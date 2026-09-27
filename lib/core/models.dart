/// 与 Mocca 后端契约对齐的数据模型。
///
/// 后端统一响应信封为 `{ "code": 200, "message": "...", "data": {...} }`，
/// 业务错误也走 HTTP 200，错误信息在 `code` 中；仅认证中间件拦截（401）
/// 与路由未命中（404）使用真实 HTTP 状态码。
library;

/// 媒体类型，取值与后端 `ObjType` 一致。
abstract final class MediaKind {
  static const int dir = 0;
  static const int unknown = 1;
  static const int video = 2;
  static const int audio = 3;
  static const int text = 4;
  static const int image = 5;

  /// 本应用能直接播放 / 查看的类型。
  static bool isPlayable(int t) => t == video || t == audio || t == image;

  static bool isImage(int t) => t == image;

  static String label(int t) => switch (t) {
    dir => '目录',
    video => '视频',
    audio => '音频',
    image => '图片',
    text => '文本',
    _ => '文件',
  };
}

/// 目录中的一个条目，对应 `/api/fs/list` 的 `content[]`。
class MediaObj {
  const MediaObj({
    required this.name,
    required this.size,
    required this.isDir,
    required this.type,
    this.sign = '',
    this.thumb = '',
    this.modified,
    this.isMount = false,
  });

  final String name;
  final int size;
  final bool isDir;
  final int type;

  /// 是否为挂载点（存储 / 驱动）。Alist 兼容后端的根目录顶级条目通常是挂载点，
  /// 用于在界面上与普通目录区分。
  final bool isMount;

  /// 受保护路径才非空；下载时需要拼到 URL 上。
  final String sign;
  final String thumb;
  final DateTime? modified;

  factory MediaObj.fromJson(Map<String, dynamic> json) => MediaObj(
    name: (json['name'] ?? '') as String,
    size: (json['size'] as num?)?.toInt() ?? 0,
    isDir: json['is_dir'] == true,
    type: (json['type'] as num?)?.toInt() ?? MediaKind.unknown,
    sign: (json['sign'] ?? '') as String,
    thumb: (json['thumb'] ?? '') as String,
    modified: DateTime.tryParse((json['modified'] ?? '') as String),
    isMount: json['mount'] == true,
  );
}

/// `/api/fs/get` 的详情：在列表条目基础上追加可播放地址。
class MediaDetail {
  const MediaDetail({
    required this.obj,
    required this.rawUrl,
    this.header = '',
    this.provider = '',
  });

  final MediaObj obj;

  /// 可直接播放的地址（需要签名时后端已带 `?sign=`）。
  /// 通常是相对路径，需用 [ApiClient.resolveUrl] 补全。
  final String rawUrl;

  /// 该对象要求的额外请求头（后端以字符串形式给出，如 `Referer: ...`）。
  final String header;
  final String provider;

  factory MediaDetail.fromJson(Map<String, dynamic> json) => MediaDetail(
    obj: MediaObj.fromJson(json),
    rawUrl: (json['raw_url'] ?? '') as String,
    header: (json['header'] ?? '') as String,
    provider: (json['provider'] ?? '') as String,
  );

  /// 把后端返回的 header 字符串解析成请求头映射。
  ///
  /// 后端格式为多行 `Key: Value`，仅取合法行，避免把脏数据塞进 HTTP 头。
  Map<String, String> parsedHeaders() {
    if (header.trim().isEmpty) return const {};
    final result = <String, String>{};
    for (final line in header.split('\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
  }
}

/// 当前登录用户，对应 `/api/me`。
class Session {
  const Session({
    required this.username,
    required this.role,
    this.basePath = '/',
    this.id = 0,
    this.avatar = '',
  });

  final String username;

  /// `0` = 普通用户（有账号、需登录、只看自身专属目录）
  /// `1` = 游客　`2` = 运维账号
  final int role;

  /// 用户 ID，来自 `/api/me`。
  ///
  /// 弹幕与评论要拿它跟 [SocialEntry.userId] 比对，才能判断「这是不是我发的」
  /// ——后端只允许删自己的（管理员除外）。
  final int id;

  /// 头像预设 key（如 `01`），来自 `/api/me`。
  final String avatar;

  /// 专属资源目录：所有文件请求都会被后端拼接到该路径之下。
  final String basePath;

  bool get isGuest => role == 1;
  bool get isAdmin => role == 2;

  String get roleLabel => switch (role) {
    0 => '用户',
    1 => '游客',
    2 => '管理员',
    _ => '未知',
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    username: (json['username'] ?? '') as String,
    role: (json['role'] as num?)?.toInt() ?? 0,
    basePath: (json['base_path'] ?? '/') as String,
    id: (json['id'] as num?)?.toInt() ?? 0,
    avatar: (json['avatar'] ?? '') as String,
  );
}

/// 播放记录：记住「看到哪」与「看了多久」。
class PlayRecord {
  PlayRecord({
    required this.path,
    required this.name,
    required this.kind,
    this.positionMs = 0,
    this.durationMs = 0,
    this.watchedMs = 0,
    DateTime? updatedAt,
    this.thumb = '',
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// 后端路径，作为唯一键。
  final String path;
  String name;
  final int kind;

  /// 上次停顿位置（毫秒）——用于续播。
  int positionMs;

  /// 媒体总时长（毫秒）；直播或未知时为 0。
  int durationMs;

  /// 累计观看时长（毫秒）——跨多次播放累加。
  int watchedMs;

  /// 最近一次观看时间。
  DateTime updatedAt;

  String thumb;

  /// 观看进度 0~1；时长未知时返回 0。
  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// 是否已基本看完（≥95%），用于在列表中区分「看完」与「看了一半」。
  bool get isFinished => durationMs > 0 && progress >= 0.95;

  /// 续播位置：接近开头时从头播放，避免「刚点开就跳到片尾」的观感。
  int get resumeMs => positionMs < 5000 ? 0 : positionMs;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'kind': kind,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'watchedMs': watchedMs,
    'updatedAt': updatedAt.toIso8601String(),
    'thumb': thumb,
  };

  factory PlayRecord.fromJson(Map<String, dynamic> json) => PlayRecord(
    path: (json['path'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    kind: (json['kind'] as num?)?.toInt() ?? MediaKind.unknown,
    positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    watchedMs: (json['watchedMs'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String),
    thumb: (json['thumb'] ?? '') as String,
  );
}

/// 收藏 / 稍后再看 的条目。两者结构相同，用两个列表区分。
class SavedItem {
  SavedItem({
    required this.path,
    required this.name,
    required this.kind,
    DateTime? addedAt,
    this.thumb = '',
  }) : addedAt = addedAt ?? DateTime.now();

  final String path;
  final String name;
  final int kind;
  final DateTime addedAt;
  final String thumb;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'kind': kind,
    'addedAt': addedAt.toIso8601String(),
    'thumb': thumb,
  };

  factory SavedItem.fromJson(Map<String, dynamic> json) => SavedItem(
    path: (json['path'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    kind: (json['kind'] as num?)?.toInt() ?? MediaKind.unknown,
    addedAt: DateTime.tryParse((json['addedAt'] ?? '') as String),
    thumb: (json['thumb'] ?? '') as String,
  );
}
