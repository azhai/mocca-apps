import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocca/core/api_client.dart';
import 'package:mocca/core/models.dart';
import 'package:mocca/data/store.dart';
import 'package:mocca/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 固定返回一批条目。默认只有子目录，避免列表里出现需要联网取封面的媒体项。
class _FakeApi extends ApiClient {
  _FakeApi({this.images = 0}) : super(baseUrl: 'http://test');

  /// 生成的图片条目数量。有图片时默认视图会判成网格。
  final int images;

  @override
  Future<List<MediaObj>> list(String path, {String? password}) async => [
    for (var i = 1; i <= 40 - images; i++)
      MediaObj(
        name: '目录 ${i.toString().padLeft(2, '0')}',
        size: 0,
        isDir: true,
        type: MediaKind.dir,
      ),
    for (var i = 1; i <= images; i++)
      MediaObj(
        name: '图片 ${i.toString().padLeft(2, '0')}',
        size: 1024,
        isDir: false,
        type: MediaKind.image,
      ),
  ];

  /// 一律不给封面地址：图片的默认封面是原图直链，测试里会去联网取图。
  @override
  String? coverUrl(int kind, String path) => null;
}

/// 视口里最靠上那一个网格条目的名字（含被上沿裁掉一半的）。
String _topGridName(WidgetTester tester) {
  var best = '';
  var bestDy = double.infinity;
  for (final element in find.byType(Text).evaluate()) {
    final text = (element.widget as Text).data;
    if (text == null || !text.startsWith('图片 ')) continue;
    final dy = tester.getTopLeft(find.byWidget(element.widget)).dy;
    if (dy < bestDy) {
      bestDy = dy;
      best = text;
    }
  }
  return best;
}

void main() {
  testWidgets('可用宽度变化后仍停在原目录、原视图模式与滚动位置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppStore.instance.load();
    AppStore.instance.api = _FakeApi();

    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoccaApp());
    await tester.pumpAndSettle();

    // 进入子目录，切到网格，并往下滚一段
    await tester.tap(find.text('目录 01'));
    await tester.pumpAndSettle();
    expect(find.text('/目录 01'), findsOneWidget, reason: '未进入子目录');

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.view_list), findsOneWidget, reason: '未切到网格');

    await tester.drag(find.byType(GridView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final grid = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    final offset = grid.position.pixels;
    expect(offset, greaterThan(0), reason: '未滚动起来，用例前提不成立');

    // 模拟播放页转横屏：宽度越过平板断点，外壳在「底栏 / 侧栏」之间切换
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    await tester.pumpAndSettle();

    expect(find.text('/目录 01'), findsOneWidget, reason: '返回后目录被重置了');
    expect(find.byIcon(Icons.view_list), findsOneWidget, reason: '返回后视图模式被重置了');
    final after = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(after.position.pixels, closeTo(offset, 1), reason: '返回后滚动位置被重置了');
  });

  testWidgets('宽窄变化引起列表 / 网格自动切换时，滚动位置也不应丢失', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppStore.instance.load();
    AppStore.instance.api = _FakeApi();

    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoccaApp());
    await tester.pumpAndSettle();

    // 目录里没有图片，竖屏默认列表；往下滚一段
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    final offset = list.position.pixels;
    expect(offset, greaterThan(0), reason: '未滚动起来，用例前提不成立');

    // 转横屏：宽度越过平板断点。默认视图在载入时已固定，不应再跟着换，
    // 否则列表 / 网格互换会把滚动组件重建，位置归零。
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget, reason: '横屏时视图模式被换掉了');

    // 转回竖屏
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    await tester.pumpAndSettle();

    final after = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(after.position.pixels, closeTo(offset, 1), reason: '模式自动切换后滚动位置被重置了');
  });

  testWidgets('网格排版变化后按条目锚点回到原来那一屏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppStore.instance.load();
    AppStore.instance.api = _FakeApi(images: 40);

    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoccaApp());
    await tester.pumpAndSettle();

    // 目录里有图片 → 默认视图是网格
    expect(find.byType(GridView), findsOneWidget, reason: '默认视图不是网格，用例前提不成立');

    ScrollableState gridState() => tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );

    await tester.drag(find.byType(GridView), const Offset(0, -2500));
    await tester.pumpAndSettle();
    final offset = gridState().position.pixels;
    final top = _topGridName(tester);
    expect(offset, greaterThan(0), reason: '未滚动起来，用例前提不成立');
    expect(top, isNotEmpty, reason: '没找到网格条目名，用例前提不成立');

    // 转横屏：列数变多、格子变大，内容整体变矮。此处的像素偏移会被裁到
    // 末尾，与原来那一屏差出好几行——这正是「锚点不准」的由来。
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    await tester.pumpAndSettle();
    expect(
      gridState().position.maxScrollExtent,
      lessThan(offset),
      reason: '横屏内容没有变矮，用例前提不成立',
    );

    // 转回竖屏：应回到原来读到的那一行，而不是被裁后的位置
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    await tester.pumpAndSettle();
    expect(gridState().position.pixels, closeTo(offset, 1), reason: '返回后没能回到原来的位置');
    expect(_topGridName(tester), top, reason: '返回后视口顶部的条目变了');
  });
}
