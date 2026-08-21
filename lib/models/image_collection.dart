import 'image_metadata.dart';

/// Collection of images with utility methods.
class ImageCollection {
  final List<ImageMetadata> images;

  const ImageCollection({required this.images});

  /// Returns the number of images.
  int get count => images.length;

  /// Creates a copy with updated images.
  ImageCollection copyWith({List<ImageMetadata>? images}) {
    return ImageCollection(images: images ?? this.images);
  }

  /// Groups images by row number.
  Map<int, List<ImageMetadata>> groupByRow() {
    final Map<int, List<ImageMetadata>> grouped = {};
    for (final image in images) {
      grouped.putIfAbsent(image.row, () => []).add(image);
    }
    return grouped;
  }

  /// Gets unique cycle values.
  List<int> get uniqueCycles {
    return images.map((img) => img.cycle).toSet().toList()..sort();
  }

  /// Gets unique exposure time values.
  List<int> get uniqueExposureTimes {
    return images.map((img) => img.exposureTime).toSet().toList()..sort();
  }

  /// Gets unique row numbers.
  List<int> get uniqueRows {
    return images.map((img) => img.row).toSet().toList()..sort();
  }

  /// Gets unique column numbers.
  List<int> get uniqueColumns {
    return images.map((img) => img.column).toSet().toList()..sort();
  }

  /// Maps each grid column index to the barcode that identifies it.
  ///
  /// Derived from the images themselves rather than from a barcode's position
  /// in a sorted list, so a column whose images carry an empty barcode simply
  /// has no entry instead of borrowing another column's label (CR-01-16).
  Map<int, String> get barcodesByColumn {
    final byColumn = <int, String>{};
    for (final image in images) {
      final barcode = image.metadata['barcode'] as String? ?? '';
      if (barcode.isEmpty) continue;
      byColumn.putIfAbsent(image.column, () => barcode);
    }
    return byColumn;
  }

  /// Gets unique barcode values for column labels.
  List<String> get uniqueBarcodes {
    final barcodes = images
        .map((img) => img.metadata['barcode'] as String?)
        .where((b) => b != null && b.isNotEmpty)
        .toSet()
        .toList();
    barcodes.sort();
    return barcodes.cast<String>();
  }
}
