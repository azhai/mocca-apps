import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/store.dart';
import 'ui/browse_page.dart';
import 'ui/library_page.dart';
import 'ui/login_page.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 应用以竖屏为基准；播放横向视频时由 VideoPage 临时转横屏，
  // 退出播放会调用 restorePortrait() 转回来。
  // 平板（最短边 >= 600dp）不锁定，否则会白白浪费横向空间。
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortestSide < 600) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 先载入本地配置，避免首帧闪烁
  await AppStore.instance.load();
  runApp(const MoccaApp());
}

class MoccaApp extends StatelessWidget {
  const MoccaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final palette = store.palette;
        return MaterialApp(
          title: 'Mocca',
          debugShowCheckedModeBanner: false,
          // 每套配色自带明暗：绿/蓝为暗，紫/杏为浅，切换配色即切换明暗。
          theme: MoccaTheme.themeOf(palette),
          darkTheme: MoccaTheme.themeOf(palette),
          themeMode: palette.brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // 浏览不需要登录：地址有默认值，启动即进主界面。
          // 登录 / 注册只在「设置」里按需触发（见 LoginPage）。
          home: store.serverUrl.isEmpty ? const LoginPage() : const AppShell(),
        );
      },
    );
  }
}

/// 响应式主导航。
///
/// - 手机（< 600dp）：底部 [NavigationBar]
/// - 平板 / 大屏：侧边 [NavigationRail]
///
/// 两个分支共用同一份页面列表，用 [IndexedStack] 保持各页状态
/// （例如浏览页的目录位置不会因切换标签而丢失）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations =
      <({IconData icon, IconData selected, String label})>[
        (icon: Icons.folder_outlined, selected: Icons.folder, label: '浏览'),
        (icon: Icons.person_outline, selected: Icons.person, label: '个人'),
        (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置'),
      ];

  @override
  Widget build(BuildContext context) {
    final pages = const [BrowsePage(), LibraryPage(), SettingsPage()];
    final useRail = Breakpoints.useNavigationRail(
      MediaQuery.sizeOf(context).width,
    );

    // 两种布局都让 IndexedStack 待在 Row 的同一个位置（最末一个子节点），
    // 侧栏只在前面增删。这样宽度越过断点时（例如播放视频转横屏再返回）
    // 各页的元素不会被重建，浏览页的目录、滚动位置与视图模式才能保住。
    return Scaffold(
      body: Row(
        children: [
          if (useRail) ...[
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: d.label,
                  ),
              ],
            ),
    );
  }
}
