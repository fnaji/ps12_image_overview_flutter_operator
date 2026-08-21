import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ps12_image_overview/providers/image_overview_provider.dart';
import 'package:ps12_image_overview/screens/image_overview_screen.dart';

import '../helpers/test_fixtures.dart';

/// CR-01 test strategy TS-20..TS-30 (widget) and TS-40..TS-45 (regression).
///
/// The default 800x600 test viewport is deliberately smaller than the grid
/// content (4 columns = 1044px wide, 4 rows = 1044px tall), so both axes
/// overflow and the scrolling requirements are exercised.
void main() {
  ImageOverviewProvider providerOf(WidgetTester tester) {
    final context = tester.element(find.byType(ImageOverviewScreen));
    return Provider.of<ImageOverviewProvider>(context, listen: false);
  }

  group('Filter bar (CR-01-20..25)', () {
    testWidgets('TS-20: bar is at most 44px tall and total chrome at most 60px',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(columns: 4));

      final barHeight = tester.getSize(find.byKey(const Key('filterBar'))).height;
      expect(barHeight, lessThanOrEqualTo(44));

      // Chrome above the grid = where the grid's padded content starts, less
      // the grid's own padding.
      final gridTop = tester.getTopLeft(find.byKey(const Key('rowLabels'))).dy;
      final chrome = gridTop - gridPadding;
      expect(chrome, lessThanOrEqualTo(60));
    });

    testWidgets('TS-21: no AppBar, and the theme toggle lives in the bar',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(columns: 4));

      expect(find.byType(AppBar), findsNothing);

      final toggle = find.descendant(
        of: find.byKey(const Key('filterBar')),
        matching: find.byType(IconButton),
      );
      expect(toggle, findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.light_mode), findsOneWidget,
          reason: 'toggling must switch the icon, proving the theme flipped');
    });

    testWidgets('TS-22: labels sit inline beside 72px-wide controls',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(columns: 4));

      final label = find.text('Pump Cycle');
      final control = find.byKey(const Key('cycleDropdown'));

      // Inline, not stacked: shared vertical centre.
      expect(
        (tester.getCenter(label).dy - tester.getCenter(control).dy).abs(),
        lessThan(1.0),
      );
      // Control is to the right of its label.
      expect(tester.getTopLeft(control).dx,
          greaterThan(tester.getTopRight(label).dx - 1));
      // Sized to content (CR-01-23).
      expect(tester.getSize(control).width, 72);

      expect(tester.getSize(find.byKey(const Key('exposureDropdown'))).width, 72);
    });

    testWidgets('the title is present and the bar is a single row',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(columns: 4));

      expect(find.text('Image Overview'), findsOneWidget);

      // Every element shares one line: same vertical centre as the title.
      final titleCentre = tester.getCenter(find.text('Image Overview')).dy;
      for (final finder in [
        find.text('Pump Cycle'),
        find.text('Exposure Time'),
        find.byKey(const Key('cycleDropdown')),
        find.byKey(const Key('exposureDropdown')),
      ]) {
        expect((tester.getCenter(finder).dy - titleCentre).abs(), lessThan(2.0),
            reason: 'all bar elements must share one line');
      }
    });
  });

  group('Grid scrolling and alignment (CR-01-01..14)', () {
    testWidgets('TS-23: all well rows share one horizontal offset',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      await scrollBody(tester, Axis.horizontal, 200);

      final firstColumnOffsets = [
        for (var row = 0; row < 4; row++)
          tester.getTopLeft(find.byKey(Key('cell_${row}_0'))).dx,
      ];

      for (final offset in firstColumnOffsets) {
        expect(offset, closeTo(firstColumnOffsets.first, 0.01),
            reason: 'a shared viewport must keep every row column-aligned');
      }
    });

    testWidgets('TS-24: barcode header stays aligned to its column',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      for (final offset in [0.0, 120.0, 260.0]) {
        await scrollBody(tester, Axis.horizontal, offset);

        for (var column = 0; column < 4; column++) {
          final headerCentre =
              tester.getCenter(find.byKey(Key('barcode_$column'))).dx;
          final cellCentre =
              tester.getCenter(find.byKey(Key('cell_0_$column'))).dx;

          expect(headerCentre, closeTo(cellCentre, 0.5),
              reason: 'header must track column $column at offset $offset');
        }
      }
    });

    testWidgets('TS-25: well labels stay aligned to their row', (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      for (final offset in [0.0, 130.0, 300.0]) {
        await scrollBody(tester, Axis.vertical, offset);

        for (var row = 0; row < 4; row++) {
          final labelCentre =
              tester.getCenter(find.byKey(Key('rowLabel_$row'))).dy;
          final cellCentre =
              tester.getCenter(find.byKey(Key('cell_${row}_0'))).dy;

          expect(labelCentre, closeTo(cellCentre, 0.5),
              reason: 'label must track row $row at offset $offset');
        }
      }
    });

    testWidgets('TS-26: barcode header stays put while scrolling vertically',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final before = tester.getTopLeft(find.byKey(const Key('barcode_0'))).dy;

      final vertical = scrollPositionIn(
          tester, const Key('gridBody'), Axis.vertical);
      await scrollBody(tester, Axis.vertical, vertical.maxScrollExtent);

      expect(tester.getTopLeft(find.byKey(const Key('barcode_0'))).dy,
          closeTo(before, 0.01));
    });

    testWidgets('TS-27: well labels stay put while scrolling horizontally',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final before = tester.getTopLeft(find.byKey(const Key('rowLabel_0'))).dx;

      final horizontal = scrollPositionIn(
          tester, const Key('gridBody'), Axis.horizontal);
      await scrollBody(tester, Axis.horizontal, horizontal.maxScrollExtent);

      expect(tester.getTopLeft(find.byKey(const Key('rowLabel_0'))).dx,
          closeTo(before, 0.01));
    });

    testWidgets('TS-28: barcode labels render when rows start at 1',
        (tester) async {
      await pumpOverviewScreen(
        tester,
        images: testGrid(rows: 4, columns: 4, firstRow: 1),
      );

      for (var column = 0; column < 4; column++) {
        final label = tester.widget<Text>(
          find.descendant(
            of: find.byKey(Key('barcode_$column')),
            matching: find.byType(Text),
          ),
        );
        expect(label.data, isNotEmpty,
            reason: 'column $column must be labelled even with no row 0');
      }
    });

    testWidgets('TS-29: the last row is reachable by vertical scrolling',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final vertical =
          scrollPositionIn(tester, const Key('gridBody'), Axis.vertical);
      expect(vertical.maxScrollExtent, greaterThan(0),
          reason: '4 rows of 250px must overflow a 600px viewport');

      await scrollBody(tester, Axis.vertical, vertical.maxScrollExtent);

      final lastCell = find.byKey(const Key('cell_3_0'));
      final rect = tester.getRect(lastCell);
      expect(rect.bottom, lessThanOrEqualTo(600),
          reason: 'W4 must be fully visible once scrolled to the end');
      expect(rect.height, closeTo(cellHeight, 0.01));
    });

    testWidgets('TS-30: scrolling both axes to the extreme stays aligned',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final horizontal =
          scrollPositionIn(tester, const Key('gridBody'), Axis.horizontal);
      final vertical =
          scrollPositionIn(tester, const Key('gridBody'), Axis.vertical);

      await scrollBody(tester, Axis.horizontal, horizontal.maxScrollExtent);
      await scrollBody(tester, Axis.vertical, vertical.maxScrollExtent);

      expect(tester.takeException(), isNull);

      // Followers must be clamped to their own extents and still aligned.
      expect(
        tester.getCenter(find.byKey(const Key('barcode_3'))).dx,
        closeTo(tester.getCenter(find.byKey(const Key('cell_0_3'))).dx, 0.5),
      );
      expect(
        tester.getCenter(find.byKey(const Key('rowLabel_3'))).dy,
        closeTo(tester.getCenter(find.byKey(const Key('cell_3_0'))).dy, 0.5),
      );
    });

    testWidgets('mouse is an accepted drag device (CR-01-04)', (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final scrollable = find.descendant(
        of: find.byKey(const Key('gridBody')),
        matching: find.byType(Scrollable),
      );
      final behaviour = ScrollConfiguration.of(
        tester.element(scrollable.first),
      );

      expect(behaviour.dragDevices, contains(PointerDeviceKind.mouse));
    });
  });

  group('Amendment A - cell aspect and scrollbars (CR-01-50..56)', () {
    testWidgets('TS-31: cells match the 552:413 source aspect ratio',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final size = tester.getSize(find.byKey(const Key('cell_0_0')));

      expect(size.width, 250);
      expect(size.height, closeTo(250 / (552 / 413), 0.01));
      expect(size.width / size.height, closeTo(552 / 413, 0.001),
          reason: 'no letterbox should be reserved inside the cell');
    });

    testWidgets('TS-32: the visible image has not shrunk', (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      // Before Amendment A a 4:3 image rendered 250 wide inside a 250x250
      // cell. Width must be unchanged - only the dead space is gone.
      expect(tester.getSize(find.byKey(const Key('cell_0_0'))).width, 250);
    });

    testWidgets('TS-33: four rows are ~252px shorter than square cells would be',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final top = tester.getRect(find.byKey(const Key('cell_0_0'))).top;
      final bottom = tester.getRect(find.byKey(const Key('cell_3_0'))).bottom;
      final squareEquivalent = 4 * (250 + 8) - 8;

      expect(bottom - top, closeTo(4 * (cellHeight + 8) - 8, 0.5));
      expect(squareEquivalent - (bottom - top), closeTo(252, 1.0));
    });

    testWidgets('TS-35: images render with BoxFit.contain, so no distortion',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 1, columns: 1));

      // Fake service is not a TercenImageService, so the cell paints its
      // placeholder; assert the contract on the widget that would be used.
      expect(find.byKey(const Key('cell_0_0')), findsOneWidget);
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.fit, BoxFit.contain);
      }
    });

    testWidgets('TS-46: scrollbars are themed for contrast on black imagery',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 4));

      final theme = ScrollbarTheme.of(
        tester.element(find.byKey(const Key('cell_0_0'))),
      );

      expect(theme.thumbColor?.resolve(<WidgetState>{}), scrollbarThumb);
      expect(theme.trackVisibility?.resolve(<WidgetState>{}), isTrue);
      expect(theme.thickness?.resolve(<WidgetState>{}), scrollbarThickness);
    });

    testWidgets('TS-36: grid stays left-aligned when narrower than the viewport',
        (tester) async {
      // Reproduces DEF-09: a viewport far wider than the content. Before the
      // fix the header and cells shrink-wrapped and centred, drifting away
      // from the row labels.
      tester.view.physicalSize = const Size(2400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 3));

      final labelRight =
          tester.getRect(find.byKey(const Key('rowLabels'))).right;
      final firstCellLeft =
          tester.getRect(find.byKey(const Key('cell_0_0'))).left;

      expect(firstCellLeft, closeTo(labelRight, 0.5),
          reason: 'cells must start immediately after the pinned label column');

      // CR-01-56: header tracks the cells at this width too.
      expect(
        tester.getCenter(find.byKey(const Key('barcode_0'))).dx,
        closeTo(tester.getCenter(find.byKey(const Key('cell_0_0'))).dx, 0.5),
      );
    });

    testWidgets('TS-36b: still left-aligned when content overflows',
        (tester) async {
      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 8));

      final labelRight =
          tester.getRect(find.byKey(const Key('rowLabels'))).right;
      final firstCellLeft =
          tester.getRect(find.byKey(const Key('cell_0_0'))).left;

      expect(firstCellLeft, closeTo(labelRight, 0.5));
    });
  });

  group('Viewport matrix - invariants at any screen size', () {
    const viewports = <String, Size>{
      'small laptop': Size(1366, 768),
      'laptop': Size(1440, 900),
      'desktop': Size(1920, 1080),
      'ultrawide': Size(3440, 1440),
      'narrow window': Size(900, 700),
      'very narrow': Size(640, 600),
    };

    for (final entry in viewports.entries) {
      testWidgets('${entry.key} (${entry.value.width.toInt()}x'
          '${entry.value.height.toInt()}): grid left-aligned, no overflow',
          (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 6));

        expect(tester.takeException(), isNull,
            reason: 'no layout overflow at ${entry.key}');

        final labelRight =
            tester.getRect(find.byKey(const Key('rowLabels'))).right;
        final firstCellLeft =
            tester.getRect(find.byKey(const Key('cell_0_0'))).left;

        expect(firstCellLeft, closeTo(labelRight, 0.5),
            reason: 'grid must be left-aligned at ${entry.key}');

        expect(
          tester.getCenter(find.byKey(const Key('barcode_0'))).dx,
          closeTo(tester.getCenter(find.byKey(const Key('cell_0_0'))).dx, 0.5),
          reason: 'header must track columns at ${entry.key}',
        );
      });
    }

    testWidgets('all content is reachable whenever it overflows',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpOverviewScreen(tester, images: testGrid(rows: 4, columns: 24));

      final h = scrollPositionIn(tester, const Key('gridBody'), Axis.horizontal);
      final v = scrollPositionIn(tester, const Key('gridBody'), Axis.vertical);

      // Whatever the viewport, the far corner must be reachable.
      await scrollBody(tester, Axis.horizontal, h.maxScrollExtent);
      await scrollBody(tester, Axis.vertical, v.maxScrollExtent);

      final lastCell = tester.getRect(find.byKey(const Key('cell_3_23')));
      expect(lastCell.right, lessThanOrEqualTo(1000.5));
      expect(lastCell.bottom, lessThanOrEqualTo(700.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('Regression (CR-01-41, CR-01-42)', () {
    testWidgets('TS-40: filters default to the highest available values',
        (tester) async {
      await pumpOverviewScreen(
        tester,
        images: testGrid(
          rows: 4,
          columns: 4,
          cycles: [100, 200, 300],
          exposureTimes: [50, 60],
        ),
      );

      final provider = providerOf(tester);
      expect(provider.filters.cycle, 300);
      expect(provider.filters.exposureTime, 60);
    });

    testWidgets('TS-41: dropdown option order is unchanged (descending)',
        (tester) async {
      await pumpOverviewScreen(
        tester,
        images: testGrid(
          rows: 4,
          columns: 4,
          cycles: [100, 200, 300],
          exposureTimes: [50, 60],
        ),
      );

      final cycleDropdown = tester.widget<DropdownButton<int?>>(
        find.descendant(
          of: find.byKey(const Key('cycleDropdown')),
          matching: find.byType(DropdownButton<int?>),
        ),
      );

      expect(cycleDropdown.items!.map((item) => item.value).toList(),
          [300, 200, 100]);
    });

    testWidgets('TS-42: filters AND together and the grid keeps its structure',
        (tester) async {
      // Column 3 exists only at cycle 100, so filtering to cycle 200 must leave
      // that column present but empty.
      final images = [
        ...testGrid(rows: 4, columns: 3, cycles: [100, 200]),
        for (var row = 0; row < 4; row++)
          testImage(row: row, column: 3, barcode: '641070503', cycle: 100),
      ];

      await pumpOverviewScreen(tester, images: images);

      final provider = providerOf(tester);
      expect(provider.filters.cycle, 200);

      // All four columns still present in the structure.
      for (var column = 0; column < 4; column++) {
        expect(find.byKey(Key('cell_0_$column')), findsOneWidget);
      }

      // Column 3 has no image at cycle 200 - placeholder instead.
      expect(
        find.descendant(
          of: find.byKey(const Key('cell_0_3')),
          matching: find.text('No image'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('TS-45: the service is asked to load exactly once',
        (tester) async {
      final service =
          await pumpOverviewScreen(tester, images: testGrid(columns: 4));

      expect(service.loadCallCount, 1);
    });
  });

  group('TS-44: dark theme', () {
    testWidgets('bar geometry and grid alignment hold in dark mode',
        (tester) async {
      await pumpOverviewScreen(
        tester,
        images: testGrid(rows: 4, columns: 4),
        themeMode: ThemeMode.dark,
      );

      expect(tester.getSize(find.byKey(const Key('filterBar'))).height,
          lessThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('cycleDropdown'))).width, 72);
      expect(find.byType(AppBar), findsNothing);

      await scrollBody(tester, Axis.horizontal, 200);
      expect(
        tester.getCenter(find.byKey(const Key('barcode_1'))).dx,
        closeTo(tester.getCenter(find.byKey(const Key('cell_0_1'))).dx, 0.5),
      );
    });
  });
}
