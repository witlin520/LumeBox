import 'dart:math' as math;

import 'intro_models.dart';
import 'intro_signals.dart';

class MetadataSegments {
  static SegmentKind? kind(String text) {
    final value = text.toLowerCase();
    if (RegExp(r'\b(recap|previously|prev)\b|前情|回顾').hasMatch(value)) {
      return SegmentKind.recap;
    }
    if (RegExp(r'\b(op\d*|opening|intro)\b|片头|オープニング').hasMatch(value)) {
      return SegmentKind.opening;
    }
    if (RegExp(r'\b(ed\d*|ending|credits|outro)\b|片尾|演职员|エンディング')
        .hasMatch(value)) {
      return SegmentKind.ending;
    }
    if (RegExp(r'\b(preview|next episode)\b|下集预告').hasMatch(value)) {
      return SegmentKind.preview;
    }
    return null;
  }

  static List<SkipSegment> detect(
    Map<String, Object?> metadata,
    int duration,
    IntroOptions options,
  ) {
    final result = <SkipSegment>[];
    for (final category in ['chapters', 'mkvTags', 'subtitles', 'filename']) {
      if (!options.enabled(category)) continue;
      final records = metadata[category];
      if (records is! List) continue;
      final sorted = records.whereType<Map>().toList()
        ..sort(
          (a, b) => ((a['startMs'] as num?) ?? 0).compareTo(
            (b['startMs'] as num?) ?? 0,
          ),
        );
      for (var i = 0; i < sorted.length; i++) {
        final record = sorted[i];
        final type = kind('${record['title'] ?? ''}');
        if (type == null) continue;
        // A filename keyword alone never establishes a timestamp. Only an
        // explicit timed filename marker, e.g. OP[00:05-01:35], is actionable.
        final start = record['startMs'],
            end =
                record['endMs'] ??
                (i + 1 < sorted.length ? sorted[i + 1]['startMs'] : duration);
        if (start is! num || end is! num) continue;
        final segment = SkipSegment(
          kind: type,
          startMs: start.round(),
          endMs: end.round(),
          confidence: category == 'chapters' || category == 'mkvTags'
              ? .97
              : .88,
          source: category,
          evidence: '${record['title']}',
        );
        final span = segment.endMs - segment.startMs;
        if (type == SegmentKind.opening && span > 300000 ||
            type == SegmentKind.recap && span > 480000 ||
            type == SegmentKind.ending && span > 900000) {
          continue;
        }
        if (segment.validFor(duration)) result.add(segment);
      }
    }
    return result;
  }

  static List<Map<String, Object?>> timedFilename(String name) {
    final result = <Map<String, Object?>>[];
    final regex = RegExp(
      r'(OP|Opening|ED|Credits|Prev|Recap|Intro|Outro)\s*[\[(](\d{1,2}:\d{2}(?::\d{2})?)[\s-]+(\d{1,2}:\d{2}(?::\d{2})?)[\])]',
      caseSensitive: false,
    );
    int time(String text) =>
        text.split(':').fold(0, (n, part) => n * 60 + int.parse(part)) * 1000;
    for (final match in regex.allMatches(name)) {
      result.add({
        'title': match[1],
        'startMs': time(match[2]!),
        'endMs': time(match[3]!),
      });
    }
    return result;
  }
}

