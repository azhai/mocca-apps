import 'package:flutter/material.dart';

/// 四套 Material 3 配色。
///
/// 每套配色自带明暗：绿 / 蓝为暗色系，紫 / 杏为浅色系。切换配色即切换整个应用
/// 的明暗与主色调（见设置页「外观」区块；无独立的「跟随系统」开关）。
enum MoccaPalette {
  green('抹绿', Brightness.dark, _Palettes.green),
  blue('湛蓝', Brightness.dark, _Palettes.blue),
  purple('藕紫', Brightness.light, _Palettes.purple),
  apricot('杏黄', Brightness.light, _Palettes.apricot);

  const MoccaPalette(this.label, this.brightness, this._tokens);

  /// 设置页展示用的名称。
  final String label;

  /// 该配色对应的明暗模式。
  final Brightness brightness;

  /// 覆盖后的 M3 关键角色色值。
  final _PaletteTokens _tokens;
}

/// 一套配色的 M3 完整角色色值。
///
/// 通过 [ColorScheme.fromSeed] 生成合法色板（保证对比度与「前景/容器」配对
/// 不出错），再用这些色值覆盖关键角色。低饱和、靠明度分层是 Mocca 的既定取向。
class _PaletteTokens {
  const _PaletteTokens({
    required this.seed,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
  });

  final Color seed;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outline;
  final Color outlineVariant;
  final Color scrim;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;
}

/// 四套配色的取值。独立成类是为了让 [MoccaPalette] 枚举保持简洁。
abstract final class _Palettes {
  // ----------------------------------------------------------- 暗色·抹绿
  static const green = _PaletteTokens(
    seed: Color(0xFF6B8E4E),
    primary: Color(0xFF9CC79C),
    onPrimary: Color(0xFF12200F),
    primaryContainer: Color(0xFF2A3D31),
    onPrimaryContainer: Color(0xFFC6E4C3),
    secondary: Color(0xFF92B4BE),
    onSecondary: Color(0xFF0C1E23),
    secondaryContainer: Color(0xFF22363C),
    onSecondaryContainer: Color(0xFFC6E2E9),
    tertiary: Color(0xFFC3B4D8),
    onTertiary: Color(0xFF1E1828),
    tertiaryContainer: Color(0xFF332C40),
    onTertiaryContainer: Color(0xFFE4DAF4),
    error: Color(0xFFE4A3A0),
    onError: Color(0xFF2A1110),
    errorContainer: Color(0xFF4A2726),
    onErrorContainer: Color(0xFFF7D5D3),
    surface: Color(0xFF0E1614),
    onSurface: Color(0xFFE2EAE3),
    onSurfaceVariant: Color(0xFFAEBAB2),
    surfaceContainerLowest: Color(0xFF0A100F),
    surfaceContainerLow: Color(0xFF16211E),
    surfaceContainer: Color(0xFF16211E),
    surfaceContainerHigh: Color(0xFF1D2B27),
    surfaceContainerHighest: Color(0xFF25352F),
    outline: Color(0xFF4A5A52),
    outlineVariant: Color(0xFF2C3A35),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE2EAE3),
    onInverseSurface: Color(0xFF0E1614),
    inversePrimary: Color(0xFF416B45),
  );

  // ----------------------------------------------------------- 暗色·湛蓝
  static const blue = _PaletteTokens(
    seed: Color(0xFF4E7B8E),
    primary: Color(0xFF93B6CB),
    onPrimary: Color(0xFF0B1A24),
    primaryContainer: Color(0xFF223A49),
    onPrimaryContainer: Color(0xFFCBE3F0),
    secondary: Color(0xFF94C7C7),
    onSecondary: Color(0xFF0C2121),
    secondaryContainer: Color(0xFF223A3A),
    onSecondaryContainer: Color(0xFFCAECEA),
    tertiary: Color(0xFFB9B0DD),
    onTertiary: Color(0xFF1E1828),
    tertiaryContainer: Color(0xFF342C45),
    onTertiaryContainer: Color(0xFFE4DEF6),
    error: Color(0xFFE4A3A0),
    onError: Color(0xFF2A1110),
    errorContainer: Color(0xFF4A2726),
    onErrorContainer: Color(0xFFF7D5D3),
    surface: Color(0xFF0E141C),
    onSurface: Color(0xFFE2E9EE),
    onSurfaceVariant: Color(0xFFAEB8C0),
    surfaceContainerLowest: Color(0xFF0A1016),
    surfaceContainerLow: Color(0xFF161E26),
    surfaceContainer: Color(0xFF161E26),
    surfaceContainerHigh: Color(0xFF1D2730),
    surfaceContainerHighest: Color(0xFF25303A),
    outline: Color(0xFF4A5A64),
    outlineVariant: Color(0xFF2C3A42),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE2E9EE),
    onInverseSurface: Color(0xFF0E141C),
    inversePrimary: Color(0xFF35607A),
  );

  // ----------------------------------------------------------- 浅色·藕紫
  static const purple = _PaletteTokens(
    seed: Color(0xFF7A5FA8),
    primary: Color(0xFF6A4D99),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE9DDFB),
    onPrimaryContainer: Color(0xFF241539),
    secondary: Color(0xFF6B6280),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEDE5FF),
    onSecondaryContainer: Color(0xFF251A37),
    tertiary: Color(0xFF82506E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8EC),
    onTertiaryContainer: Color(0xFF361522),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFCF7FF),
    onSurface: Color(0xFF1C1B21),
    onSurfaceVariant: Color(0xFF49464F),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F1FD),
    surfaceContainer: Color(0xFFF0EAFB),
    surfaceContainerHigh: Color(0xFFEAE5F5),
    surfaceContainerHighest: Color(0xFFE4DFEF),
    outline: Color(0xFF7A7480),
    outlineVariant: Color(0xFFCBC4D2),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF313036),
    onInverseSurface: Color(0xFFF4EFFB),
    inversePrimary: Color(0xFFD5BBFF),
  );

  // ----------------------------------------------------------- 浅色·杏黄
  static const apricot = _PaletteTokens(
    seed: Color(0xFFC98A3B),
    primary: Color(0xFF926400),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDDB3),
    onPrimaryContainer: Color(0xFF2E1B00),
    secondary: Color(0xFF6F6248),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF9E6C7),
    onSecondaryContainer: Color(0xFF261A08),
    tertiary: Color(0xFF82543A),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFDBC9),
    onTertiaryContainer: Color(0xFF321305),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFFF9F2),
    onSurface: Color(0xFF211B13),
    onSurfaceVariant: Color(0xFF4E463B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFCF4EB),
    surfaceContainer: Color(0xFFF7EEE2),
    surfaceContainerHigh: Color(0xFFF0E8DC),
    surfaceContainerHighest: Color(0xFFEBE2D6),
    outline: Color(0xFF80776A),
    outlineVariant: Color(0xFFD2C8BA),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF373028),
    onInverseSurface: Color(0xFFFBF7EE),
    inversePrimary: Color(0xFFFFB95A),
  );
}

