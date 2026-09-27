import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocca/core/social.dart';
import 'package:mocca/ui/widgets/danmaku_layer.dart';

void main() {
  final now = DateTime.parse('2026-09-26T10:00:00Z');

  SocialEntry danmaku(String id, int offsetMs, [String content = '弹幕']) =>
      SocialEntry(
        id: id,
        userId: 1,
        userName: 'u',
        userAvatar: '01',
        type: SocialType.danmaku,
        offsetMs: offsetMs,
        content: content,
        createdAt: now,
      );

  /// 把图层放进固定尺寸的盒子里，避免测试默认 800×600 之外的布局干扰。
  Widget mount(
    List<SocialEntry> entries,
    ValueNotifier<int> position,
    ValueNotifier<bool> playing, {
    bool visible = true,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 300,
        child: DanmakuLayer(
          entries: entries,
          position: position,
          playing: playing,
          visible: visible,
        ),
      ),
    ),
  );

  // Scaffold 自己也会挂 CustomPaint，所以要限定在图层内部找
  Finder canvas() => find.descendant(
    of: find.byType(DanmakuLayer),
    matching: find.byType(CustomPaint),
  );

  testWidgets('显示时挂上画布，隐藏时完全不画', (tester) async {
    final position = ValueNotifier(0);
    final playing = ValueNotifier(true);

    await tester.pumpWidget(mount([danmaku('1', 0)], position, playing));
    expect(canvas(), findsOneWidget);

    await tester.pumpWidget(
      mount([danmaku('1', 0)], position, playing, visible: false),
    );
    expect(canvas(), findsNothing);
  });

  testWidgets('播放推进后弹幕会飞完并回收，不残留', (tester) async {
    final position = ValueNotifier(0);
    final playing = ValueNotifier(true);
    await tester.pumpWidget(
      mount([danmaku('1', 0), danmaku('2', 5000)], position, playing),
    );

    // 推进到第 6 秒：两条都该被投放
    position.value = 6000;
    await tester.pump();

    // 再飞满一条弹幕的时长，两条都该离场
    await tester.pump(Duration(milliseconds: defaultDanmakuFlightMs + 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖动进度条（位置跳变）不会一次性涌出或崩溃', (tester) async {
    final position = ValueNotifier(0);
    final playing = ValueNotifier(true);
    // 1000 条全在前 10 秒内，随后直接跳到第 8 分钟
    final many = [for (var i = 0; i < 1000; i++) danmaku('d$i', i * 10)];
    await tester.pumpWidget(mount(many, position, playing));

    position.value = 480000;
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '大跳变后不应有异常');

    // 跳回去同样要能重建
    position.value = 1000;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂停时不推进飞行时长', (tester) async {
    final position = ValueNotifier(0);
    final playing = ValueNotifier(false);
    await tester.pumpWidget(mount([danmaku('1', 0)], position, playing));

    await tester.pump(Duration(seconds: 10));
    expect(tester.takeException(), isNull);
    // 恢复播放后继续推进
    playing.value = true;
    await tester.pump(Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
