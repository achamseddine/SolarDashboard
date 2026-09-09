import 'dart:async';
import 'dart:collection';

/// Limits outbound API calls: at most [maxConcurrent] in flight and at least
/// [minGap] between the *start* of consecutive calls.
class RateLimiter {
  RateLimiter({this.maxConcurrent = 4, this.minGap = const Duration(milliseconds: 120)});

  final int maxConcurrent;
  final Duration minGap;

  int _inFlight = 0;
  DateTime? _lastStart;
  final Queue<Completer<void>> _waiters = Queue();

  int get inFlight => _inFlight;
  int get queued => _waiters.length;

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_inFlight >= maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _inFlight++;
    final now = DateTime.now();
    if (_lastStart != null) {
      final wait = minGap - now.difference(_lastStart!);
      if (wait > Duration.zero) {
        _lastStart = now.add(wait);
        await Future<void>.delayed(wait);
        return;
      }
    }
    _lastStart = now;
  }

  void _release() {
    _inFlight--;
    if (_waiters.isNotEmpty) _waiters.removeFirst().complete();
  }
}
