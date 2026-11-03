import 'dart:convert';

import 'package:http/http.dart' as http;

/// Bangumi API 调用失败（带可读原因，不包含令牌）。
class BangumiException implements Exception {
  const BangumiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BangumiUser {
  const BangumiUser({
    required this.id,
    required this.username,
    required this.nickname,
  });

  final int id;
  final String username, nickname;

  String get displayName => nickname.trim().isNotEmpty ? nickname : username;

  factory BangumiUser.fromJson(Map<String, dynamic> data) => BangumiUser(
    id: (data['id'] as num?)?.toInt() ?? 0,
    username: '${data['username'] ?? ''}',
    nickname: '${data['nickname'] ?? ''}',
  );
}

class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.date,
    required this.image,
  });

  final int id;
  final String name, nameCn, date, image;

  String get displayName => nameCn.trim().isNotEmpty ? nameCn : name;

  factory BangumiSubject.fromJson(Map<String, dynamic> data) {
    final images = data['images'];
    return BangumiSubject(
      id: (data['id'] as num?)?.toInt() ?? 0,
      name: '${data['name'] ?? ''}',
      nameCn: '${data['name_cn'] ?? ''}',
      date: '${data['date'] ?? ''}',
      image: images is Map
          ? '${images['large'] ?? images['common'] ?? images['medium'] ?? ''}'
          : '',
    );
  }
}

class BangumiEpisode {
  const BangumiEpisode({
    required this.id,
    required this.sort,
    required this.name,
    required this.nameCn,
  });

  final int id;
  final double sort;
  final String name, nameCn;

  factory BangumiEpisode.fromJson(Map<String, dynamic> data) => BangumiEpisode(
    id: (data['id'] as num?)?.toInt() ?? 0,
    sort: (data['sort'] as num?)?.toDouble() ?? 0,
    name: '${data['name'] ?? ''}',
    nameCn: '${data['name_cn'] ?? ''}',
  );
}

/// Bangumi v0 API 的最小客户端：账号、搜索、章节与收藏进度。
///
/// 令牌只放在 Authorization 头里，不写日志、不拼进 URL；跟随重定向会把令牌
/// 送到别的主机，因此这里明确关闭重定向并把 3xx 当作失败。
class BangumiClient {
  BangumiClient(this.token, {http.Client? client})
    : client = client ?? http.Client();

  final String token;
  final http.Client client;

  static const String host = 'api.bgm.tv';

  void close() => client.close();

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer $token',
    'User-Agent': 'LumeBox/1.0',
    'Accept': 'application/json',
  };

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, Uri.https(host, path, query))
      ..followRedirects = false
      ..headers.addAll(_headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final text = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = '';
      try {
        final data = jsonDecode(text);
        if (data is Map) {
          detail = '${data['title'] ?? data['description'] ?? ''}'.trim();
        }
      } catch (_) {
        // 错误体不是 JSON 时只报状态码。
      }
      throw BangumiException(
        'Bangumi 返回 ${response.statusCode}${detail.isEmpty ? '' : '：$detail'}',
      );
    }
    if (text.trim().isEmpty) return <String, dynamic>{};
    final data = jsonDecode(text);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<BangumiUser> me() async {
    return BangumiUser.fromJson(await _request('GET', '/v0/me'));
  }

  /// 搜索番剧（type 2）。标题匹配由用户确认，不自动绑定。
  Future<List<BangumiSubject>> search(String keyword, {int type = 2}) async {
    final data = await _request(
      'POST',
      '/v0/search/subjects',
      body: {
        'keyword': keyword.trim(),
        'filter': {
          'type': [type],
        },
      },
    );
    final list = data['data'];
    return [
      for (final item in list is List ? list : const <Object?>[])
        if (item is Map<String, dynamic>) BangumiSubject.fromJson(item),
    ];
  }

  /// 拉取按 sort 排序的全部正片章节（分页上限 100）。
  Future<List<BangumiEpisode>> episodes(int subjectId) async {
    final all = <BangumiEpisode>[];
    var offset = 0;
    while (true) {
      final data = await _request(
        'GET',
        '/v0/episodes',
        query: {
          'subject_id': '$subjectId',
          'type': '0',
          'limit': '100',
          'offset': '$offset',
        },
      );
      final list = data['data'];
      if (list is! List || list.isEmpty) break;
      all.addAll([
        for (final item in list)
          if (item is Map<String, dynamic>) BangumiEpisode.fromJson(item),
      ]);
      if (list.length < 100) break;
      offset += list.length;
      if (offset > 5000) break;
    }
    all.sort((a, b) => a.sort.compareTo(b.sort));
    return all;
  }

  /// 收藏类型：1 想看 / 2 看过 / 3 在看 / 4 搁置 / 5 抛弃。
  Future<void> updateCollection(int subjectId, int type) async {
    await _request(
      'POST',
      '/v0/users/-/collections/$subjectId',
      body: {'type': type},
    );
  }

  /// 把章节标记为看过（type 2）。重复提交是幂等的。
  Future<void> markEpisodes(int subjectId, List<int> episodeIds) async {
    if (episodeIds.isEmpty) return;
    await _request(
      'POST',
      '/v0/users/-/collections/$subjectId/episodes',
      body: {'episode_id': episodeIds, 'type': 2},
    );
  }
}
