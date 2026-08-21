import 'package:flutter_test/flutter_test.dart';
import 'package:ps12_image_overview/models/image_collection.dart';

import '../helpers/test_fixtures.dart';

/// CR-01 test strategy TS-01..TS-04: column-to-barcode mapping (CR-01-16,
/// DEF-04, DEF-05).
void main() {
  group('ImageCollection.barcodesByColumn', () {
    test('TS-01: maps every column to its own barcode', () {
      final collection = ImageCollection(
        images: [
          testImage(row: 0, column: 0, barcode: '641070511'),
          testImage(row: 0, column: 1, barcode: '641070514'),
          testImage(row: 0, column: 2, barcode: '641070516'),
          testImage(row: 1, column: 0, barcode: '641070511'),
          testImage(row: 1, column: 1, barcode: '641070514'),
          testImage(row: 1, column: 2, barcode: '641070516'),
        ],
      );

      expect(collection.barcodesByColumn, {
        0: '641070511',
        1: '641070514',
        2: '641070516',
      });
    });

    test('TS-02: a column with empty barcodes gets no entry, and does not '
        'inherit another column\'s barcode', () {
      final collection = ImageCollection(
        images: [
          testImage(row: 0, column: 0, barcode: ''),
          testImage(row: 0, column: 1, barcode: '641070514'),
          testImage(row: 1, column: 0, barcode: ''),
          testImage(row: 1, column: 1, barcode: '641070514'),
        ],
      );

      final byColumn = collection.barcodesByColumn;

      expect(byColumn.containsKey(0), isFalse);
      expect(byColumn[1], '641070514');
      expect(byColumn.length, 1);
    });

    test('TS-03: empty image list yields an empty map without throwing', () {
      const collection = ImageCollection(images: []);

      expect(collection.barcodesByColumn, isEmpty);
    });

    test('TS-04: resolves labels when rows start at 1 instead of 0', () {
      final collection = ImageCollection(
        images: testGrid(rows: 4, columns: 3, firstRow: 1),
      );

      final byColumn = collection.barcodesByColumn;

      expect(byColumn.keys.toList()..sort(), [0, 1, 2]);
      expect(byColumn[0], '641070500');
      expect(byColumn[2], '641070502');
    });

    test('uses the first non-empty barcode found for a column', () {
      final collection = ImageCollection(
        images: [
          testImage(row: 0, column: 0, barcode: '', id: 'a'),
          testImage(row: 1, column: 0, barcode: '641070511', id: 'b'),
        ],
      );

      expect(collection.barcodesByColumn[0], '641070511');
    });
  });
}
