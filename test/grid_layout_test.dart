import 'package:flutter_test/flutter_test.dart';
import 'package:mocca/core/theme.dart';

void main() {
  group('网格响应式排版', () {
    // 覆盖常见的手机 / 平板 / 桌面宽度。455 是「2 列 → 3 列」切换前的临界值，
    // 格子在那里最宽，专门留着防回归。
    const widths = <double>[
      360,
      390,
      414,
      430,
      455,
      480,
      540,
      600,
      700,
      768,
      834,
      900,
      1024,
      1194,
      1280,
      1440,
      1600,
      1920,
      2560,
    ];

    test('列数随宽度单调不减', () {
      var prev = 0;
      for (final w in widths) {
        final columns = Breakpoints.gridSpec(w).columns;
        expect(columns, greaterThanOrEqualTo(prev), reason: '宽度 $w 的列数回退了');
        prev = columns;
      }
    });

    test('格子始终落在可读区间，既不挤也不空', () {
      for (final w in widths) {
        final tile = Breakpoints.gridSpec(w).tileWidth;
        expect(tile, greaterThanOrEqualTo(140), reason: '宽度 $w 的格子过窄：$tile');
        // 临界值处格子会伸到 210 出头，再多就该分裂成更多列了
        expect(tile, lessThanOrEqualTo(220), reason: '宽度 $w 的格子过宽：$tile');
      }
    });

    test('每行刚好铺满，不残留半格空隙', () {
      for (final w in widths) {
        final s = Breakpoints.gridSpec(w);
        final used = s.tileWidth * s.columns + s.gutter * (s.columns - 1);
        expect(used, closeTo(w - s.margin * 2, 0.01), reason: '宽度 $w 的行没铺满');
      }
    });

    test('间距与外边距随断点放大', () {
      expect(
        Breakpoints.gridSpec(360).gutter,
        lessThan(Breakpoints.gridSpec(768).gutter),
      );
      expect(
        Breakpoints.gridSpec(768).gutter,
        lessThan(Breakpoints.gridSpec(1280).gutter),
      );
      expect(
        Breakpoints.gridSpec(360).margin,
        lessThan(Breakpoints.gridSpec(1280).margin),
      );
    });

    test('极窄宽度回退到两列而不是崩掉', () {
      expect(Breakpoints.gridColumns(200), 2);
      expect(Breakpoints.gridColumns(0), 2);
    });
  });
}
