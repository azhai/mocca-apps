import 'package:flutter/material.dart';

/// Mocca 的暗色主题：抹茶绿为骨、莫奈色为韵。
///
/// 设计取向说明（避免后续改动时偏航）：
/// - **暗色唯一**：应用只提供暗色主题（[MoccaTheme.dark]），不做亮色分支。
/// - **低饱和**：莫奈的印象派用色是「灰调里的彩色」，所以主色不用高饱和绿，
///   而是往灰里走（如 `#9CC79C` 而非 `#4CAF50`），长时间观看不刺眼。
/// - **分层靠明度而非阴影**：暗色下阴影几乎不可见，层次由 surface 的
///   三级明度差（surface / surfaceContainer / surfaceContainerHigh）拉开。
/// - 通过 [ColorScheme.fromSeed] 生成完整合法的 M3 色板（保证对比度与
///   「前景/容器」配对不出错），再用 [ColorScheme.copyWith] 覆盖关键角色为
///   莫奈色，兼顾正确性与调色自由度。
abstract final class MoccaTheme {
  /// 种子色（抹茶绿）。仅用于让 fromSeed 推导出合法的默认配对。
  static const seed = Color(0xFF6B8E4E);

  // ---------------------------------------------------------------- 莫奈色板
  //
  // 取自莫奈《睡莲》与《日本桥》的常用色：雾绿、灰蓝、藕紫、暖砂。

  /// 抹茶绿（主色）：带灰的茶绿。
  static const _mocca = Color(0xFF9CC79C);
  static const _moccaDeep = Color(0xFF2A3D31);
  static const _moccaOn = Color(0xFF12200F);

  /// 莫奈灰蓝（次色）：睡莲池水与晨雾。
  static const _monetBlue = Color(0xFF92B4BE);
  static const _monetBlueDeep = Color(0xFF22363C);
  static const _monetBlueOn = Color(0xFF0C1E23);

  /// 藕紫（第三色）：黄昏水面与鸢尾。
  static const _irisPurple = Color(0xFFC3B4D8);
  static const _irisPurpleDeep = Color(0xFF332C40);
  static const _irisPurpleOn = Color(0xFF1E1828);

  /// 暖砂（强调）：草垛与石径。
  static const _sandAccent = Color(0xFFD8C4A0);

  /// 底色：极暗的墨绿黑，比纯黑柔和，能压住长时间的对比疲劳。
  static const _ink = Color(0xFF0E1614);
  static const _inkRaised = Color(0xFF16211E);
  static const _inkHigh = Color(0xFF1D2B27);
  static const _inkHighest = Color(0xFF25352F);
  static const _onInk = Color(0xFFE2EAE3);
  static const _onInkMuted = Color(0xFFAEBAB2);

  /// 柔和的胭脂红，用于错误态（不用刺眼的纯红）。
  static const _rouge = Color(0xFFE4A3A0);
  static const _rougeDeep = Color(0xFF4A2726);
  static const _rougeOn = Color(0xFF2A1110);

  /// 唯一的主题入口。
  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    final scheme = base.copyWith(
      primary: _mocca,
      onPrimary: _moccaOn,
      primaryContainer: _moccaDeep,
      onPrimaryContainer: const Color(0xFFC6E4C3),

      secondary: _monetBlue,
      onSecondary: _monetBlueOn,
      secondaryContainer: _monetBlueDeep,
      onSecondaryContainer: const Color(0xFFC6E2E9),

      tertiary: _irisPurple,
      onTertiary: _irisPurpleOn,
      tertiaryContainer: _irisPurpleDeep,
      onTertiaryContainer: const Color(0xFFE4DAF4),

      error: _rouge,
      onError: _rougeOn,
      errorContainer: _rougeDeep,
      onErrorContainer: const Color(0xFFF7D5D3),

      surface: _ink,
      onSurface: _onInk,
      onSurfaceVariant: _onInkMuted,
      surfaceContainerLowest: const Color(0xFF0A100F),
      surfaceContainerLow: _inkRaised,
      surfaceContainer: _inkRaised,
      surfaceContainerHigh: _inkHigh,
      surfaceContainerHighest: _inkHighest,

      // 描边压得很淡：暗色界面里高对比描边会显得「脏」
      outline: const Color(0xFF4A5A52),
      outlineVariant: const Color(0xFF2C3A35),
      scrim: const Color(0xFF000000),
      inverseSurface: _onInk,
      onInverseSurface: _ink,
      inversePrimary: const Color(0xFF416B45),
    );

    final radius = BorderRadius.circular(18);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      // 暗色下不做 elevation 染色，避免表面泛白
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
        ),
        labelType: NavigationRailLabelType.all,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: scheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 12.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.16),
        trackHeight: 3,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant,
        circularTrackColor: Colors.transparent,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),

      // 统一过渡：淡入 + 轻微上移，比默认的「从右滑入」更贴合静谧的调性
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 点缀色，供渐变、封面占位等场景使用（不参与 M3 角色映射）。
  static const sand = _sandAccent;
  static const mocca = _mocca;
  static const monetBlue = _monetBlue;
  static const iris = _irisPurple;
}

/// 响应式断点：手机 / 平板 / 大屏。
///
/// 依据 Material 3 的建议，`600dp` 与 `840dp` 是常用的划分点；
/// 应用用它在「底部导航」与「侧边导航」之间切换，并调整内容栅格列数。
abstract final class Breakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  static bool isCompact(double width) => width < compact;
  static bool isMedium(double width) => width >= compact && width < expanded;
  static bool isExpanded(double width) => width >= expanded;

  /// 依据可用宽度推荐列表栅格列数（图片墙、卡片列表用）。
  static int gridColumns(double width) {
    if (width < 400) return 2;
    if (width < compact) return 3;
    if (width < 900) return 4;
    if (width < 1280) return 6;
    return 8;
  }

  /// 手机用底部导航栏，平板 / 大屏用侧边导航轨道。
  static bool useNavigationRail(double width) => width >= compact;
}

/// 在任意位置取到当前宽度对应的断点判断。
extension BreakpointContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => Breakpoints.isCompact(screenWidth);
  bool get isTablet => !isCompact;
}
