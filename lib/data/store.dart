import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// 全局应用状态：服务器配置、登录会话，以及本地媒体库
/// （播放记录 / 收藏 / 稍后再看）。
///
/// 全部通过 [SharedPreferences] 以 JSON 持久化，无原生依赖，卸载即清除。
class AppStore extends ChangeNotifier {
  AppStore._();

  static final AppStore instance = AppStore._();

  static const _keyServer = 'mocca.server_url';
  static const _keyToken = 'mocca.token';
  static const _keyUsername = 'mocca.username';
  static const _keyBasePath = 'mocca.base_path';
  static const _keyUserId = 'mocca.user_id';
  static const _keyRole = 'mocca.role';
  static const _keyHistory = 'mocca.history';
  static const _keyFavorites = 'mocca.favorites';
  static const _keyWatchLater = 'mocca.watch_later';
  static const _keyTheme = 'mocca.theme';
  static const _keyDanmaku = 'mocca.danmaku_visible';

  /// 默认服务器地址。首次启动即用它，无需用户填写。
  static const defaultServerUrl = 'http://mocca.vod:8000';

  /// 播放记录上限，超出后淘汰最旧的，避免无限增长。
  static const _maxHistory = 500;

  SharedPreferences? _prefs;

  /// 当前配色方案，默认暗色·抹绿。
  MoccaPalette _palette = MoccaPalette.green;

  /// 当前配色方案。切换见 [setPalette]。
  MoccaPalette get palette => _palette;

  /// 弹幕是否显示，默认开。播放页的开关与它同步。
  bool _danmakuVisible = true;

  /// 弹幕显示开关（跨页面、跨次启动沿用）。
  bool get danmakuVisible => _danmakuVisible;

  /// 服务器地址（规范化后，无尾斜杠）。
  String serverUrl = defaultServerUrl;

  /// 登录令牌。为空表示未登录。
  String? token;

  /// 已登录用户名；仅用于展示。
  String username = '';

  /// 登录用户专属资源目录（由后端返回，只读展示）。
  String basePath = '/';

  /// 登录用户的 ID（来自 `/api/me`）。
  ///
  /// 弹幕与评论用它判断「是不是我发的」——后端只允许删自己的。
  int userId = 0;

  /// 登录用户的角色：`0` 普通用户 / `1` 游客 / `2` 管理员。
  int role = 0;

  /// 管理员可以删除任何人的弹幕与评论。
  bool get isAdmin => role == 2;

  late ApiClient api = _buildApi();

  List<PlayRecord> _history = [];
  List<SavedItem> _favorites = [];
  List<SavedItem> _watchLater = [];

  bool _ready = false;
  bool get ready => _ready;

  bool get loggedIn => token != null && token!.isNotEmpty;

  /// 按最近观看时间倒序的播放记录。
  List<PlayRecord> get history => List.unmodifiable(_history);

  List<SavedItem> get favorites => List.unmodifiable(_favorites);

  List<SavedItem> get watchLater => List.unmodifiable(_watchLater);

  /// 「继续观看」：有进度、未看完、且非图片的记录。
  List<PlayRecord> get continueWatching => _history
      .where(
        (r) => r.kind != MediaKind.image && r.durationMs > 0 && !r.isFinished,
      )
      .toList(growable: false);

  /// 按当前配置构建 API 客户端。地址变化时都走这里，避免散落的构造点漏改。
  /// 接口前缀不再是可配置项，统一用 [ApiClient.defaultApiPrefix]（`/api`）。
  ApiClient _buildApi() => ApiClient(baseUrl: serverUrl, token: token);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;

    final savedServer = p.getString(_keyServer);
    serverUrl = (savedServer == null || savedServer.isEmpty)
        ? defaultServerUrl
        : savedServer;
    token = p.getString(_keyToken);
    username = p.getString(_keyUsername) ?? '';
    basePath = p.getString(_keyBasePath) ?? '/';
    userId = p.getInt(_keyUserId) ?? 0;
    role = p.getInt(_keyRole) ?? 0;