class FingerprintSegments {
  static List<SkipSegment> match(
    List<Map<String, Object?>> frames,
    List<Map<String, Object?>> histories,
    int duration,
    IntroOptions options,
  ) {
    if (frames.length < 5) return [];
    for (final history in histories) {
      final refs = (history['frames'] as List? ?? []).whereType<Map>().toList();
      final segments = (history['segments'] as List? ?? [])
          .map(SkipSegment.parse)
          .whereType<SkipSegment>();
      for (final segment in segments) {
        final inside = refs
            .where(
              (r) =>
                  (r['at'] as num) >= segment.startMs &&
                  (r['at'] as num) < segment.endMs,
            )
            .toList();
        if (inside.length < 5) continue;
        final methods = <String, Map<int, Map<int, double>>>{};
        for (final candidate in frames) {
          for (final ref in inside) {
            final scores = <String, double>{};
            double? visual;
            for (final hash in ['p', 'd']) {
              if (!options.enabled(hash == 'p' ? 'phash' : 'dhash') &&
                  !(hash == 'p' && options.enabled('joint'))) {
                continue;
              }
              if (candidate[hash] is String && ref[hash] is String) {
                final similarity =
                    1 -
                    IntroSignals.hamming(
                          candidate[hash] as String,
                          ref[hash] as String,
                        ) /
                        64;
                visual = math.max(visual ?? 0, similarity);
                if (options.enabled(hash == 'p' ? 'phash' : 'dhash')) {
                  scores[hash == 'p' ? 'phash' : 'dhash'] = similarity;
                }
              }
            }
            double? audio;
            if (options.enabled('mfcc') || options.enabled('joint')) {
              final a = (candidate['m'] as List? ?? [])
                  .whereType<num>()
                  .map((n) => n.toDouble())
                  .toList();
              final b = (ref['m'] as List? ?? [])
                  .whereType<num>()
                  .map((n) => n.toDouble())
                  .toList();
              if (a.isNotEmpty && b.isNotEmpty) {
                audio = IntroSignals.cosine(a, b);
              }
              if (audio != null && options.enabled('mfcc')) {
                scores['mfcc'] = audio;
              }
            }
            if (options.enabled('joint') && visual != null && audio != null) {
              scores['joint'] = math.min(visual, audio);
            }
            final offset =
                (((candidate['at'] as num) - (ref['at'] as num)) / 1000)
                    .round();
            for (final score in scores.entries) {
              if (score.value < .92) continue;
              methods
                      .putIfAbsent(score.key, () => {})
                      .putIfAbsent(offset, () => {})[(candidate['at'] as num)
                      .round()] =
                  score.value;
            }
          }
        }
        final matches = <SkipSegment>[];
        for (final method in methods.entries) {
          final offsets = method.value;
          if (offsets.isEmpty) continue;
          final best = offsets.entries.reduce(
            (a, b) => a.value.length >= b.value.length ? a : b,
          );
          // Require a temporally consistent run covering most reference samples.
          if (best.value.length < math.max(5, (inside.length * .75).ceil())) {
            continue;
          }
          final start = segment.startMs + best.key * 1000,
              end = segment.endMs + best.key * 1000;
          final match = SkipSegment(
            kind: segment.kind,
            startMs: start,
            endMs: end,
            confidence:
                best.value.values.reduce((a, b) => a + b) / best.value.length,
            source: 'fingerprint.${method.key}',
            evidence:
                '${best.value.length}/${inside.length} aligned samples; offset ${best.key}s',
          );
          if (match.validFor(duration)) matches.add(match);
        }
        if (matches.isNotEmpty) return matches;
      }
    }
    return [];
  }
}

