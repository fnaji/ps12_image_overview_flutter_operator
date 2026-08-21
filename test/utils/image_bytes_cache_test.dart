import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ps12_image_overview/utils/image_bytes_cache.dart';

/// CR-01 test strategy TS-07, TS-08: the synchronous read that lets a cached
/// image paint without a loading spinner (CR-01-30, CR-01-32).
///
/// `TercenImageService.cachedImage` is a direct delegate to `ImageBytesCache.get`
/// and `fetchAndConvertImage` consults the same method before queueing any
/// download, so the cache contract is what these assert. Verified end to end by
/// manual case TM-08.
///
/// NOTE: recency ordering is deliberately NOT asserted here. `ImageBytesCache`
/// tracks access times with `DateTime.now()`, whose resolution (~1ms on Windows)
/// is coarser than the interval between successive puts and gets, so entries
/// touched in the same tick tie and `_evictOldest` falls back to map iteration
/// (insertion) order. The cache is therefore closer to FIFO than LRU under fast
/// access. Out of CR-01 scope - recorded as a finding against the cache
/// capacity observation in the functional spec §7.2.
void main() {
  Uint8List bytes(int length, [int fill = 1]) =>
      Uint8List.fromList(List.filled(length, fill));

  group('ImageBytesCache', () {
    test('TS-07: get returns null before a put and bytes immediately after',
        () {
      final cache = ImageBytesCache();

      expect(cache.get('a'), isNull);
      expect(cache.contains('a'), isFalse);

      cache.put('a', bytes(16));

      // Synchronous read - no await, which is the whole point of CR-01-30.
      expect(cache.get('a'), isNotNull);
      expect(cache.get('a')!.length, 16);
      expect(cache.contains('a'), isTrue);
    });

    test('TS-08: a cached entry survives repeated reads', () {
      final cache = ImageBytesCache();
      cache.put('a', bytes(16));

      for (var i = 0; i < 5; i++) {
        expect(cache.get('a'), isNotNull);
      }

      expect(cache.length, 1);
    });

    test('re-putting the same id does not double-count cache size', () {
      final cache = ImageBytesCache();

      cache.put('a', bytes(100));
      final afterFirst = cache.currentSizeBytes;
      cache.put('a', bytes(100));

      expect(cache.currentSizeBytes, afterFirst);
      expect(cache.length, 1);
    });

    test('evicts to stay within capacity when full', () {
      final cache = ImageBytesCache(maxCacheSizeBytes: 300);

      cache.put('a', bytes(100));
      cache.put('b', bytes(100));
      cache.put('c', bytes(100));
      expect(cache.length, 3);

      cache.put('d', bytes(100));

      // Capacity is respected and the newest entry is retained.
      expect(cache.currentSizeBytes, lessThanOrEqualTo(300));
      expect(cache.length, 3);
      expect(cache.contains('d'), isTrue);
    });

    test('an entry larger than the whole cache is not stored', () {
      final cache = ImageBytesCache(maxCacheSizeBytes: 100);

      cache.put('big', bytes(200));

      expect(cache.contains('big'), isFalse);
      expect(cache.currentSizeBytes, 0);
    });

    test('clear empties the cache', () {
      final cache = ImageBytesCache();
      cache.put('a', bytes(16));

      cache.clear();

      expect(cache.get('a'), isNull);
      expect(cache.length, 0);
      expect(cache.currentSizeBytes, 0);
    });
  });
}
