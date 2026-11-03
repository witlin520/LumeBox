import '../../core/player/player_settings.dart';
import '../../core/source/source.dart';

/// Only chooses an existing address. No requests, retries or adaptive bitrate policy.
class PlaybackQualityPreference {
  static bool isOriginal(String label) =>
      RegExp(r'原[画畫]|original|source', caseSensitive: false).hasMatch(label);
  static VideoQuality? select(
    List<VideoQuality> qualities,
    PlayerSettings settings,
  ) {
    if (settings.rememberManualQuality &&
        settings.manualQualityLabel.isNotEmpty) {
      for (final quality in qualities) {
        if (quality.label == settings.manualQualityLabel) return quality;
      }
    }
    final preset = settings.defaultQuality;
    if (preset == DefaultQuality.original ||
        preset == DefaultQuality.automatic) {
      for (final quality in qualities) {
        if (isOriginal(quality.label)) return quality;
      }
    } else {
      for (final quality in qualities) {
        if (quality.resolutionRank == preset.height) return quality;
      }
    }
    VideoQuality? best;
    var rank = -1;
    for (final quality in qualities) {
      if (quality.resolutionRank > rank) {
        best = quality;
        rank = quality.resolutionRank;
      }
    }
    return best;
  }
}
