import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/social.dart';

/// 单个媒体的弹幕与评论状态。
///
/// 生命周期跟随播放页：进入时 [load]，切集时丢弃重建（弹幕按内容 sha1 锚定，
/// 换一个视频就是另一份数据，复用只会串台）。
///
/// 三段式加载：
/// 1. [load] 全量拉一次弹幕与评论（两者互不阻塞，各记各的错误状态）；
/// 2. 拉完订阅 SSE，之后**只接收新增**条目，追加到本地；
/// 3. 发送走乐观更新：接口返回的新条目直接入列，SSE 随后推来的同一条按 id 去重。
class SocialStore extends ChangeNotifier {
  SocialStore({required this.path, required this.api});

  /// 媒体路径（相对用户根，如 `/movies/a.mp4`）。
  final String path;

  final ApiClient api;

  List<SocialEntry> _danmaku = const [];
  List<CommentThread> _comments = const [];

  bool _loadingDanmaku = false;
  bool _loadingComments = false;
  String? _danmakuError;
  String? _commentsError;
  bool _loaded = false;
  bool _sending = false;

  StreamSubscription<SocialEntry>? _sub;

  /// 按出现时刻升序的弹幕。
  List<SocialEntry> get danmaku => _danmaku;

  /// 顶层评论（最新在前），每条自带回复。
  List<CommentThread> get comments => _comments;

  bool get loadingDanmaku => _loadingDanmaku;
  bool get loadingComments => _loadingComments;
  String? get danmakuError => _danmakuError;
  String? get commentsError => _commentsError;

  /// 首次加载是否已完成（用于区分「还没开始」与「加载完但是空」）。
  bool get loaded => _loaded;

  /// 是否有发送 / 删除请求在飞。用于让按钮转圈并防重复提交。
  bool get sending => _sending;

  /// 评论总条数（含回复）。
  int get commentCount => _comments.fold(0, (n, t) => n + t.count);

  /// 首次加载：并行拉取，再订阅实时流。可重复调用，只有第一次会真正拉取。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await Future.wait([_loadDanmaku(), _loadComments()]);
    _subscribe();
  }

  /// 手动刷新（下拉刷新用）：重新拉取，但不动已订阅的实时流。
  Future<void> refresh() => Future.wait([_loadDanmaku(), _loadComments()]);

  Future<void> _loadDanmaku() async {
    _loadingDanmaku = true;
    _danmakuError = null;
    notifyListeners();
    try {
      final list = await api.danmakuList(path);
      _danmaku = [...list]..sort(_byOffset);
      _danmakuError = null;
    } catch (e) {
      // 400 里最常见的两种：媒体没索引、游客被禁读。message 是中文，直接展示。
      _danmakuError = _messageOf(e);
    } finally {
      _loadingDanmaku = false;
      notifyListeners();
    }
  }

  Future<void> _loadComments() async {
    _loadingComments = true;
    _commentsError = null;
    notifyListeners();
    try {
      _comments = await api.commentList(path);
      _commentsError = null;
    } catch (e) {
      _commentsError = _messageOf(e);
    } finally {
      _loadingComments = false;
      notifyListeners();
    }
  }

  /// 订阅实时流。失败静默：已经加载的内容照常可用，只是不再自动追加。
  void _subscribe() {
    _sub?.cancel();
    _sub = api
        .danmakuStream(path)
        .listen(_onLive, onError: (Object _) {}, cancelOnError: true);
  }

  void _onLive(SocialEntry e) {
    if (e.isDanmaku) {
      _addDanmaku(e);
    } else {
      _addComment(e);
    }
  }

  void _addDanmaku(SocialEntry e) {
    if (_danmaku.any((x) => x.id == e.id)) return;
    _danmaku = [..._danmaku, e]..sort(_byOffset);
    notifyListeners();
  }

  /// 把一条评论塞进现成的树：顶层评论插到最前（后端是倒序），回复挂到对应父级。
  void _addComment(SocialEntry e) {
    if (_comments.any((t) => t.root.id == e.id)) return;

    if (e.parentId.isEmpty) {
      _comments = [CommentThread(root: e, replies: const []), ..._comments];
      notifyListeners();
      return;
    }

    final idx = _comments.indexWhere((t) => t.root.id == e.parentId);
    if (idx < 0) return; // 父评论已被删除：孤儿回复不展示，与后端保持一致
    final target = _comments[idx];
    if (target.replies.any((r) => r.id == e.id)) return;
    final updated = List<CommentThread>.of(_comments)
      ..[idx] = CommentThread(
        root: target.root,
        replies: [...target.replies, e],
      );
    _comments = updated;
    notifyListeners();
  }

  /// 发弹幕。返回错误说明，`null` 表示成功。
  Future<String?> sendDanmaku({
    required int offsetMs,
    required String content,
  }) async {
    final invalid = validateDanmaku(content);
    if (invalid != null) return invalid;
    return _run(() async {
      final e = await api.sendDanmaku(
        path,
        offsetMs: offsetMs,
        content: content.trim(),
      );
      _addDanmaku(e);
    });
  }

  /// 发评论或回复。返回错误说明，`null` 表示成功。
  Future<String?> sendComment({
    required String content,
    String parentId = '',
  }) async {
    final invalid = validateComment(content);
    if (invalid != null) return invalid;
    return _run(() async {
      final e = await api.sendComment(
        path,
        content: content.trim(),
        parentId: parentId,
      );
      _addComment(e);
    });
  }

  /// 删除一条弹幕或评论。后端只允许删自己的（管理员除外），越权会返回错误说明。
  Future<String?> delete(SocialEntry e) => _run(() async {
    await api.deleteComment(path, e.id);
    if (e.isDanmaku) {
      _danmaku = _danmaku.where((x) => x.id != e.id).toList(growable: false);
    } else {
      _removeComment(e);
    }
  });

  void _removeComment(SocialEntry e) {
    // 顶层评论：整条线程连回复一起消失（后端删除是按 id 删一条，
    // 但父评论没了，回复在下一次拉取时也不会再出现）
    final topIdx = _comments.indexWhere((t) => t.root.id == e.id);
    if (topIdx >= 0) {
      _comments = List<CommentThread>.of(_comments)..removeAt(topIdx);
      notifyListeners();
      return;
    }
    final idx = _comments.indexWhere((t) => t.replies.any((r) => r.id == e.id));
    if (idx < 0) return;
    final target = _comments[idx];
    _comments = List<CommentThread>.of(_comments)
      ..[idx] = CommentThread(
        root: target.root,
        replies: target.replies
            .where((r) => r.id != e.id)
            .toList(growable: false),
      );
    notifyListeners();
  }

  /// 统一的「发送 / 删除」外壳：按钮置灰 + 错误归一。
  Future<String?> _run(Future<void> Function() body) async {
    if (_sending) return '正在发送，请稍候';
    _sending = true;
    notifyListeners();
    try {
      await body();
      return null;
    } catch (err) {
      return _messageOf(err);
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  static String _messageOf(Object e) {
    if (e is ApiException) return e.toString();
    return '请求失败：$e';
  }

  static int _byOffset(SocialEntry a, SocialEntry b) {
    final c = a.offsetMs.compareTo(b.offsetMs);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
