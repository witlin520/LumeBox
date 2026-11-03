/// Smooth media time between AVPlayer/MPV reports and MDK polling samples.
/// [frame] is monotonic elapsed time, never wall-clock time.
class PlaybackClock {
  Duration _sample = Duration.zero, _sampleFrame = Duration.zero;
  Duration _position = Duration.zero, _lastFrame = Duration.zero;
  bool _initialized = false, _playing = false;
  double _rate = 1;
  static const stallBudget = Duration(seconds: 1);

  Duration advance({
    required Duration sample,
    required Duration frame,
    required bool playing,
    double rate = 1,
  }) {
    rate = rate.isFinite && rate > 0 ? rate : 1;
    final restart = !_initialized || frame < _lastFrame;
    final seek =
        !restart &&
        (sample - _sample < const Duration(milliseconds: -150) ||
            sample - _sample > const Duration(seconds: 2));
    if (restart || sample != _sample || playing != _playing || rate != _rate) {
      _sampleFrame = frame;
    }
    final elapsed = (frame - _sampleFrame).inMicroseconds.clamp(
      0,
      stallBudget.inMicroseconds,
    );
    final target =
        sample + Duration(microseconds: playing ? (elapsed * rate).round() : 0);
    if (restart ||
        seek ||
        !playing ||
        (target - _position).inMilliseconds.abs() > 2000) {
      _position = target;
    } else {
      final delta = (frame - _lastFrame).inMicroseconds.clamp(
        0,
        stallBudget.inMicroseconds,
      );
      final predicted =
          _position + Duration(microseconds: (delta * rate).round());
      final limit = (delta * rate * .1).round();
      final correction = ((target - predicted).inMicroseconds * .12)
          .round()
          .clamp(-limit, limit);
      final next = predicted + Duration(microseconds: correction);
      final ceiling =
          sample +
          Duration(microseconds: (stallBudget.inMicroseconds * rate).round());
      _position = next > ceiling ? ceiling : next;
    }
    _sample = sample;
    _lastFrame = frame;
    _playing = playing;
    _rate = rate;
    _initialized = true;
    return _position;
  }
}
