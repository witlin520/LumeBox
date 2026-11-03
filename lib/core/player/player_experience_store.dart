import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../reading/reading.dart';
import '../session/section.dart';
import 'player_experience.dart';
export 'player_experience.dart';

class PlayerExperienceStore extends ValueNotifier<PlayerExperience> {
  PlayerExperienceStore._(this.library)
    : super(PlayerExperience.decode(library.setting(key)));
  static const key = 'video.player.reference.experience.v1';
  static final _stores = Expando<PlayerExperienceStore>();
  final ReadingLibrary library;
  static PlayerExperienceStore forLibrary(ReadingLibrary library) =>
      _stores[library] ??= PlayerExperienceStore._(library);
  static Future<PlayerExperienceStore> open() async =>
      forLibrary(await ReadingLibrary.open(Section.video));
  static PlayerExperience get current {
    final library = ReadingLibrary.find(Section.video);
    return library == null
        ? const PlayerExperience()
        : forLibrary(library).value;
  }

  void update(Map<String, Object?> patch) {
    final next = value.update(patch);
    library.setSetting(key, jsonEncode(next.toJson()));
    value = next;
  }

  double? brightnessFor(String sourceId, String itemId) {
    final key =
        'video.player.reference.brightness.${jsonEncode([sourceId, itemId])}';
    final value = double.tryParse(library.setting(key) ?? '');
    return value != null && value.isFinite ? value.clamp(0.05, 1.0) : null;
  }

  void saveBrightness(String sourceId, String itemId, double brightness) {
    if (!value.rememberBrightness) return;
    library.setSetting(
      'video.player.reference.brightness.${jsonEncode([sourceId, itemId])}',
      brightness.clamp(0.05, 1.0).toString(),
    );
  }
}
