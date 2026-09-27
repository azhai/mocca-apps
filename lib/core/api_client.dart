import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'models.dart';
import 'social.dart';

/// 后端返回的业务异常。
///
/// 注意：后端约定「业务错误也返回 HTTP 200」，错误码在响应体的 `code` 里，
/// 因此不能只看 HTTP 状态码，必须解析信封。
class ApiException implements Exception {
  ApiException(this.code, this.message);

  final int code;
  final String message;

  bool get isUnauthorized => code == 401 || code == 403;

  @override
  String toString() => message.isEmpty ? '请求失败（$code）' : message;
}

/// Mocca 后端 API 客户端。
///
/// 只覆盖本应用需要的端点：
/// - `POST /api/auth/login/hash` 登录
/// - `GET  /api/me`             当前用户
/// - `POST /api/fs/list`        列目录
/// - `POST /api/fs/get`         取详情（含可播放的 `raw_url`）
///
/// 弹幕与评论（写入均需登录，读取游客可见，受服务端 `allow_guest` 约束）：
/// - `GET    /api/danmaku`        弹幕列表（可按 `from` / `to` 取时间窗）
/// - `POST   /api/danmaku`        发弹幕
/// - `GET    /api/comments`       评论（顶层 + 回复）
/// - `POST   /api/comments`       发评论 / 回复
/// - `DELETE /api/comments`       删自己的评论或弹幕（管理员可删任何人的）
/// - `GET    /api/danmaku/stream` SSE 实时推送新增条目
///
/// 注意弹幕按媒体内容的 sha1 锚定，不是按路径：媒体未索引时这些接口统一返回
/// `code:400`，message 里会提示「该媒体还没有索引」。
class ApiClient {
  ApiClient({
    String baseUrl = '',
    this.apiPrefix = defaultApiPrefix,
    this.token,
  }) : _baseUrl = normalizeBaseUrl(baseUrl) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        // 流媒体地址不做下载，但目录列举在慢速存储上可能较久
        receiveTimeout: const Duration(seconds: 30),
        // 交由我们自己解析信封，不让 Dio 因 4xx/5xx 抛异常
        validateStatus: (_) => true,
      ),
    );
  }

  /// 默认接口前缀：后端所有业务接口都挂在 `/api` 之下。
  static const defaultApiPrefix = '/api';

  late final Dio _dio;
  String _baseUrl;

  /// 接口前缀，固定为 `/api`：后端所有业务接口都挂在这一层。
  /// 保留为字段是为了让 [apiBase] 与 [pingAt] 共用同一处定义。
  String apiPrefix;

  /// 当前凭证（JWT 或管理员令牌）。为空表示未登录。
  String? token;

  String get baseUrl => _baseUrl;

  /// 业务接口的完整前缀（不含尾斜杠）。
  String get apiBase => '$_baseUrl$apiPrefix';

  /// 规范化用户输入的服务器地址：
  /// 补全协议、去掉尾部斜杠、校验 host 合法。
  static String normalizeBaseUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return '';

    // 去掉末尾斜杠，但保留可能存在的子路径前缀（如 /nas）
    final rawPath = uri.path;
    final path = rawPath.length > 1 && rawPath.endsWith('/')
        ? rawPath.substring(0, rawPath.length - 1)
        : rawPath;

    // 注意：不要用 uri.replace(query: '', fragment: '') —— 那会生成 "...?#"，
    // 而尾部这个 "?#" 会让 Uri.resolve 把最后一段路径当成文件名，
    // 导致子路径部署（如 /nas）下的相对播放地址丢失前缀。
    // 直接重建 URI 才能真正丢弃查询串与锚点。
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  void setBaseUrl(String url) {
    _baseUrl = normalizeBaseUrl(url);
  }

  /// 单次探活。返回 `(错误说明, 主机是否可达)`。
  ///
  /// 第二个返回值用于区分「主机连不上」与「主机在但该路径不存在」：
  /// 前者没必要再试别的路径（会白白多等一个超时）。
  Future<(String?, bool)> _pingOnce(String pingUrl) async {
    try {
      final res = await _dio.get<String>(
        pingUrl,
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode == 200 && (res.data ?? '').trim() == 'pong') {
        return (null, true);
      }
      return ('服务器响应异常（HTTP ${res.statusCode}）', true);
    } on DioException catch (e) {
      final reachable =
          e.type != DioExceptionType.connectionError &&
          e.type != DioExceptionType.connectionTimeout;
      return (_describeDioError(e), reachable);
    }
  }

  /// 探测指定地址是否可用：返回 null 表示可达。
  ///
  /// 接口前缀同样加在探活地址之前（后端在 `/api` 下也注册了 `/ping` 别名）。
  /// 若服务器只提供根路径的 `/ping`（旧版本，或反代把前缀剥掉了），
  /// 会在「主机可达但路径 404」时回退到根路径再试一次，避免误判为不可达。
  Future<String?> pingAt(String baseUrl) async {
    final url = normalizeBaseUrl(baseUrl);
    if (url.isEmpty) return '地址为空';

    final candidates = <String>[
      if (apiPrefix.isNotEmpty) '$url$apiPrefix/ping',
      '$url/ping',
    ];

    String? lastError;
    for (final candidate in candidates) {
      final (err, reachable) = await _pingOnce(candidate);
      if (err == null) return null;
      lastError = err;
      // 主机都连不上，再试别的路径没有意义
      if (!reachable) return err;
    }
    return lastError;
  }

  /// 把后端返回的相对地址（如 `/d/movies/a.mp4?sign=...`）补全为绝对地址。
  ///
  /// 子路径部署时后端返回的路径已含前缀，直接基于 origin 解析即可；
  /// 给 base 补上尾斜杠可同时正确处理相对与绝对两种形式。
  String resolveUrl(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return '';
    final parsed = Uri.tryParse(r);
    if (parsed != null && parsed.hasScheme) return r;
    if (_baseUrl.isEmpty) return r;
    final base = Uri.parse(_baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/');
    return base.resolve(r).toString();
  }

  /// 封面取图地址。
  ///
  /// 后端的 `thumb` 字段恒为空（mocca-serv `docs/API.md` §4.2 写明「本服务不生成
  /// 缩略图」），视频/音频的封面要走根路径下的 `/meta/poster`。令牌只能放查询串
  /// —— 图片组件带不了自定义请求头。
  String posterUrl(String path) {
    final q = <String, String>{'path': path};
    final t = token;
    if (t != null && t.isNotEmpty) q['token'] = t;
    return resolveUrl('/meta/poster?${Uri(queryParameters: q).query}');
  }

  /// 取流直链，图片缩略图也走它。
  ///
  /// 网格一屏几十张图，逐张调 `/api/fs/get` 太浪费，这里按服务端 web UI 的做法
  /// 直接拼 `/d/<路径>`（与 [MediaDetail.rawUrl] 同一形式），令牌走查询串。
  /// 路径按段编码：中文名与 `#`、`?` 这类字符不编码会被当成路径分隔或查询串。
  String directUrl(String path) {
    final segs = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final q = <String, String>{};
    final t = token;
    if (t != null && t.isNotEmpty) q['token'] = t;
    final s = Uri(queryParameters: q).query;
    return resolveUrl('/d/$segs${s.isEmpty ? '' : '?$s'}');
  }

  /// 按类型给出封面地址；没有封面的类型返回 null。
  ///
  /// 后端的 `thumb` 字段恒为空，客户端只能自己按类型拼：视频/音频走
  /// [posterUrl]（服务端抽帧生成的海报），图片直接取原图。浏览页、历史页、
  /// 播放页都要同一份规则，集中在这里免得各处漂移。
  String? coverUrl(int kind, String path) => switch (kind) {
    MediaKind.video || MediaKind.audio => posterUrl(path),
    MediaKind.image => directUrl(path),
    _ => null,
  };

  /// 登录所需的「静态哈希」。
  ///
  /// 与后端 `model.StaticHash` 保持一致：
  /// `sha256(明文密码 + "-" + "https://github.com/alist-org/alist")`，小写十六进制。
  static String staticHash(String password) {
    const salt = 'https://github.com/alist-org/alist';
    return sha256.convert(utf8.encode('$password-$salt')).toString();
  }

  Options get _jsonOptions {
    final t = token;
    return Options(
      contentType: Headers.jsonContentType,
      headers: {if (t != null && t.isNotEmpty) 'Authorization': t},
    );
  }

  /// 解析统一信封，失败即抛 [ApiException]。
  T _unwrap<T>(Response response, T Function(dynamic data) parse) {
    final body = response.data;
    if (body is! Map) {
      throw ApiException(response.statusCode ?? 0, '服务器返回了非预期内容');
    }
    final code = (body['code'] as num?)?.toInt() ?? -1;
    final message = (body['message'] ?? '').toString();
    if (code != 200) throw ApiException(code, message);
    return parse(body['data']);
  }

  /// 连通性探测：`/ping` 返回纯文本 `pong`。
  ///
  /// 注意 `/ping` 挂在根上，**不**经过 [apiPrefix]。
  /// 返回 null 表示成功，否则返回错误说明。
  Future<String?> ping() async {
    if (_baseUrl.isEmpty) return '请先填写服务器地址';
    return pingAt(_baseUrl);
  }

  /// 用户名 + 明文密码登录，返回 JWT。
  Future<String> login(String username, String password) async {
    final res = await _dio.post(
      '$apiBase/auth/login/hash',
      data: {'username': username, 'password': staticHash(password)},
      options: _jsonOptions,
    );
    return _unwrap(res, (data) {
      final token = (data is Map ? data['token'] : null)?.toString() ?? '';
      if (token.isEmpty) throw ApiException(500, '登录成功但未返回令牌');
      return token;
    });
  }

  /// 注册新账号。
  ///
  /// 密码同样先做静态哈希再传输，与 [login] 保持一致的约定。
  /// 后端以 `POST {api}/auth/register` 提供该能力；若服务端未开启注册，
  /// 会返回业务错误码，这里原样抛出 [ApiException] 供界面提示。
  Future<void> register(String username, String password) async {
    final res = await _dio.post(
      '$apiBase/auth/register',
      data: {'username': username, 'password': staticHash(password)},
      options: _jsonOptions,
    );
    _unwrap(res, (_) => null);
  }

  /// 当前凭证对应的用户。
  Future<Session> me() async {
    final res = await _dio.get('$apiBase/me', options: _jsonOptions);
    return _unwrap(res, (data) => Session.fromJson((data as Map).cast()));
  }

  /// 列目录。[path] 使用相对根的路径（如 `/movies`）；
  /// 若已登录，后端会自动拼上该用户的专属目录 `base_path`。
  Future<List<MediaObj>> list(String path, {String? password}) async {
    final res = await _dio.post(
      '$apiBase/fs/list',
      data: {
        'path': path.isEmpty ? '/' : path,
        if (password != null && password.isNotEmpty) 'password': password,
        'page': 1,
        'per_page': 0, // 0 = 不分页，一次取全
      },
      options: _jsonOptions,
    );
    return _unwrap(res, (data) {
      if (data is! Map) return <MediaObj>[];
      final content = data['content'];
      if (content is! List) return <MediaObj>[];
      return content
          .whereType<Map>()
          .map((e) => MediaObj.fromJson(e.cast()))
          .toList(growable: false);
    });
  }

  /// 取单个对象的详情，其中 `raw_url` 可直接交给播放器。
  Future<MediaDetail> get(String path, {String? password}) async {
    final res = await _dio.post(
      '$apiBase/fs/get',
      data: {
        'path': path,
        if (password != null && password.isNotEmpty) 'password': password,
      },
      options: _jsonOptions,
    );
    return _unwrap(res, (data) => MediaDetail.fromJson((data as Map).cast()));
  }

  // ────────────────────────────────────────────── 弹幕与评论

  static List<SocialEntry> _parseEntries(dynamic data) {
    if (data is! List) return <SocialEntry>[];
    return data
        .whereType<Map>()
        .map((e) => SocialEntry.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// 某媒体的全部弹幕。接口没有分页——弹幕本来就是一次取全。
  ///
  /// [fromMs] / [toMs] 为毫秒区间（含端点），用于只取时间轴上的一段；
  /// 播放器通常全量取，再在本地按播放位置调度。
  Future<List<SocialEntry>> danmakuList(
    String path, {
    int? fromMs,
    int? toMs,
  }) async {
    final res = await _dio.get(
      '$apiBase/danmaku',
      queryParameters: {
        'path': path,
        if (fromMs != null) 'from': '$fromMs',
        if (toMs != null) 'to': '$toMs',
      },
      options: _jsonOptions,
    );
    return _unwrap(res, _parseEntries);
  }

  /// 发一条弹幕，[offsetMs] 是它在时间轴上出现的时刻（毫秒）。
  ///
  /// 需登录，否则后端返回 `code:401`。
  Future<SocialEntry> sendDanmaku(
    String path, {
    required int offsetMs,
    required String content,
  }) async {
    final res = await _dio.post(
      '$apiBase/danmaku',
      data: {'path': path, 'offset': offsetMs, 'content': content},
      options: _jsonOptions,
    );
    return _unwrap(
      res,
      (data) => SocialEntry.fromJson((data as Map).cast<String, dynamic>()),
    );
  }

  /// 某媒体的评论：顶层评论倒序（最新在最上），每条自带 `replies`。
  ///
  /// 不要在本地重新组装父子关系——后端已按「父评论被删则回复不展示」处理过。
  Future<List<CommentThread>> commentList(String path) async {
    final res = await _dio.get(
      '$apiBase/comments',
      queryParameters: {'path': path},
      options: _jsonOptions,
    );
    return _unwrap(res, (data) {
      if (data is! List) return <CommentThread>[];
      return data
          .whereType<Map>()
          .map((e) => CommentThread.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    });
  }

  /// 发评论；给了 [parentId] 就是回复某条评论（只支持一层）。
  Future<SocialEntry> sendComment(
    String path, {
    required String content,
    String parentId = '',
  }) async {
    final res = await _dio.post(
      '$apiBase/comments',
      data: {'path': path, 'content': content, 'parent_id': parentId},
      options: _jsonOptions,
    );
    return _unwrap(
      res,
      (data) => SocialEntry.fromJson((data as Map).cast<String, dynamic>()),
    );
  }

  /// 删除自己发的评论或弹幕（管理员可删任何人的）。弹幕没有单独的删除接口。
  Future<void> deleteComment(String path, String id) async {
    final res = await _dio.delete(
      '$apiBase/comments',
      data: {'path': path, 'id': id},
      options: _jsonOptions,
    );
    _unwrap(res, (_) => null);
  }

  /// 订阅某媒体的实时弹幕 / 评论（SSE）。
  ///
  /// **只推送新增条目**——历史要先调一次 [danmakuList] / [commentList]。
  /// 订阅会在流被取消或连接断开时结束；后端每 15 秒发一行注释帧保活。
  ///
  /// 令牌走查询串而不是请求头：EventSource 语义下没法自定义头，后端
  /// `middlewares.TokenFrom` 两种取法都支持，这里用更通用的那种。
  Stream<SocialEntry> danmakuStream(String path) async* {
    final t = token;
    final res = await _dio.get<ResponseBody>(
      '$apiBase/danmaku/stream',
      queryParameters: {
        'path': path,
        if (t != null && t.isNotEmpty) 'token': t,
      },
      options: Options(
        responseType: ResponseType.stream,
        // dio 的 per-request receiveTimeout 为 null 时会回退到 BaseOptions 的
        // 30 秒，长连接会被掐断。这里给一个足够大的值（SSE 自带心跳，
        // 真断了由服务端关闭连接）。
        receiveTimeout: _streamTimeout,
      ),
    );

    final body = res.data;
    if (body == null) return;

    var buffer = '';
    // body.stream 是 Stream<Uint8List>，而 utf8.decoder 是
    // StreamTransformer<List<int>, String> —— 输入类型是逆变的，必须先向上转型
    // 才能接得上。
    final text = body.stream.cast<List<int>>().transform(utf8.decoder);
    await for (final chunk in text) {
      buffer += chunk;
      // 帧以空行结尾；可能一次收到多帧，也可能一帧分多次收到
      var idx = buffer.indexOf('\n\n');
      while (idx >= 0) {
        final frame = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        final entry = parseDanmakuFrame(frame);
        if (entry != null) yield entry;
        idx = buffer.indexOf('\n\n');
      }
    }
  }

  /// SSE 长连接的读取超时：给到 1 天，实际不会触发（服务端 15 秒一次心跳）。
  static const Duration _streamTimeout = Duration(days: 1);

  static String _describeDioError(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout => '连接超时，请检查服务器地址与网络',
    DioExceptionType.receiveTimeout => '读取超时，服务器响应过慢',
    DioExceptionType.sendTimeout => '发送超时',
    DioExceptionType.connectionError => '无法连接服务器，请确认地址与端口正确',
    DioExceptionType.badCertificate => '服务器证书无效',
    DioExceptionType.cancel => '请求已取消',
    _ => '网络错误：${e.message ?? e.type.name}',
  };

  /// 把 Dio 异常包装成用户可读的 [ApiException]。
  static ApiException wrapDio(DioException e) {
    if (e.error is ApiException) return e.error as ApiException;
    return ApiException(0, _describeDioError(e));
  }
}

/// 统一处理网络异常，避免每个调用点都写 try/catch 映射。
extension ApiCall<T> on Future<T> {
  Future<T> mapErrors() => catchError((Object e) {
    if (e is DioException) throw ApiClient.wrapDio(e);
    throw e;
  });
}
