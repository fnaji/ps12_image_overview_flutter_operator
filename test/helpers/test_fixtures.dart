import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ps12_image_overview/di/service_locator.dart';
import 'package:ps12_image_overview/models/filter_criteria.dart';
import 'package:ps12_image_overview/models/image_collection.dart';
import 'package:ps12_image_overview/models/image_metadata.dart';
import 'package:ps12_image_overview/models/image_metadata_impl.dart';
import 'package:ps12_image_overview/providers/image_overview_provider.dart';
import 'package:ps12_image_overview/providers/theme_provider.dart';
import 'package:ps12_image_overview/screens/image_overview_screen.dart';
import 'package:ps12_image_overview/services/image_service.dart';

/// In-memory [ImageService] so tests need no Tercen connection.
///
/// Deliberately not a [TercenImageService], so [ImageGridCell] falls through to
/// its placeholder painter and no image decoding happens during widget tests.
class FakeImageService implements ImageService {
  FakeImageService(this.images);

  final List<ImageMetadata> images;

  int loadCallCount = 0;
  int filterCallCount = 0;
  FilterCriteria? lastCriteria;

  @override
  Future<ImageCollection> loadImages() async {
    loadCallCount++;
    return ImageCollection(images: images);
  }

  @override
  Future<ImageCollection> filterImages(FilterCriteria criteria) async {
    filterCallCount++;
    lastCriteria = criteria;

    return ImageCollection(
      images: images.where((image) {
        if (criteria.cycle != null && image.cycle != criteria.cycle) {
          return false;
        }
        if (criteria.exposureTime != null &&
            image.exposureTime != criteria.exposureTime) {
          return false;
        }
        return true;
      }).toList(),
    );
  }
}

/// Builds one image metadata entry.
ImageMetadataImpl testImage({
  required int row,
  required int column,
  String barcode = '',
  int cycle = 100,
  int exposureTime = 50,
  String? id,
}) {
  return ImageMetadataImpl(
    id: id ?? 'img_${row}_${column}_${cycle}_$exposureTime',
    cycle: cycle,
    exposureTime: exposureTime,
    row: row,
    column: column,
    timestamp: DateTime.utc(2026, 1, 1),
    metadata: {'barcode': barcode},
  );
}

/// Builds a full rectangular grid of images.
///
/// Barcodes are generated as 9-digit strings in the same ascending order as the
/// column index, matching how TercenImageService assigns columns.
List<ImageMetadata> testGrid({
  int rows = 4,
  int columns = 3,
  int firstRow = 0,
  List<int> cycles = const [100],
  List<int> exposureTimes = const [50],
  bool withBarcodes = true,
}) {
  final images = <ImageMetadata>[];

  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      for (final cycle in cycles) {
        for (final exposure in exposureTimes) {
          images.add(testImage(
            row: firstRow + r,
            column: c,
            barcode: withBarcodes ? '${641070500 + c}' : '',
            cycle: cycle,
            exposureTime: exposure,
          ));
        }
      }
    }
  }

  return images;
}

/// Registers [FakeImageService] and pumps [ImageOverviewScreen].
///
/// Returns the fake so tests can assert on call counts.
Future<FakeImageService> pumpOverviewScreen(
  WidgetTester tester, {
  required List<ImageMetadata> images,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await locator.reset();
  final service = FakeImageService(images);
  locator.registerSingleton<ImageService>(service);

  final themeProvider = ThemeProvider();
  themeProvider.setThemeMode(themeMode);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ImageOverviewProvider()),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, provider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: provider.themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: Colors.grey[100],
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: Colors.grey[900],
            ),
            home: const ImageOverviewScreen(),
          );
        },
      ),
    ),
  );

  await tester.pumpAndSettle();
  return service;
}

/// Returns the scroll position for [axis] within the widget keyed [ancestor].
ScrollPosition scrollPositionIn(
  WidgetTester tester,
  Key ancestor,
  Axis axis,
) {
  final states = tester.stateList<ScrollableState>(
    find.descendant(
      of: find.byKey(ancestor),
      matching: find.byType(Scrollable),
    ),
  );

  return states
      .map((state) => state.position)
      .firstWhere((position) => axisDirectionToAxis(position.axisDirection) == axis);
}

/// Jumps the grid body to [offset] on [axis] and settles the follower views.
Future<void> scrollBody(
  WidgetTester tester,
  Axis axis,
  double offset,
) async {
  final position = scrollPositionIn(tester, const Key('gridBody'), axis);
  position.jumpTo(offset.clamp(0, position.maxScrollExtent));
  await tester.pumpAndSettle();
}
