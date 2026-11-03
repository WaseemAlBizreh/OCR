import 'dart:async';

/// Thrown inside a read once its time limit has passed, so the steps left are
/// skipped. Apps never see it: the result says `ScanIssue.timedOut`.
class ScanTimedOutException implements Exception {
  const ScanTimedOutException();

  @override
  String toString() =>
      'ScanTimedOutException: the read took longer than its time limit';
}

/// The time limit of the read running in the current zone.
///
/// [run] returns on time even when a native call is stuck. The read itself
/// can't be interrupted, so its long loops call [check] between steps: once
/// the limit has passed, the read stops at the next step instead of running
/// to the end in the background. A step already running finishes first.
class ScanDeadline {
  ScanDeadline._(this._limit) : _clock = Stopwatch()..start();

  final Duration _limit;
  final Stopwatch _clock;

  static const _key = #idlensScanDeadline;

  /// Throws [ScanTimedOutException] when the read running in this zone has
  /// passed its time limit. Does nothing for a read without one.
  static void check() {
    final deadline = Zone.current[_key];
    if (deadline is ScanDeadline &&
        deadline._clock.elapsed >= deadline._limit) {
      throw const ScanTimedOutException();
    }
  }

  /// Runs [read] within [limit]: its value, or [onTimeout]'s when the limit
  /// passes first. With a null [limit], [read] runs with no limit.
  static Future<T> run<T>(
    Duration? limit,
    Future<T> Function() read,
    T Function() onTimeout,
  ) {
    if (limit == null) return read();
    final deadline = ScanDeadline._(limit);
    return runZoned(
      read,
      zoneValues: {_key: deadline},
    ).timeout(limit, onTimeout: onTimeout);
  }
}
