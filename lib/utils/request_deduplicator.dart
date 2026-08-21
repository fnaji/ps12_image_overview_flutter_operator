import 'dart:async';

/// De-duplicates concurrent asynchronous requests that share a key.
///
/// Without this, a widget rebuild while a download is pending starts a second
/// download of the same image (CR-01-31). Extracted from [TercenImageService]
/// so the de-duplication rule can be unit tested without faking the Tercen
/// service factory - see test strategy limitation L-04.
class RequestDeduplicator<T> {
  final Map<String, Future<T>> _inFlight = {};

  /// Whether a request for [key] is currently in flight.
  bool isPending(String key) => _inFlight.containsKey(key);

  /// Number of requests currently in flight.
  int get pendingCount => _inFlight.length;

  /// Returns the in-flight future for [key], or starts one via [start].
  ///
  /// Every caller asking for the same [key] before it settles receives the
  /// identical future, so the underlying work happens exactly once.
  ///
  /// The future from [start] is consumed here and its outcome forwarded through
  /// a completer. Chaining cleanup onto it directly would leave a derived future
  /// with no listener, which Dart reports as an unhandled async error when a
  /// request fails.
  Future<T> run(String key, Future<T> Function() start) {
    final pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }

    final completer = Completer<T>();
    _inFlight[key] = completer.future;

    start().then(
      (value) {
        _inFlight.remove(key);
        completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        _inFlight.remove(key);
        completer.completeError(error, stackTrace);
      },
    );

    return completer.future;
  }
}