/// Mocca 的 M3 主题工厂。
///
/// 分层靠明度差异由各套配色的 surface 系列色值撑起；组件级样式集中在
/// [_buildTheme]，一套逻辑同时适配明暗四套配色，避免分叉。
abstract final class MoccaTheme {
  // ----------------------------------------------------------- 兼容入口

  /// 旧的单一入口：暗色·抹绿。
  static ThemeData dark() => themeOf(MoccaPalette.green);

  /// 拐角半径：卡片、弹窗等统一圆角。
  static final BorderRadius _radius = BorderRadius.circular(18);

  // ----------------------------------------------------------- 主题构建

  /// 唯一的主题入口：依据所选配色构建 [ThemeData]。
  static ThemeData themeOf(MoccaPalette palette) {
    final scheme = _schemeOf(palette);
    return _buildTheme(scheme);
  }

  static ColorScheme _schemeOf(MoccaPalette p) {
    final t = p._tokens;
    final base = ColorScheme.fromSeed(
      seedColor: t.seed,
      brightness: p.brightness,
    );
    return base.copyWith(
      primary: t.primary,
      onPrimary: t.onPrimary,
      primaryContainer: t.primaryContainer,
      onPrimaryContainer: t.onPrimaryContainer,
      secondary: t.secondary,
      onSecondary: t.onSecondary,
      secondaryContainer: t.secondaryContainer,
      onSecondaryContainer: t.onSecondaryContainer,
      tertiary: t.tertiary,
      onTertiary: t.onTertiary,
      tertiaryContainer: t.tertiaryContainer,
      onTertiaryContainer: t.onTertiaryContainer,
      error: t.error,
      onError: t.onError,
      errorContainer: t.errorContainer,
      onErrorContainer: t.onErrorContainer,
      surface: t.surface,
      onSurface: t.onSurface,
      onSurfaceVariant: t.onSurfaceVariant,
      surfaceContainerLowest: t.surfaceContainerLowest,
      surfaceContainerLow: t.surfaceContainerLow,
      surfaceContainer: t.surfaceContainer,
      surfaceContainerHigh: t.surfaceContainerHigh,
      surfaceContainerHighest: t.surfaceContainerHighest,
      outline: t.outline,
      outlineVariant: t.outlineVariant,
      scrim: t.scrim,
      inverseSurface: t.inverseSurface,
      onInverseSurface: t.onInverseSurface,
      inversePrimary: t.inversePrimary,
    );
  }

