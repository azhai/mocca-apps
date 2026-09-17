import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../data/store.dart';

/// MP4 视频播放页。
///
/// 进度记忆的关键点：
/// - 初始化完成后 seek 到上次停顿位置（[PlayRecord.resumeMs]）
/// - 每 5 秒落一次盘（位置 + 本次新增观看时长）
/// - 暂停、退到后台、退出页面时各落一次盘，避免丢进度
///
/// 选集：传入同目录下的 [siblings] 后，可用右下角「选集」在右侧展开列表，
/// 点击即可切换到同目录的其他视频（顶部 [path] / [title] / [url] 等为初始项）。
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.path,
    required this.title,
    required this.url,
    this.headers = const {},
    this.thumb = '',
    this.siblings = const [],
    this.index = 0,
    this.password,
  });

  final String path;
  final String title;
  final String url;
  final Map<String, String> headers;
  final String thumb;

  /// 同目录下的可播放视频（含当前项），用于「选集」。
  final List<({MediaObj obj, String path})> siblings;

  /// 当前项在 [siblings] 中的下标。
  final int index;

  /// 受保护目录的访问密码（如有）。
  final String? password;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Timer? _ticker;

  String? _error;
  bool _ready = false;
  bool _controlsVisible = true;
  double _speed = 1.0;

  /// 手动指定的屏幕方向：null = 跟随片源比例（自动），true = 强制横屏，
  /// false = 强制竖屏。右上角「横竖屏切换」按钮按下后生效。
  bool? _manualLandscape;

  /// 上次落盘时的播放位置，用于计算「本次新增观看时长」。
  int _lastSavedPositionMs = 0;

  /// 选集面板是否展开。
  bool _showPlaylist = false;

  // —— 当前正在播放的项（切换选集时会变化）——
  late String _curPath;
  late String _curTitle;
  late String _curUrl;
  late Map<String, String> _curHeaders;
  late String _curThumb;
  late int _curIndex;

  PlayRecord? get _record => AppStore.instance.recordFor(_curPath);

  /// 当前是否为横屏：未手动指定时按片源比例判断，手动指定后以 [_manualLandscape] 为准。
  bool get _isLandscape {
    final manual = _manualLandscape;
    if (manual != null) return manual;
    final ratio = _controller?.value.aspectRatio ?? 1.0;
    return ratio > 1.0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _curPath = widget.path;
    _curTitle = widget.title;
    _curUrl = widget.url;
    _curHeaders = widget.headers;
    _curThumb = widget.thumb;
    _curIndex = widget.index;
    _loadCurrent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    // 先落盘再销毁控制器：此时 position 仍然可读
    unawaited(_persist());
    _controller?.dispose();
    // 退出播放务必恢复竖屏：否则用户回到列表页时会被留在横屏，
    // 而列表页是按竖屏排版的，观感会很突兀。
    unawaited(restorePortrait());
    super.dispose();
  }

  /// 按视频自身比例选择屏幕方向。
  ///
  /// - 宽 > 高（16:9 等横向片源）→ 横屏，并进入沉浸式全屏
  /// - 宽 <= 高（竖屏短视频、手机拍摄）→ 保持竖屏，不隐藏状态栏
  ///
  /// 用 [VideoPlayerValue.aspectRatio] 而不是设备当前方向来判断，
  /// 这样即使手机此刻横着拿，竖屏片源也不会被错误地拉成横屏。
  Future<void> _applyOrientationFor(double aspectRatio) async {
    final isWide = aspectRatio > 1.0;
    if (isWide) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  /// 手动设定屏幕方向：横屏进入沉浸式全屏，竖屏恢复状态栏（与 [_applyOrientationFor] 行为一致）。
  Future<void> _setOrientation(bool landscape) async {
    if (landscape) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  /// 在横屏 / 竖屏之间手动切换；首次切换前按片源比例决定起点。
  void _toggleOrientation() {
    final next = !_isLandscape;
    _manualLandscape = next;
    unawaited(_setOrientation(next));
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persist());
    }
  }

  /// 加载（或重新加载）当前 [_curPath] 指向的视频。
  Future<void> _loadCurrent() async {
    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = null;
    });

    _lastSavedPositionMs = _record?.positionMs ?? 0;

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_curUrl),
      httpHeaders: _curHeaders,
    );
    _controller = controller;
    try {
      await controller.initialize();

      // 续播：接近片头时从头开始，避免「一点开就跳到片尾」
      final resume = _record?.resumeMs ?? 0;
      if (resume > 0 && resume < controller.value.duration.inMilliseconds) {
        await controller.seekTo(Duration(milliseconds: resume));
      }

      // 拿到真实比例后再决定横竖屏，避免先转屏再转回来
      await _applyOrientationFor(controller.value.aspectRatio);

      controller.addListener(_onControllerUpdate);
      await controller.play();

      // 每 5 秒记录一次进度
      _ticker?.cancel();
      _ticker = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_persist()),
      );

      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      // 初始化失败时也要还原方向，不能把用户留在横屏
      unawaited(restorePortrait());
      if (!mounted) return;
      setState(() => _error = '无法播放该视频：$e');
    }
  }

  /// 切换到选集中的第 [index] 项：先保存当前进度，再解析新地址并重新加载。
  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= widget.siblings.length || index == _curIndex) {
      if (mounted) setState(() => _showPlaylist = false);
      return;
    }

    // 先保存当前进度，再销毁旧控制器
    await _persist();
    _ticker?.cancel();
    final old = _controller;
    if (old != null) {
      old.removeListener(_onControllerUpdate);
      await old.dispose();
    }
    _controller = null;
    _manualLandscape = null;

    try {
      final store = AppStore.instance;
      final detail = await store.api.get(
        widget.siblings[index].path,
        password: widget.password,
      );
      final url = store.api.resolveUrl(detail.rawUrl);
      if (url.isEmpty) throw ApiException(500, '服务器未返回可播放地址');
      if (!mounted) return;
      setState(() {
        _curIndex = index;
        _curPath = widget.siblings[index].path;
        _curTitle = widget.siblings[index].obj.name;
        _curUrl = url;
        _curHeaders = detail.parsedHeaders();
        _curThumb = detail.obj.thumb.isNotEmpty
            ? detail.obj.thumb
            : widget.siblings[index].obj.thumb;
        _showPlaylist = false;
      });
      await _loadCurrent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法切换到该视频：$e');
    }
  }

  void _onControllerUpdate() {
    final v = _controller?.value;
    if (v == null || !mounted) return;
    // 播放结束后再落一次盘，让记录显示为「已看完」
    if (v.isInitialized && v.position >= v.duration && _ticker != null) {
      unawaited(_persist());
    }
    setState(() {});
  }

  /// 把当前位置与本次新增观看时长写入历史。
  Future<void> _persist() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final position = controller.value.position.inMilliseconds;
    final duration = controller.value.duration.inMilliseconds;

    // 只有正常前进才算「看过」：忽略 seek 造成的跳跃
    final delta = position - _lastSavedPositionMs;
    final watchedDelta = (delta > 0 && delta < 30000) ? delta : 0;
    _lastSavedPositionMs = position;

    await AppStore.instance.upsertRecord(
      path: _curPath,
      name: _curTitle,
      kind: MediaKind.video,
      positionMs: position,
      durationMs: duration,
      watchedDeltaMs: watchedDelta,
      thumb: _curThumb,
    );
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    setState(() {});
  }

  Future<void> _seekRelative(int seconds) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    await c.seekTo(clamped);
    setState(() {});
  }

  Future<void> _setSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
    if (mounted) setState(() => _speed = speed);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    final marks = store.marksOf(_curPath);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '退出播放',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_curTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _isLandscape ? '切换为竖屏' : '切换为横屏',
            icon: Icon(
              _isLandscape
                  ? Icons.stay_current_landscape
                  : Icons.stay_current_portrait,
            ),
            onPressed: _toggleOrientation,
          ),
          IconButton(
            tooltip: marks.favorite ? '取消收藏' : '收藏',
            icon: Icon(marks.favorite ? Icons.favorite : Icons.favorite_border),
            onPressed: () async {
              await store.toggle(
                SavedGroup.favorite,
                SavedItem(
                  path: _curPath,
                  name: _curTitle,
                  kind: MediaKind.video,
                  thumb: _curThumb,
                ),
              );
            },
          ),
          IconButton(
            tooltip: marks.later ? '移出稍后再看' : '稍后再看',
            icon: Icon(
              marks.later ? Icons.watch_later : Icons.watch_later_outlined,
            ),
            onPressed: () async {
              await store.toggle(
                SavedGroup.watchLater,
                SavedItem(
                  path: _curPath,
                  name: _curTitle,
                  kind: MediaKind.video,
                  thumb: _curThumb,
                ),
              );
            },
          ),
          PopupMenuButton<double>(
            tooltip: '播放速度',
            initialValue: _speed,
            onSelected: _setSpeed,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0.5, child: Text('0.5×')),
              PopupMenuItem(value: 0.75, child: Text('0.75×')),
              PopupMenuItem(value: 1.0, child: Text('正常')),
              PopupMenuItem(value: 1.25, child: Text('1.25×')),
              PopupMenuItem(value: 1.5, child: Text('1.5×')),
              PopupMenuItem(value: 2.0, child: Text('2×')),
            ],
            icon: Text(
              '$_speed×',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _error != null
          ? _ErrorView(message: _error!)
          : !_ready
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                  if (_controlsVisible) _buildControls(context),
                  // 选集必须排在控件层**之后**：Stack 里后加的在上层，
                  // 之前它排在前面，于是面板被下方的进度条与渐变盖住了。
                  if (_showPlaylist && widget.siblings.length > 1)
                    _buildPlaylist(context),
                ],
              ),
            ),
    );
  }

  /// 点击画面：选集开着就先收起选集，否则才切控件的显示。
  ///
  /// 早期版本这里只切控件，于是「想关选集却点偏了一点」会变成把控件藏起来 ——
  /// 选集面板留在屏幕上，而关它的按钮跟着控件一起消失了，看起来就是「关不掉」。
  void _toggleControls() {
    setState(() {
      if (_showPlaylist) {
        _showPlaylist = false;
        return;
      }
      _controlsVisible = !_controlsVisible;
      // 控件收起时选集一并收起，不留「面板在、按钮没了」的死角
      if (!_controlsVisible) _showPlaylist = false;
    });
  }

  Widget _buildControls(BuildContext context) {
    final c = _controller!;
    final v = c.value;
    final duration = v.duration;
    final position = v.position;

    return Container(
      // key 是必要的：Stack 的子节点按位置复用 element，
      // 选集面板出现/消失会让这层的位置发生挪动，没有 key 就可能错配状态。
      key: const ValueKey('controls'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.75),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // 中央播放 / 暂停与快退快进
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  color: Colors.white,
                  tooltip: '后退 10 秒',
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seekRelative(-10),
                ),
                const SizedBox(width: 16),
                IconButton.filled(
                  iconSize: 44,
                  tooltip: v.isPlaying ? '暂停' : '播放',
                  icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlay,
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  color: Colors.white,
                  tooltip: '前进 10 秒',
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seekRelative(10),
                ),
              ],
            ),
            const Spacer(),
            // 进度与信息
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                    ),
                    child: Slider(
                      value: duration.inMilliseconds == 0
                          ? 0
                          : position.inMilliseconds
                                .clamp(0, duration.inMilliseconds)
                                .toDouble(),
                      max: duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: (value) async {
                        await c.seekTo(Duration(milliseconds: value.round()));
                      },
                      onChangeEnd: (_) => unawaited(_persist()),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        formatDuration(position.inMilliseconds),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const Text(
                        ' / ',
                        style: TextStyle(color: Colors.white38),
                      ),
                      Text(
                        formatDuration(duration.inMilliseconds),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const Spacer(),
                      if (_speed != 1.0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '$_speed×',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      // 选集：同目录其他视频，点击右侧展开列表（仅在有多项时显示）
                      if (widget.siblings.length > 1)
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showPlaylist = !_showPlaylist),
                          icon: const Icon(
                            Icons.playlist_play,
                            size: 18,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            '选集',
                            style: TextStyle(color: Colors.white70),
                          ),
                          style: TextButton.styleFrom(
                            // 给足点击区域：早先 minimumSize: zero + shrinkWrap
                            // 让热区只剩文字那么大，点偏一点就落到外层
                            // GestureDetector 上（反而把控件一起收起来了）。
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(64, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右侧选集面板：列出同目录下的其他视频，点击切换。
  ///
  /// 两个不变量，改动时都要保住：
  ///   1. 它是 Stack 的**最后一个**子节点 —— Stack 里后加者在上层，排到控件层
  ///      前面就会连内容一起被渐变和进度条压住；
  ///   2. 它**不与底部控制栏重叠**（下面 `_bottomBarHeight` 的让位）——
  ///      否则面板会把进度条和右下角「选集」按钮一起盖住，
  ///      结果就是「再点选集关不掉」（按钮根本点不到）。
  Widget _buildPlaylist(BuildContext context) {
    final siblings = widget.siblings;
    return Align(
      // 与控件层同理：进出 Stack 时靠 key 保证 element 不错配
      key: const ValueKey('playlist'),
      alignment: Alignment.centerRight,
      child: Padding(
        // 底部再让开安全区：控制栏自身也在 SafeArea 里，不跟着让的话
        // 有底部横条/刘海的机型上仍会压住进度条
        padding: EdgeInsets.only(
          bottom: _bottomBarHeight + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Material(
          key: const ValueKey('playlist-panel'),
          color: Colors.black.withValues(alpha: 0.92),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.62,
            constraints: const BoxConstraints(maxWidth: 320),
            // 横屏时刘海在侧边：内容避开安全区；底部已由外层 Padding 让开
            child: SafeArea(
              left: false,
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '选集',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // 显式关闭入口：原先只能靠再点一次「选集」，点偏一点就关不掉
                        IconButton(
                          tooltip: '收起选集',
                          iconSize: 20,
                          color: Colors.white70,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 42,
                            minHeight: 42,
                          ),
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _showPlaylist = false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: siblings.length,
                      itemBuilder: (_, i) {
                        final s = siblings[i];
                        final active = i == _curIndex;
                        return ListTile(
                          selected: active,
                          selectedTileColor: Colors.white.withValues(
                            alpha: 0.12,
                          ),
                          dense: true,
                          title: Text(
                            s.obj.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active ? Colors.white : Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          trailing: active
                              ? const Icon(
                                  Icons.play_arrow,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                          onTap: () => unawaited(_switchTo(i)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('返回'),
          ),
        ],
      ),
    ),
  );
}

/// 控件层底部（进度条 + 时间行）占的高度（实测：进度条顶到屏幕底 80px，
/// 这里留 8px 余量）。选集面板按它让开底部 —— 面板若盖住控制栏，
/// 进度条和右下角的「选集」按钮都会点不到，用户就没法再点一次收起了。
///
/// 改动控件层底部排版（行数/字号/间距）时记得同步这个值：
/// `test/video_playlist_test.dart` 有一条断言盯着「面板与控制栏不得重叠」。
const double _bottomBarHeight = 88;

/// 退出播放时恢复竖屏（供外部与 [VideoPage.dispose] 调用）。
///
/// 全应用以竖屏为基准，只有横向视频播放期间才临时切到横屏。
Future<void> restorePortrait() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}
