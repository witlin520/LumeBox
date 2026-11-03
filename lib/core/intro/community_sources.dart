import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'intro_models.dart';

class CommunitySegments {
  CommunitySegments({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, DateTime> _backoff = {};
  void close() => _client.close();
  Future<List<SkipSegment>> lookup(
    String provider,
    EpisodeIdentity identity,
    int durationMs,
    IntroCancellation token,
  ) async {
    token.check();
    if (_backoff[provider]?.isAfter(DateTime.now()) ?? false) return [];
    final query = <String, String>{};
    late Uri uri;
    if (provider == 'theIntroDB') {
      if (identity.tmdb == null) return [];
      query.addAll({
        'tmdb_id': '${identity.tmdb}',
        'duration_ms': '$durationMs',
        'details': 'true',
      });
      if (!identity.movie) {
        query.addAll({
          'season': '${identity.season}',
          'episode': '${identity.episode}',
        });
      }
      // Verified against the provider's current OpenAPI, v4 /media.
      uri = Uri.https('api.theintrodb.org', '/v4/media', query);
    } else {
      if (!RegExp(r'^tt\d{7,9}$').hasMatch(identity.imdb ?? '')) return [];
      query['imdb_id'] = identity.imdb!;
      if (identity.movie) {
        query['is_movie'] = 'true';
      } else {
        query.addAll({
          'season': '${identity.season}',
          'episode': '${identity.episode}',
        });
      }
      uri = Uri.https('api.introdb.app', '/segments', query);
    }
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'application/json';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 6));
    token.check();
    if (response.statusCode == 429) {
      _backoff[provider] = DateTime.now().add(
        Duration(
          seconds: (int.tryParse(response.headers['retry-after'] ?? '') ?? 300)
              .clamp(30, 3600),
        ),
      );
      await response.stream.drain<void>();
      throw StateError('$provider 请求限流，稍后重试');
    }
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return [];
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw StateError('$provider HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 6),
    )) {
      token.check();
      bytes.addAll(chunk);
      if (bytes.length > 512 * 1024) {
        throw StateError('Community response too large');
      }
    }
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map) throw const FormatException('Expected segment object');
    final remoteDuration = body['group_duration_ms'];
    // APIs may fall back to a different release. Reject rather than seek blindly.
    if (remoteDuration is num && (remoteDuration - durationMs).abs() > 2000) {
      throw StateError('社区库版本时长与当前视频不符');
    }
    final result = <SkipSegment>[];
    for (final entry in {
      'intro': SegmentKind.opening,
      'recap': SegmentKind.recap,
      'credits': SegmentKind.ending,
      'outro': SegmentKind.ending,
      'preview': SegmentKind.preview,
    }.entries) {
      final data = body[entry.key];
      for (final item in data is List ? data : [if (data is Map) data]) {
        if (item is! Map) continue;
        final rawStart =
            item['start_ms'] ??
            (item['start_sec'] is num ? (item['start_sec'] as num) * 1000 : 0);
        final rawEnd =
            item['end_ms'] ??
            (item['end_sec'] is num
                ? (item['end_sec'] as num) * 1000
                : durationMs);
        if (rawStart is! num || rawEnd is! num) continue;
        final segment = SkipSegment(
          kind: entry.value,
          startMs: rawStart.round(),
          endMs: rawEnd.round(),
          confidence: (item['confidence'] as num?)?.toDouble() ?? .8,
          source: provider,
          evidence:
              'community submissions: ${item['submission_count'] ?? "unknown"}',
        );
        if (segment.validFor(durationMs)) result.add(segment);
      }
    }
    return result;
  }
}
