import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ps12_image_overview/utils/request_deduplicator.dart';

/// CR-01 test strategy TS-05, TS-06: one download per image regardless of how
/// many callers ask for it (CR-01-31).
///
/// Tested here rather than through TercenImageService because constructing that
/// service requires a Tercen ServiceFactory - see test strategy limitation
/// L-04. The service-level behaviour is covered manually by TM-08.
void main() {
  group('RequestDeduplicator', () {
    test('TS-05: concurrent callers for the same key share one invocation',
        () async {
      final deduplicator = RequestDeduplicator<int>();
      final completer = Completer<int>();
      var starts = 0;

      Future<int> start() {
        starts++;
        return completer.future;
      }

      final first = deduplicator.run('a', start);
      final second = deduplicator.run('a', start);
      final third = deduplicator.run('a', start);

      expect(starts, 1, reason: 'work must be started exactly once');
      expect(identical(first, second), isTrue);
      expect(identical(second, third), isTrue);
      expect(deduplicator.isPending('a'), isTrue);

      completer.complete(7);

      expect(await first, 7);
      expect(await second, 7);
      expect(await third, 7);
    });

    test('TS-06: a key is released once settled, so a later call starts fresh',
        () async {
      final deduplicator = RequestDeduplicator<int>();
      var starts = 0;

      Future<int> start() async {
        starts++;
        return starts;
      }

      expect(await deduplicator.run('a', start), 1);
      expect(deduplicator.isPending('a'), isFalse);
      expect(deduplicator.pendingCount, 0);

      expect(await deduplicator.run('a', start), 2);
      expect(starts, 2);
    });

    test('different keys do not share an invocation', () async {
      final deduplicator = RequestDeduplicator<String>();
      final gate = Completer<void>();
      final started = <String>[];

      Future<String> start(String key) async {
        started.add(key);
        await gate.future;
        return key;
      }

      final a = deduplicator.run('a', () => start('a'));
      final b = deduplicator.run('b', () => start('b'));

      expect(deduplicator.pendingCount, 2);
      gate.complete();

      expect(await a, 'a');
      expect(await b, 'b');
      expect(started, ['a', 'b']);
    });

    test('a failed request is released and does not go unhandled', () async {
      final deduplicator = RequestDeduplicator<int>();

      final future = deduplicator.run('a', () async => throw StateError('boom'));

      await expectLater(future, throwsStateError);
      expect(deduplicator.isPending('a'), isFalse);

      // A retry after failure must start new work rather than replay the error.
      expect(await deduplicator.run('a', () async => 5), 5);
    });
  });
}
