import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ps12_image_overview/models/image_metadata.dart';
import 'package:ps12_image_overview/providers/image_overview_provider.dart';
import 'package:ps12_image_overview/providers/theme_provider.dart';
import 'package:ps12_image_overview/widgets/image_grid_cell.dart';

/// Aspect ratio of a PS12 fluorescence image: 552 x 413 px, measured from
/// instrument output rather than assumed.
///
/// Cells are shaped to match so nothing is spent on letterbox (CR-01-50). If a
/// dataset ever carries differently-shaped images, BoxFit.contain still
/// prevents distortion (CR-01-52) - such a cell simply letterboxes again.
const double imageAspectRatio = 552 / 413;

/// Rendered width of one image. Fixed by design: four rows deliberately exceed
/// the viewport and are reached by scrolling rather than shrunk to fit (CR-01
/// spec DEC-01, option A).
const double cellWidth = 250;

/// Rendered height, derived so the cell matches the image it holds.
///
/// Square 250x250 cells displayed these images at exactly 250x187 with 63px of
/// invisible black letterbox, wasting 252px across four rows. Matching the
/// ratio reclaims that at no cost to how large the image appears (CR-01-51).
const double cellHeight = cellWidth / imageAspectRatio;

/// Gap between adjacent cells, applied as trailing padding inside each slot.
const double cellGutter = 8;

/// Space occupied by one cell including its gutter, per axis.
const double slotWidth = cellWidth + cellGutter;
const double slotHeight = cellHeight + cellGutter;

/// Width of the pinned well-label column (W1, W2, ...).
const double rowLabelWidth = 34;

/// Pinned barcode header row, and the gap between it and the cells.
const double headerHeight = 22;
const double headerGap = 4;

/// Padding around the whole grid area.
const double gridPadding = 8;

/// Strip left free at the end of the scroll content on both axes, so the
/// always-visible scrollbars have somewhere to sit once scrolled to the extreme
/// instead of covering an image (CR-01-07). Mirrored into the header and label
/// scroll views to keep all extents identical.
const double scrollbarGutter = 12;

/// Filter bar height, excluding its 1px bottom border (CR-01-21).
const double filterBarHeight = 40;

/// Tercen brand teal, carried by the title now that the AppBar is gone.
const Color brandTeal = Color(0xFF005F75);
const Color brandTealDark = Color(0xFF4DB8CC);

/// Scrollbar colours (CR-01-53, CR-01-54).
///
/// The Material default is a dark translucent grey, which all but disappears
/// over PS12 fluorescence images - they are predominantly black. A bright teal
/// thumb over a light track keeps the affordance readable against the imagery
/// it overlays, which is the entire point of showing it permanently.
const Color scrollbarThumb = Color(0xFF4DB8CC);
const Color scrollbarThumbHover = Color(0xFF7FD4E3);
const Color scrollbarTrack = Color(0x26FFFFFF);
const Color scrollbarTrackBorder = Color(0x40FFFFFF);
const double scrollbarThickness = 12;

/// Main screen displaying the image overview with filters and grid.
///
/// Implements CR-01. The grid is a four-quadrant scrolling layout: the barcode
/// header row is pinned vertically, the well-label column is pinned
/// horizontally, and the image cells scroll on both axes through a single
/// shared viewport so every well row stays aligned to the same columns. Header
/// and label column follow the body's controllers rather than owning scroll
/// physics of their own.
class ImageOverviewScreen extends StatefulWidget {
  const ImageOverviewScreen({super.key});

  @override
  State<ImageOverviewScreen> createState() => _ImageOverviewScreenState();
}

class _ImageOverviewScreenState extends State<ImageOverviewScreen> {
  /// Body controllers - the ones the user drives.
  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _bodyVertical = ScrollController();

  /// Follower controllers for the pinned header row and label column.
  final ScrollController _headerHorizontal = ScrollController();
  final ScrollController _labelsVertical = ScrollController();

