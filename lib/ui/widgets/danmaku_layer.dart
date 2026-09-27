import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/social.dart';

/// 一条弹幕从右侧入场到左侧完全离场的时间（毫秒）。
const int defaultDanmakuFlightMs = 8000;

/// 弹幕轨道的行高（像素）。轨道数由可用高度除以它得出。
const double defaultDanmakuLaneHeight = 30;

/// 播放区域上方的弹幕图层：按播放位置把弹幕投到若干条横向轨道上滚动。
///
/// 时间轴调度是这样对上号的：
/// - 播放位置前进时，把 `offset ∈ [上次位置, 当前位置]` 的弹幕投出去；
/// - 拖动进度条（位置跳变超过 [_seekThresholdMs]）时，清空重算——只把「此刻
///   本该还在飞」的那些按进度放到半路上，避免快进后一次性涌出上百条；
/// - 暂停时冻结：不推进飞行时长，弹幕停在原地。
///
/// 绘制走 [CustomPaint] 而不是给每条弹幕建一个 Widget：弹幕可能同时在屏几十
/// 条，每帧重建组件树的代价远高于在同一块画布上画几十行文字。
class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({
    super.key,
    required this.entries,
    required this.position,
    required this.playing,
    this.visible = true,
    this.flightMs = defaultDanmakuFlightMs,
    this.laneHeight = defaultDanmakuLaneHeight,
  });

  /// 按出现时刻升序的弹幕列表。
  final List<SocialEntry> entries;

  /// 当前播放位置（毫秒）。用 [ValueListenable] 传入，是为了让图层内部直接监听，
  /// 不必每帧带着整棵播放页重建。
  final ValueListenable<int> position;

  /// 是否正在播放。暂停时弹幕冻结。
  final ValueListenable<bool> playing;

  /// 是否显示弹幕。
  final bool visible;

  final int flightMs;
  final double laneHeight;

  /// 位置跳变超过这个阈值就认为是拖动进度条。
  static const int seekThresholdMs = 2000;

  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  final List<_Flight> _flights = <_Flight>[];
  final Set<String> _launched = <String>{};
  final Map<String, TextPainter> _painters = <String, TextPainter>{};
  final ValueNotifier<int> _repaint = ValueNotifier(0);

  Ticker? _ticker;
  Duration _prevElapsed = Duration.zero;
  int _lastPositionMs = 0;
  int _laneCursor = 0;
  int _laneCount = 4;

  TextStyle get _textStyle => const TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    shadows: [
      // 描边效果：画面本身明暗不定，加一圈阴影才能保证任何底色上都读得清
      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black87),
      Shadow(offset: Offset(-1, -1), blurRadius: 3, color: Colors.black87),
    ],
  );

  @override
  void initState() {
    super.initState();
    _lastPositionMs = widget.position.value;
    widget.position.addListener(_onPositionChanged);
    widget.playing.addListener(_onPlayingChanged);
    _ticker = createTicker(_onTick)..start();
    // 从半路开始播（续播）时，把本该在飞的那些先摆好
    _syncTo(_lastPositionMs, seeked: true);
  }

  @override
  void didUpdateWidget(DanmakuLayer old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
    }
    if (old.playing != widget.playing) {
      old.playing.removeListener(_onPlayingChanged);
      widget.playing.addListener(_onPlayingChanged);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPositionChanged);
    widget.playing.removeListener(_onPlayingChanged);
    _ticker?.dispose();
    _repaint.dispose();
    for (final p in _painters.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _onPositionChanged() => _syncTo(widget.position.value, seeked: false);

  void _onPlayingChanged() {
    // 恢复播放时把 elapsed 基准拨到当前，否则暂停期间的空档会被算成飞行时间
    if (widget.playing.value) _repaint.value++;
  }

  void _onTick(Duration elapsed) {
    if (!widget.playing.value) {
      _prevElapsed = elapsed;
      return;
    }
    final deltaMs = (elapsed - _prevElapsed).inMicroseconds / 1000.0;
    _prevElapsed = elapsed;
    if (_flights.isEmpty) return;

    for (final f in _flights) {
      f.elapsedMs += deltaMs;
    }
    _flights.removeWhere((f) {
      if (f.elapsedMs < widget.flightMs) return false;
      _painters.remove(f.entry.id)?.dispose();
      return true;
    });
    _repaint.value++;
  }

  /// 把时间轴推进到 [positionMs]。
  void _syncTo(int positionMs, {required bool seeked}) {
    final prev = _lastPositionMs;
    _lastPositionMs = positionMs;

    // 拖动进度条（含后退）：清空重算。若不清，后退后 [launched] 里的 id 会让
    // 弹幕永远补不回来，前进而已超出飞行时长的那些则会一次性涌出。
    if (seeked || (positionMs - prev).abs() > DanmakuLayer.seekThresholdMs) {
      _resetFlights();
      for (final e in widget.entries) {
        if (e.offsetMs <= positionMs &&
            positionMs - e.offsetMs < widget.flightMs) {
          _launch(e, elapsedMs: (positionMs - e.offsetMs).toDouble());
        }
      }
      _repaint.value++;
      return;
    }

    var added = false;
    for (final e in widget.entries) {
      // 下界取闭区间：自己刚发出的弹幕 offset 就等于当前位置
      if (e.offsetMs >= prev && e.offsetMs <= positionMs) {
        added = _launch(e, elapsedMs: 0) || added;
      }
    }
    if (added) _repaint.value++;
  }

  void _resetFlights() {
    _flights.clear();
    _launched.clear();
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }

  /// 投放一条弹幕；已投过（按 id 去重）则跳过。返回是否真的投放了。
  bool _launch(SocialEntry e, {required double elapsedMs}) {
    if (_launched.contains(e.id)) return false;
    _launched.add(e.id);
    _painters[e.id] = TextPainter(
      text: TextSpan(text: e.content, style: _textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _flights.add(_Flight(e, _laneCursor++, elapsedMs));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.expand();
    // 弹幕只是画面上的一层字，不能吃掉点击——否则「点画面切控件」会失灵。
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final raw = (constraints.maxHeight * 0.62 / widget.laneHeight)
              .floor();
          _laneCount = raw < 1 ? 1 : (raw > 8 ? 8 : raw);
          return CustomPaint(
            painter: _DanmakuPainter(
              flights: _flights,
              painters: _painters,
              flightMs: widget.flightMs,
              laneHeight: widget.laneHeight,
              laneCount: _laneCount,
              repaint: _repaint,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

/// 在飞的弹幕：记住它属于哪条轨道、已经飞了多久。
class _Flight {
  _Flight(this.entry, this.lane, this.elapsedMs);

  final SocialEntry entry;
  final int lane;

  /// 已飞行时长（毫秒）。
  double elapsedMs;
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.flights,
    required this.painters,
    required this.flightMs,
    required this.laneHeight,
    required this.laneCount,
    super.repaint,
  });

  final List<_Flight> flights;
  final Map<String, TextPainter> painters;
  final int flightMs;
  final double laneHeight;
  final int laneCount;

  @override
  void paint(Canvas canvas, Size size) {
    // 顶部留出安全边距，别糊在状态栏/标题上
    const topPad = 10.0;
    for (final f in flights) {
      final p = painters[f.entry.id];
      if (p == null) continue;
      final progress = (f.elapsedMs / flightMs).clamp(0.0, 1.0);
      // 从屏幕右缘外进场，走到完全离开左缘
      final x = size.width - progress * (size.width + p.width);
      // 轨道数可能因为转屏变过，这里取模保证不越界
      final y = topPad + (f.lane % laneCount) * laneHeight;
      p.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter old) =>
      old.flights != flights ||
      old.laneCount != laneCount ||
      old.painters != painters;
}