class HeuristicSegments {
  static List<SkipSegment> detect(
    List<IntroSample> samples,
    int duration,
    IntroOptions options,
  ) {
    final candidates = <SkipSegment>[];
    final boundaries = <int>[];
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (sample.gray.length != 1024) continue;
      final luma = sample.gray.fold(0, (a, b) => a + b) / 1024 / 255;
      final black = options.enabled('black') && luma < .025;
      final silent =
          options.enabled('silence') &&
          sample.pcm.isNotEmpty &&
          IntroSignals.rms(sample.pcm) < .003;
      var fade = false, cut = false;
      if (i > 0 &&
          samples[i - 1].gray.length == 1024 &&
          sample.atMs - samples[i - 1].atMs < 12000) {
        final previous = samples[i - 1].gray;
        final lastLuma = previous.fold(0, (a, b) => a + b) / 1024 / 255;
        fade =
            options.enabled('black') &&
            math.min(luma, lastLuma) < .05 &&
            (luma - lastLuma).abs() > .15;
        cut =
            options.enabled('sceneCuts') &&
            IntroSignals.hamming(
                  IntroSignals.dHash(previous),
                  IntroSignals.dHash(sample.gray),
                ) >
                25;
      }
      if ((black && silent) || (fade && silent) || (black && cut)) {
        boundaries.add(sample.atMs);
      }
      if (options.enabled('ocr') &&
          sample.atMs > duration * .65 &&
          sample.text.isNotEmpty) {
        final credit = RegExp(
          r'导演|演员|出演|制作|监制|配音|摄影|作曲|出品|cast|director|producer|starring|credits',
          caseSensitive: false,
        ).hasMatch(sample.text);
        // A second text observation moving upwards is evidence of rolling credits.
        final prior = i > 0 ? samples[i - 1] : null;
        final legacyScrolling =
            prior != null &&
            prior.textY != null &&
            sample.textY != null &&
            sample.textY! < prior.textY! - .015 &&
            sample.atMs - prior.atMs < 12000;
        final lineScrolling =
            prior != null &&
            sample.lines.any(
              (line) => prior.lines.any(
                (old) =>
                    line['text'] == old['text'] &&
                    '${line['text']}'.trim().length >= 4 &&
                    line['y'] is num &&
                    old['y'] is num &&
                    (line['y'] as num) < (old['y'] as num) - .015,
              ),
            );
        final scrolling =
            lineScrolling || (sample.lines.isEmpty && legacyScrolling);
        if (credit && scrolling) {
          candidates.add(
            SkipSegment(
              kind: SegmentKind.ending,
              startMs: prior.atMs,
              endMs: duration,
              confidence: .88,
              source: 'heuristic.ocr',
              evidence: 'credit keywords + upward text motion',
            ),
          );
        }
      }
    }
    // Black or silence alone is never enough to skip narrative scenes.
    for (var i = 0; i + 1 < boundaries.length; i++) {
      final start = boundaries[i], end = boundaries[i + 1];
      final span = end - start;
      if (start < duration * .2 && span >= 25000 && span <= 150000) {
        final within = samples
            .where((s) => s.atMs >= start && s.atMs <= end)
            .toList();
        var cuts = 0;
        for (var n = 1; n < within.length; n++) {
          if (within[n - 1].gray.length == 1024 &&
              within[n].gray.length == 1024 &&
              IntroSignals.hamming(
                    IntroSignals.dHash(within[n - 1].gray),
                    IntroSignals.dHash(within[n].gray),
                  ) >
                  25) {
            cuts++;
          }
        }
        if (options.enabled('sceneCuts') && cuts >= 4) {
          candidates.add(
            SkipSegment(
              kind: SegmentKind.opening,
              startMs: start,
              endMs: end,
              confidence: .86,
              source: 'heuristic.combined',
              evidence:
                  'paired black/fade + silence boundaries, $cuts sampled cuts',
            ),
          );
        }
      }
    }
    return candidates;
  }
}

class AiSegments {
  static List<SkipSegment> classify(
    List<IntroSample> samples,
    int duration,
    IntroOptions options,
  ) {
    if (!options.enabled('videoAI')) return [];
    final result = <SkipSegment>[];
    for (final kind in [
      SegmentKind.recap,
      SegmentKind.opening,
      SegmentKind.ending,
    ]) {
      final runs = <List<IntroSample>>[];
      for (final sample in samples) {
        final video = sample.ai[kind.name] ?? 0;
        final music = sample.ai['music'] ?? 0;
        final speech = sample.ai['speech'] ?? 0;
        final inRegion = kind == SegmentKind.ending
            ? sample.atMs > duration * .6
            : sample.atMs < math.min(duration * .3, 480000);
        final audioSupports =
            !options.enabled('audioAI') ||
            kind == SegmentKind.recap ||
            (music > .45 && music > speech);
        if (video < options.threshold || !inRegion || !audioSupports) continue;
        if (runs.isEmpty ||
            sample.atMs - runs.last.last.atMs >
                options.sampleEverySeconds * 2000) {
          runs.add([]);
        }
        runs.last.add(sample);
      }
      for (final run in runs.where((r) => r.length >= 4)) {
        final start = run.first.atMs,
            end = math.min(
              duration,
              run.last.atMs + options.sampleEverySeconds * 1000,
            );
        if (end - start < 12000) continue;
        result.add(
          SkipSegment(
            kind: kind,
            startMs: start,
            endMs: end,
            confidence:
                run.map((s) => s.ai[kind.name]!).reduce((a, b) => a + b) /
                run.length,
            source: 'ai.mobileclip',
            evidence:
                'consecutive zero-shot frames${options.enabled('audioAI') ? ' + YAMNet audio' : ''}; experimental uncalibrated score',
          ),
        );
      }
    }
    return result;
  }
}