    _history = _decodeList(p.getString(_keyHistory), PlayRecord.fromJson);
    _favorites = _decodeList(p.getString(_keyFavorites), SavedItem.fromJson);
    _watchLater = _decodeList(p.getString(_keyWatchLater), SavedItem.fromJson);
    _sortHistory();
    _palette = _readPalette(p.getString(_keyTheme));
    _danmakuVisible = p.getBool(_keyDanmaku) ?? true;

    api = _buildApi();
    _ready = true;
    notifyListeners();
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => fromJson(e.cast<String, dynamic>()))
          .where((e) => (e as dynamic).path.toString().isNotEmpty)
          .toList();
    } catch (_) {
      // 本地数据损坏时从空开始，不阻塞启动
      return [];
    }
  }

  Future<void> _write(String key, Object value) async {
    await _prefs?.setString(key, jsonEncode(value));
  }

  void _sortHistory() {
    _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  // ---------------------------------------------------------------- 外观

  /// 从持久化取值解析配色；未知字符串回退到默认（抹绿）。
  static MoccaPalette _readPalette(String? raw) {
    if (raw == null) return MoccaPalette.green;
    for (final p in MoccaPalette.values) {
      if (p.name == raw) return p;
    }
    return MoccaPalette.green;
  }

  /// 切换配色并持久化。界面上即点即改。
  Future<void> setPalette(MoccaPalette value) async {
    if (value == _palette) return;
    _palette = value;
    await _prefs?.setString(_keyTheme, value.name);
    notifyListeners();
  }

  /// 记住弹幕显示开关，下次进播放页沿用。
  Future<void> setDanmakuVisible(bool value) async {
    if (value == _danmakuVisible) return;
    _danmakuVisible = value;
    await _prefs?.setBool(_keyDanmaku, value);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 服务器

  /// 保存服务器地址（不校验连通性）。
  Future<void> setServerUrl(String url) async {
    serverUrl = ApiClient.normalizeBaseUrl(url);
    api.setBaseUrl(serverUrl);
    await _prefs?.setString(_keyServer, serverUrl);
    notifyListeners();
  }

  /// 注册新账号，随后自动登录。
  Future<void> register(String user, String password) async {
    if (serverUrl.isEmpty) throw ApiException(0, '请先设置服务器地址');
    await api.register(user, password);
    await login(user, password);
  }

  /// 使用用户名密码登录并保存令牌。
  Future<void> login(String user, String password) async {
    if (serverUrl.isEmpty) throw ApiException(0, '请先设置服务器地址');
    final t = await api.login(user, password);

    // 登录后立刻取用户信息，拿到专属目录 base_path
    api.token = t;
    final session = await api.me();

    await _applySession(t, session);
  }

  /// 直接使用管理员令牌（适合只做播放、不需要账号的场景）。
  Future<void> loginWithToken(String t) async {
    api.token = t;
    final session = await api.me();
    await _applySession(t, session);
  }

  /// 落地登录结果：内存状态与持久化一起更新。
  ///
  /// [Session.id] 要一并存下来：弹幕与评论的「删除」按钮得拿它比对作者。
  Future<void> _applySession(String t, Session session) {
    token = t;
    username = session.username;
    basePath = session.basePath;
    userId = session.id;
    role = session.role;

    final p = _prefs;
    final writes = <Future<void>>[
      if (p != null) p.setString(_keyToken, t),
      if (p != null) p.setString(_keyUsername, username),
      if (p != null) p.setString(_keyBasePath, basePath),
      if (p != null) p.setInt(_keyUserId, userId),
      if (p != null) p.setInt(_keyRole, role),
    ];
    notifyListeners();
    return Future.wait(writes);
  }

  Future<void> logout() async {
    token = null;
    username = '';
    basePath = '/';
    userId = 0;
    role = 0;
    api.token = null;
    final p = _prefs;
    final writes = <Future<void>>[
      if (p != null) p.remove(_keyToken),
      if (p != null) p.remove(_keyUsername),
      if (p != null) p.remove(_keyBasePath),
      if (p != null) p.remove(_keyUserId),
      if (p != null) p.remove(_keyRole),
    ];
    notifyListeners();
    await Future.wait(writes);
  }

  // ------------------------------------------------------------ 播放记录

  PlayRecord? recordFor(String path) {
    for (final r in _history) {
      if (r.path == path) return r;
    }
    return null;
  }

  /// 写入 / 更新一条播放记录。
  ///
  /// [watchedDeltaMs] 是本次新增的观看时长，会累加到历史总时长上；
  /// 播放器按固定间隔调用，因此这里做累加而不是覆盖。
  Future<void> upsertRecord({
    required String path,
    required String name,
    required int kind,
    required int positionMs,
    required int durationMs,
    int watchedDeltaMs = 0,
    String thumb = '',
  }) async {
    if (path.isEmpty) return;
    final existing = recordFor(path);
    if (existing != null) {
      existing.positionMs = positionMs;
      if (durationMs > 0) existing.durationMs = durationMs;
      existing.watchedMs += watchedDeltaMs;
      // 只在本次拿到有效缩略图时覆盖，避免把已有值清空
      if (thumb.isNotEmpty) existing.thumb = thumb;
      existing.updatedAt = DateTime.now();
    } else {
      _history.add(
        PlayRecord(
          path: path,
          name: name,
          kind: kind,
          positionMs: positionMs,
          durationMs: durationMs,
          watchedMs: watchedDeltaMs,
          thumb: thumb,
        ),
      );
    }
    _sortHistory();
    if (_history.length > _maxHistory) {
      _history = _history.sublist(0, _maxHistory);
    }
    await _write(
      _keyHistory,
      _history.map((e) => e.toJson()).toList(growable: false),
    );
    notifyListeners();
  }

  Future<void> removeRecord(String path) async {
    _history.removeWhere((r) => r.path == path);
    await _write(
      _keyHistory,
      _history.map((e) => e.toJson()).toList(growable: false),
    );
    notifyListeners();
  }

  /// 清空记录，可按类型过滤（如只清视频）。
  Future<void> clearHistory({int? kind}) async {
    if (kind == null) {
      _history.clear();
    } else {
      _history.removeWhere((r) => r.kind == kind);
    }
    await _write(
      _keyHistory,
      _history.map((e) => e.toJson()).toList(growable: false),
    );
    notifyListeners();
  }

  /// 仅清除播放进度但保留记录（用于「从头开始」）。
  Future<void> resetProgress(String path) async {
    final r = recordFor(path);
    if (r == null) return;
    r.positionMs = 0;
    await _write(
      _keyHistory,
      _history.map((e) => e.toJson()).toList(growable: false),
    );
    notifyListeners();
  }

  // ------------------------------------------------------- 收藏 / 稍后再看

  List<SavedItem> _listFor(SavedGroup group) =>
      group == SavedGroup.favorite ? _favorites : _watchLater;

  String _keyFor(SavedGroup group) =>
      group == SavedGroup.favorite ? _keyFavorites : _keyWatchLater;

  bool contains(SavedGroup group, String path) =>
      _listFor(group).any((e) => e.path == path);

  Future<void> add(SavedGroup group, SavedItem item) async {
    final list = _listFor(group);
    if (list.any((e) => e.path == item.path)) return;
    list.insert(0, item);
    await _write(_keyFor(group), list.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  Future<void> remove(SavedGroup group, String path) async {
    final list = _listFor(group)..removeWhere((e) => e.path == path);
    await _write(_keyFor(group), list.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  Future<bool> toggle(SavedGroup group, SavedItem item) async {
    if (contains(group, item.path)) {
      await remove(group, item.path);
      return false;
    }
    await add(group, item);
    return true;
  }

  Future<void> clear(SavedGroup group) async {
    _listFor(group).clear();
    await _write(_keyFor(group), <Object>[]);
    notifyListeners();
  }

  /// 条目在收藏 / 稍后再看中的归属，用于在界面上点亮图标。
  ({bool favorite, bool later}) marksOf(String path) => (
    favorite: contains(SavedGroup.favorite, path),
    later: contains(SavedGroup.watchLater, path),
  );
}

/// 两个结构相同的本地收藏分组。
enum SavedGroup {
  favorite('收藏'),
  watchLater('稍后再看');

  const SavedGroup(this.label);
  final String label;
}