  @override
  void initState() {
    super.initState();
    _bodyHorizontal
        .addListener(() => _follow(_bodyHorizontal, _headerHorizontal));
    _bodyVertical.addListener(() => _follow(_bodyVertical, _labelsVertical));

    // Load images when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ImageOverviewProvider>().loadImages();
    });
  }

  @override
  void dispose() {
    _bodyHorizontal.dispose();
    _bodyVertical.dispose();
    _headerHorizontal.dispose();
    _labelsVertical.dispose();
    super.dispose();
  }

  /// Mirrors [leader]'s offset onto [follower] (CR-01-12, CR-01-14).
  ///
  /// Both scroll views are built with identical extents, but the offset is
  /// clamped regardless so a transient layout mismatch cannot throw (risk
  /// R-01).
  void _follow(ScrollController leader, ScrollController follower) {
    if (!leader.hasClients || !follower.hasClients) return;

    final position = follower.position;
    final target = leader.offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    if ((follower.offset - target).abs() > 0.5) {
      follower.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<ImageOverviewProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.images.count == 0) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Text(
                'Error: ${provider.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          // No SizedBox between the bar and the grid: the former 8px gap let
          // the Scaffold background show through and read as a divider. The
          // filter bar's 1px bottom border is the intended separator.
          return Column(
            children: [
              _buildFilterBar(context, provider),
              Expanded(
                child: Container(
                  color: const Color(0xFFf8f9ff),
                  child: _buildImageGrid(provider),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Builds the single-line title / filter / theme-toggle bar (CR-01-20..25).
  ///
  /// Replaces the former AppBar plus stacked-label filter block, which
  /// together cost ~172px; this bar costs 41px including its border.
  Widget _buildFilterBar(
      BuildContext context, ImageOverviewProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: const Key('filterBar'),
      height: filterBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          // The title and filters scroll horizontally rather than overflow
          // (CR-01-57). Target screen sizes are unknown, and at ~780px and
          // below a fixed Row overflows. Expanded gives the scroll view a
          // tight width, so its content stays left-aligned when it fits -
          // the same trap that caused DEF-09.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'Image Overview',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? brandTealDark : brandTeal,
                    ),
                  ),
                  const SizedBox(width: 24),
                  _buildFilterLabel('Pump Cycle'),
                  const SizedBox(width: 6),
                  _buildDropdown(
                    key: const Key('cycleDropdown'),
                    value: provider.filters.cycle,
                    items: provider.availableCycles.reversed.toList(),
                    onChanged: provider.setCycleFilter,
                  ),
                  const SizedBox(width: 20),
                  _buildFilterLabel('Exposure Time'),
                  const SizedBox(width: 6),
                  _buildDropdown(
                    key: const Key('exposureDropdown'),
                    value: provider.filters.exposureTime,
                    items: provider.availableExposureTimes.reversed.toList(),
                    onChanged: provider.setExposureTimeFilter,
                  ),
                  // Keeps the last control clear of the pinned theme toggle.
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                icon: Icon(
                  themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                ),
                iconSize: 18,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                tooltip: themeProvider.isDarkMode
                    ? 'Switch to Light Mode'
                    : 'Switch to Dark Mode',
                onPressed: themeProvider.toggleTheme,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Builds an inline filter label, beside its control rather than above it
  /// (CR-01-22).
  Widget _buildFilterLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    );
  }

  /// Builds a dropdown sized to its numeric content (CR-01-23).
  ///
  /// 72px covers 4 digits at 13px (~30px) plus an 18px icon and 16px padding.
  Widget _buildDropdown({
    required Key key,
    required int? value,
    required List<int> items,
    required void Function(int?) onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      key: key,
      width: 72,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(3),
        color: isDark ? Colors.grey.shade800 : Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          hint: Text(
            '—',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          isExpanded: true,
          isDense: true,
          itemHeight: null,
          iconSize: 18,
          style: TextStyle(fontSize: 13, color: textColor),
          dropdownColor: isDark ? Colors.grey.shade800 : Colors.white,
          items: items
              .map((item) => DropdownMenuItem<int?>(
                    value: item,
                    child: Text(
                      item.toString(),
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Builds the image grid.
  /// Maintains full grid structure even when no images match the filter,
  /// showing "no image" placeholders in empty cells.
  Widget _buildImageGrid(ImageOverviewProvider provider) {
    // Get the full grid structure from all images (not just filtered)
    final allRows = provider.allRows;
    final allColumns = provider.allColumns;
    final barcodesByColumn = provider.allBarcodesByColumn;

    // If no images loaded at all, show empty state
    if (allRows.isEmpty || allColumns.isEmpty) {
      return const Center(
        child: Text('No images to display'),
      );
    }

    // Create a lookup map for quick access to filtered images
    final imagesByPosition = <String, ImageMetadata>{};
    for (final image in provider.images.images) {
      final key = '${image.row}_${image.column}';
      imagesByPosition[key] = image;
    }

    return Padding(
      padding: const EdgeInsets.all(gridPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPinnedRowLabels(allRows),
          Expanded(
            child: Column(
              // Must be stretch, not the default center (CR-01-55). Center
              // hands children loose width constraints, and a
              // SingleChildScrollView under loose constraints shrink-wraps to
              // its content - so on a screen wider than the grid, the header
              // and cells sized themselves to the content and were centred,
              // drifting away from the row labels pinned at the left.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPinnedColumnHeader(allColumns, barcodesByColumn),
                const SizedBox(height: headerGap),
                Expanded(
                  child: _buildScrollableCells(
                    allRows,
                    allColumns,
                    imagesByPosition,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom-left quadrant: well labels, pinned horizontally (CR-01-13).
  ///
  /// Follows the body vertically (CR-01-14) and has no physics of its own.
  Widget _buildPinnedRowLabels(List<int> allRows) {
    return SizedBox(
      key: const Key('rowLabels'),
      width: rowLabelWidth,
      child: Column(
        children: [
          // Corner spacer, matching the pinned header beside it.
          const SizedBox(height: headerHeight + headerGap),
          Expanded(
            child: SingleChildScrollView(
              controller: _labelsVertical,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  ...allRows.map((rowNumber) => SizedBox(
                        height: slotHeight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: cellGutter),
                          // Key sits on the content box, not the slot, so it
                          // spans exactly the same height as its row of cells.
                          child: Center(
                            key: Key('rowLabel_$rowNumber'),
                            child: Text(
                              'W${rowNumber + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )),
                  // Mirrors the body's trailing gutter so both scroll views
                  // share the same extent and stay in sync at the end.
                  const SizedBox(height: scrollbarGutter),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Top-right quadrant: barcode labels, pinned vertically (CR-01-10,
  /// CR-01-11).
  ///
  /// Follows the body horizontally (CR-01-12). Sourced from the column-keyed
  /// map, so a column without a barcode shows nothing rather than borrowing a
  /// neighbour's label (CR-01-16).
  Widget _buildPinnedColumnHeader(
    List<int> allColumns,
    Map<int, String> barcodesByColumn,
  ) {
    return SizedBox(
      key: const Key('barcodeHeader'),
      height: headerHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _headerHorizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            ...allColumns.map((columnNumber) => SizedBox(
                  width: slotWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: cellGutter),
                    // Key sits on the content box, not the slot, so it spans
                    // exactly the same width as the cell it labels.
                    child: Center(
                      key: Key('barcode_$columnNumber'),
                      child: Text(
                        barcodesByColumn[columnNumber] ?? '',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )),
            // Mirrors the body's trailing gutter to keep extents identical.
            const SizedBox(width: scrollbarGutter),
          ],
        ),
      ),
    );
  }

  /// Bottom-right quadrant: the image cells, scrolling on both axes.
  ///
  /// One shared horizontal viewport for all rows (CR-01-01), so columns cannot
  /// fall out of alignment. Both scrollbars are permanently visible and
  /// draggable (CR-01-02, CR-01-03, CR-01-05), and mouse drag-panning is
  /// enabled because Flutter omits mice from ScrollBehavior.dragDevices by
  /// default (CR-01-04).
  Widget _buildScrollableCells(
    List<int> allRows,
    List<int> allColumns,
    Map<String, ImageMetadata> imagesByPosition,
  ) {
    return ScrollConfiguration(
      key: const Key('gridBody'),
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll(true),
          trackVisibility: const WidgetStatePropertyAll(true),
          thickness: const WidgetStatePropertyAll(scrollbarThickness),
          radius: const Radius.circular(6),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)) {
              return scrollbarThumbHover;
            }
            return scrollbarThumb;
          }),
          trackColor: const WidgetStatePropertyAll(scrollbarTrack),
          trackBorderColor:
              const WidgetStatePropertyAll(scrollbarTrackBorder),
        ),
        child: Scrollbar(
          controller: _bodyVertical,
          thumbVisibility: true,
          interactive: true,
          child: Scrollbar(
            controller: _bodyHorizontal,
            thumbVisibility: true,
            interactive: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            notificationPredicate: (notification) => notification.depth == 1,
            child: SingleChildScrollView(
              controller: _bodyVertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _bodyHorizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...allRows.map((rowNumber) => Row(
                          children: [
                            ...allColumns.map((columnNumber) {
                              final image = imagesByPosition[
                                  '${rowNumber}_$columnNumber'];

                              return Padding(
                                padding: const EdgeInsets.only(
                                  right: cellGutter,
                                  bottom: cellGutter,
                                ),
                                child: SizedBox(
                                  key: Key('cell_${rowNumber}_$columnNumber'),
                                  width: cellWidth,
                                  height: cellHeight,
                                  child: image != null
                                      ? ImageGridCell(image: image)
                                      : _buildEmptyCell(),
                                ),
                              );
                            }),
                            // Room for the vertical scrollbar at full right
                            // scroll (CR-01-07).
                            const SizedBox(width: scrollbarGutter),
                          ],
                        )),
                    // Room for the horizontal scrollbar at full bottom scroll
                    // (CR-01-07), and keeps this extent equal to the label
                    // column's.
                    const SizedBox(height: scrollbarGutter),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds an empty cell placeholder when no image exists for that grid
  /// position.
  Widget _buildEmptyCell() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border.all(
          color: Colors.grey.shade800,
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              color: Colors.grey.shade700,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'No image',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
