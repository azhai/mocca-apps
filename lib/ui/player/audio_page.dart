import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../data/store.dart';

/// MP3 等音频播放页。
///
/// 支持同目录内的上一首 / 下一首：传入的 [siblings] 是目录中的音频列表，
/// 切换到其它曲目时才去 `/api/fs/get` 拉取它的播放地址（懒加载）。
class AudioPage extends StatefulWidget {
  const AudioPage({
    super.key,
    required this.siblings,
    required this.index,
    required this.initialUrl,
    this.initialHeaders = const {},
    this.password,
  });

  final List<({MediaObj obj, String path})> siblings;
  final int index;

  /// 进入时已解析好的地址，避免重复请求第一首。
  final String initialUrl;
  final Map<String, String> initialHeaders;
  final String? password;

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> with WidgetsBindingObserver {
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  Timer? _ticker;

  late int _index = widget.index;
  String? _error;
  bool _busy = true;
  bool _shuffle = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  int _lastSavedPositionMs = 0;
  int _watchedMs = 0;

  ({MediaObj obj, String path}) get _current => widget.siblings[_index];
  int get _count => widget.siblings.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
      if (s.processingState == ProcessingState.completed) {
        unawaited(_persist());
        _next(auto: true);
      }
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    unawaited(_load(_index, url: widget.initialUrl, headers: widget.initialHeaders));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _stateSub?.cancel();
    unawaited(_persist());
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persist());
    }
  }

  /// 载入指定曲目；[url] 为空时按需向后端请求。
  Future<void> _load(
    int index, {
    String? url,
    Map<String, String> headers = const {},
  }) async {
    final target = widget.siblings[index];
    setState(() {
      _index = index;
      _busy = true;
      _error = null;
    });

    try {
      var playUrl = url ?? '';
      var httpHeaders = headers;
      if (playUrl.isEmpty) {
        final detail = await AppStore.instance.api.get(
          target.path,
          password: widget.password,
        );
        playUrl = AppStore.instance.api.resolveUrl(detail.rawUrl);
        httpHeaders = detail.parsedHeaders();
      }
      if (playUrl.isEmpty) throw ApiException(500, '服务器未返回可播放地址');

      // 取该曲目已保存的进度，实现续播
      final record = AppStore.instance.recordFor(target.path);
      _lastSavedPositionMs = record?.positionMs ?? 0;
      _watchedMs = record?.watchedMs ?? 0;
      final resume = record?.resumeMs ?? 0;

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(playUrl),
          headers: httpHeaders.isEmpty ? null : httpHeaders,
        ),
        initialPosition: Duration(milliseconds: resume),
      );
      await _player.play();

      _ticker?.cancel();
      _ticker = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_persist()),
      );

      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? e.message : '无法播放该音频：$e';
        });
      }
    }
  }

  /// 落盘当前位置与本次新增的观看时长。
  Future<void> _persist() async {
    final position = _player.position.inMilliseconds;
    final duration = _player.duration?.inMilliseconds ?? 0;
    if (position <= 0 && duration <= 0) return;

    final delta = position - _lastSavedPositionMs;
    final watchedDelta = (delta > 0 && delta < 30000) ? delta : 0;
    _lastSavedPositionMs = position;
    _watchedMs += watchedDelta;

    final cur = _current;
    await AppStore.instance.upsertRecord(
      path: cur.path,
      name: cur.obj.name,
      kind: MediaKind.audio,
      positionMs: position,
      durationMs: duration,
      watchedDeltaMs: watchedDelta,
      thumb: cur.obj.thumb,
    );
  }

  Future<void> _next({bool auto = false}) async {
    await _persist();
    if (_count <= 1) return;
    final next = _shuffle
        ? (DateTime.now().microsecondsSinceEpoch % _count)
        : (_index + 1) % _count;
    if (next == _index && auto) return;
    await _load(next);
  }

  Future<void> _prev() async {
    await _persist();
    if (_count <= 1) return;
    await _load((_index - 1 + _count) % _count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = AppStore.instance;
    final cur = _current;
    final marks = store.marksOf(cur.path);
    final maxMs = _duration.inMilliseconds.clamp(1, 1 << 62);

    return Scaffold(
      appBar: AppBar(
        title: Text(cur.obj.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: marks.favorite ? '取消收藏' : '收藏',
            icon: Icon(marks.favorite ? Icons.favorite : Icons.favorite_border),
            onPressed: () => store.toggle(
              SavedGroup.favorite,
              SavedItem(
                path: cur.path,
                name: cur.obj.name,
                kind: MediaKind.audio,
                thumb: cur.obj.thumb,
              ),
            ),
          ),
          IconButton(
            tooltip: marks.later ? '移出稍后再看' : '稍后再看',
            icon: Icon(
              marks.later ? Icons.watch_later : Icons.watch_later_outlined,
            ),
            onPressed: () => store.toggle(
              SavedGroup.watchLater,
              SavedItem(
                path: cur.path,
                name: cur.obj.name,
                kind: MediaKind.audio,
                thumb: cur.obj.thumb,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildArtwork(theme, cur.obj.thumb),
                  const SizedBox(height: 28),
                  Text(
                    cur.obj.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (_count > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_index + 1} / $_count',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Slider(
                    value: _position.inMilliseconds.clamp(0, maxMs).toDouble(),
                    max: maxMs.toDouble(),
                    onChanged: _busy
                        ? null
                        : (v) => _player.seek(Duration(milliseconds: v.round())),
                    onChangeEnd: (_) => unawaited(_persist()),
                  ),
                  Row(
                    children: [
                      Text(
                        formatDuration(_position.inMilliseconds),
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        formatDuration(_duration.inMilliseconds),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '随机',
                        isSelected: _shuffle,
                        icon: const Icon(Icons.shuffle),
                        selectedIcon: Icon(
                          Icons.shuffle,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: () => setState(() => _shuffle = !_shuffle),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 40,
                        tooltip: '上一首',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _count > 1 ? _prev : null,
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        iconSize: 44,
                        tooltip: _playing ? '暂停' : '播放',
                        icon: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(_playing ? Icons.pause : Icons.play_arrow),
                        onPressed: _busy
                            ? null
                            : () => _playing ? _player.pause() : _player.play(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 40,
                        tooltip: '下一首',
                        icon: const Icon(Icons.skip_next),
                        onPressed: _count > 1 ? () => _next() : null,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '循环模式',
                        icon: Icon(
                          switch (_player.loopMode) {
                            LoopMode.off => Icons.repeat,
                            LoopMode.all => Icons.repeat_on,
                            LoopMode.one => Icons.repeat_one,
                          },
                        ),
                        onPressed: () async {
                          final next = switch (_player.loopMode) {
                            LoopMode.off => LoopMode.all,
                            LoopMode.all => LoopMode.one,
                            LoopMode.one => LoopMode.off,
                          };
                          await _player.setLoopMode(next);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility_outlined, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '累计观看 ${formatDuration(_watchedMs)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_duration.inMilliseconds > 0) ...[
                        const SizedBox(width: 16),
                        Text(
                          '本次进度 ${(_position.inMilliseconds / maxMs * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(ThemeData theme, String thumb) {
    final size = MediaQuery.sizeOf(context).shortestSide.clamp(160.0, 300.0);
    final url = thumb.isEmpty ? null : AppStore.instance.api.resolveUrl(thumb);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Icon(
              Icons.music_note,
              size: size * 0.4,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (_, _, _) => Icon(
                Icons.music_note,
                size: size * 0.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}