  /// 组件级主题，随 [ColorScheme] 明暗而自适应。
  static ThemeData _buildTheme(ColorScheme scheme) {
    final radius = _radius;

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ------------------------------------------------------- 点缀色（兼容）
  //
  // 供渐变、封面占位等不需要参与 M3 角色映射的场景使用；统一取自抹茶绿配色。

  static const _sandAccent = Color(0xFFD8C4A0);
  static const _mocca = Color(0xFF9CC79C);
  static const _monetBlue = Color(0xFF92B4BE);
  static const _irisPurple = Color(0xFFC3B4D8);

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

  /// 依据可用宽度推荐栅格列数（图片墙、卡片列表用）。
  ///
  /// 取「格子宽度最接近 [target]」的那一档，而不是死记断点。这样跨宽度变化时
  /// 格子尺寸始终落在 target 附近的窄区间里，不会出现旧版那种
  /// 「899dp 时 4 列 208dp、900dp 时 6 列 135dp」的突兀收缩——屏幕稍宽一点
  /// 就把每一格挤小一半，看起来既拥挤又割裂。
  ///
  /// [available] 为扣掉左右外边距后的可用宽度。列数再多也不让格子窄于
  /// `140dp`——那是两行标题加一行说明还排得开的底线，再窄就只能靠截断文件名
  /// 凑合，反而更难认。
  static int gridColumns(
    double available, {
    double gutter = 12,
    double target = 180,
  }) {
    const minTile = 140.0;
    var best = 2;
    var bestDelta = double.infinity;
    for (var c = 2; c <= 12; c++) {
      final tile = (available - gutter * (c - 1)) / c;
      if (tile < minTile) break;
      final delta = (tile - target).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = c;
      }
    }
    return best;
  }

  /// 按屏幕宽度算出一整套自洽的网格横向尺寸（列数 / 格宽 / 间距 / 外边距）。
  ///
  /// 间距与外边距随断点放大：小屏紧凑省地方，大屏留白舒展。格高不在这里——
  /// 它取决于卡片里的字号行高，由使用方按自己的排版常量接着算。
  static GridSpec gridSpec(double width) {
    final compact = width < Breakpoints.compact;
    final gutter = compact ? 8.0 : (width < expanded ? 12.0 : 16.0);
    final margin = compact ? 10.0 : (width < expanded ? 16.0 : 24.0);
    final available = width - margin * 2;
    // 小屏目标格宽略小：手机上宁可多一列，也别让每格大到一屏只剩两个卡片。
    final columns = gridColumns(
      available,
      gutter: gutter,
      target: compact ? 165 : 185,
    );
    return (
      columns: columns,
      tileWidth: (available - gutter * (columns - 1)) / columns,
      gutter: gutter,
      margin: margin,
    );
  }

  /// 手机用底部导航栏，平板 / 大屏用侧边导航轨道。
  static bool useNavigationRail(double width) => width >= compact;
}

/// 网格的横向排版：列数、格宽、间距、外边距。
///
/// 格宽由「可用宽度 - 全部间距」整除得出，因此每行刚好铺满、不残留半格空隙。
typedef GridSpec = ({
  int columns,
  double tileWidth,
  double gutter,
  double margin,
});

/// 在任意位置取到当前宽度对应的断点判断。
extension BreakpointContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => Breakpoints.isCompact(screenWidth);
  bool get isTablet => !isCompact;
}
