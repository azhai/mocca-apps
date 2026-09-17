import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocca/core/models.dart';
import 'package:mocca/ui/player/video_page.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// 伪造 video_player 的平台实现：测试里没有真实解码器，这里只把
/// `VideoPlayerController.initialize()` 需要的事件补上，顺带记录 `seekTo`。
class _FakeVideoPlatform extends VideoPlayerPlatform {
  final seeks = <Duration>[];
  final _events = <int, StreamController<VideoEvent>>{};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++_nextId;
    // 必须是「单订阅」流：initialize() 是先 create 再 listen，
    // 用 broadcast 的话事件会在有人订阅前就被丢掉，initialize 永远不返回。
    final ctrl = StreamController<VideoEvent>();
    _events[id] = ctrl;
    ctrl.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 2),
        size: const Size(1920, 1080),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      seeks.add(position);

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  late _FakeVideoPlatform fake;

  setUp(() {
    fake = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  // 兄弟项：同一目录下的其他视频
  List<({MediaObj obj, String path})> siblings(int n) => List.generate(
    n,
    (i) => (
      obj: MediaObj(
        name: '第 ${i + 1} 集.mp4',
        size: 1024,
        isDir: false,
        type: MediaKind.video,
      ),
      path: '/media/第 ${i + 1} 集.mp4',
    ),
  );

  Future<void> mount(WidgetTester tester, int count) async {
    // VideoPage 在 initialize() 之后会设置屏幕方向 / 系统 UI（SystemChrome），
    // 那是平台通道：widget 测试里没有引擎来应答，await 会一直挂着，
    // 页面就永远停在加载态（连「选集」按钮都看不到）。这里给通道装个空实现。
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final all = siblings(count);
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPage(
          path: all.first.path,
          title: all.first.obj.name,
          url: 'http://example.com/a.mp4',
          siblings: all,
          index: 0,
        ),
      ),
    );
    // 让 initialize() 的异步链（create → 事件 → play）跑完
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  // 面板本体（Material）带独立 key：外层 Align 会撑满全屏，量它得出的
  // 是整屏矩形，几何断言会失真。
  Finder panel() => find.byKey(const ValueKey('playlist-panel'));

  Finder group() => find.byKey(const ValueKey('playlist'));

  final toggle = find.widgetWithText(TextButton, '选集');

  testWidgets('选集要盖在控件层之上，且不压住底部控制栏', (tester) async {
    await mount(tester, 8);

    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(panel(), findsOneWidget, reason: '点「选集」应展开面板');

    // ① 结构断言：Stack 里后加的在上层，选集必须排在控件层之后。
    //    排到前面就会被控件层的黑色渐变压暗（用户看到的「没出现在最上面」）。
    final stackFinder = find.ancestor(
      of: group(),
      matching: find.byType(Stack),
    );
    final stack = tester.widget<Stack>(stackFinder.first);
    final keys = stack.children.map((w) => w.key).toList();
    expect(
      keys.indexOf(const ValueKey('playlist')),
      greaterThan(keys.indexOf(const ValueKey('controls'))),
      reason: '选集排在控件层之前 —— Stack 后加者在上层，这样会被渐变/进度条盖住',
    );

    // ② 面板不得与底部控制栏重叠。重叠的话进度条会被压住，
    //    右下角「选集」按钮也会点不到（关不掉）。
    final panelRect = tester.getRect(panel());
    final sliderRect = tester.getRect(find.byType(Slider));
    expect(
      panelRect.overlaps(sliderRect),
      isFalse,
      reason: '面板压住了进度条：panel=$panelRect slider=$sliderRect',
    );

    // ③ 面板打开时「选集」按钮仍要能点中 —— 否则没法再点一次收起
    expect(toggle.hitTestable(), findsOneWidget, reason: '面板盖住了「选集」按钮，点不到就关不掉');
    expect(fake.seeks, isEmpty);
  });

  testWidgets('再点一次「选集」要完全收起', (tester) async {
    await mount(tester, 8);

    await tester.tap(toggle);
    await tester.pump();
    expect(panel(), findsOneWidget);

    // 第二次点击必须真的落在按钮上（warnIfMissed 会把它变成失败）
    await tester.tap(toggle);
    await tester.pump();
    expect(panel(), findsNothing, reason: '收起后不应残留面板');

    // 面板头部的 ✕ 同样能收起
    await tester.tap(toggle);
    await tester.pump();
    expect(panel(), findsOneWidget);
    await tester.tap(find.byTooltip('收起选集'));
    await tester.pump();
    expect(panel(), findsNothing, reason: '✕ 应能完全收起');
  });

  testWidgets('只有一项可播放时不显示选集入口', (tester) async {
    await mount(tester, 1);
    expect(toggle, findsNothing);
  });
}
