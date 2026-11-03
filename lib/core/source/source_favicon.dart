import 'dart:collection';

import '../net/lume_net.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;
import 'package:html/parser.dart' as html_parser;

import '../net/lume_http.dart';
import '../net/source_request_log.dart';
import '../net/waf.dart';
import '../session/section.dart';
import '../util/lume_log.dart';

/// 源图标解析：把「这个源没有图标」这件事在应用层补上。
///
/// 为什么不在控件里直接 `Image.network('${origin}/favicon.ico')`：
/// 1. **图标常常不在 /favicon.ico**：真机里一片首字母占位的根因就是这个——
///    实测多个源在 /favicon.ico 上回的是 HTML（站点的 404 页）或 404，
///    真正的图标写在首页的 `<link rel="icon">` / `apple-touch-icon` 里；
/// 2. **裸请求会被挡**：`Image.network` 不带 UA / Cookie，Cloudflare 站直接 403，
///    而该源的会话（`cf_clearance` 与验证时的 UA）就在库里，白放着不用；
/// 3. **列表会反复打同一个站**：源列表一次渲染几十项，每项一个请求会重复拉同一个
///    域名，必须去重 + 缓存。
///
/// 因此先尝试源声明图标（未声明时试 /favicon.ico），失效后马上解析首页的
/// icon / logo，再回退其他约定路径，避免每个站等完多个无效路径。图标取字节
/// （经全局网络队列，带该源会话）→ 校验**确实是图片**（SVG 转为静态 PNG）
/// → 缓存成功结果。取不到就老实回退首字母，绝不假装有图标。
class SourceFavicon {
  SourceFavicon({
    LumeHttp? http,
    this.maxEntries = 512,
    this.cacheDirectory,
    this.fetchHtmlHomepage = true,
    this.failureRetryAfter = const Duration(minutes: 2),
    DateTime Function()? now,
    // Public parameter keeps the existing test/client injection API.
    // ignore: prefer_initializing_formals
  }) : _http = http,
       _now = now ?? DateTime.now;

  /// 应用级单例：列表页与设置页共用一份缓存，同一个源只请求一次。
  static final SourceFavicon instance = SourceFavicon(
    cacheDirectory: () async => Directory(
      '${(await getApplicationSupportDirectory()).path}/source-icons-v3',
    ),
  );
  final Future<Directory> Function()? cacheDirectory;

  /// 单张图标的读取上限（图标不该超过这个量级）。
  static const int maxBytes = 256 * 1024;

  /// 单次请求超时：图标是锦上添花，不该拖慢列表。取 5 秒（队列内部还有重试，
  /// 真连不上的站点最多也就耗一个 5 秒 × 重试次数，不会长时间占着后台）。
  static const Duration timeout = Duration(seconds: 5);

  final LumeHttp? _http;
  Future<LumeHttpResponse> _request({
    required String url,
    required Map<String, String> headers,
    Duration? timeout,
    int? maxBytes,
  }) async {
    final client = _http ?? LumeHttp(settings: LumeNet.settings, source: '源图标');
    try {
      return await client.send(
        url: url,
        headers: headers,
        timeout: timeout,
        maxBytes: maxBytes,
      );
    } finally {
      if (_http == null) client.dispose();
    }
  }

  int _activeResolutions = 0;
  final _waitingResolutions = Queue<Completer<void>>();
  static Future<Map<String, dynamic>>? _bundledIndex;

  static Future<({Uint8List bytes, bool label})?> _bundled(String? id) async {
    if (id == null) return null;
    try {
      final index = await (_bundledIndex ??= rootBundle
          .loadString('assets/source_icons/index.json')
          .then((text) => Map<String, dynamic>.from(jsonDecode(text) as Map)));
      final entry = index[id];
      if (entry is! Map) return null;
      if (entry['kind'] == 'label') {
        final labels = (entry['labels'] as List)
            .whereType<String>()
            .take(2)
            .toList();
        return (bytes: await _labelPng(labels, sourceId: id), label: true);
      }
      final file = '${entry['file']}';
      if (!RegExp(r'^[a-z0-9_-]+\.(png|svg)$').hasMatch(file)) return null;
      final data = await rootBundle.load('assets/source_icons/$file');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      var png = file.endsWith('.svg') ? await _svgPng(bytes) : bytes;
      final backdrop = entry['background'];
      if (png != null && backdrop is int) {
        final logo = img.decodePng(png);
        if (logo != null) {
          final tile = img.Image(width: logo.width, height: logo.height);
          img.fill(
            tile,
            color: img.ColorRgb8(
              (backdrop >> 16) & 255,
              (backdrop >> 8) & 255,
              backdrop & 255,
            ),
          );
          img.compositeImage(tile, logo);
          png = img.encodePng(tile);
        }
      }
      return png == null ? null : (bytes: png, label: entry['kind'] == 'label');
    } catch (_) {
      return null;
    }
  }

  /// First paint is independent of slow or unavailable websites.
  Future<Uint8List?> bundledFallback(String? sourceId) async =>
      (await _bundled(sourceId))?.bytes;

  static Uint8List? storedIcon(Uint8List bytes) {
    try {
      return _asImage(bytes, null);
    } catch (_) {
      return null;
    }
  }

  // A local source label is deliberately distinct from an acquired site logo.
  // Draw text with the platform font so Chinese labels work on iOS as well.
  static Future<Uint8List> _labelPng(
    List<String> labels, {
    required String sourceId,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const palette = [
      0xFF6A52E5,
      0xFF1769AA,
      0xFFBC4366,
      0xFF087F80,
      0xFFAD531F,
      0xFF4457A5,
    ];
    final seed = labels.join().runes.fold<int>(0, (sum, rune) => sum + rune);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(0, 0, 192, 192),
        const ui.Radius.circular(38),
      ),
      ui.Paint()..color = ui.Color(palette[seed % palette.length]),
    );
    // A video emblem remains recognisable at card size; the small name below
    // distinguishes sites which do not publish an image of their own.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(46, 26, 100, 76),
        const ui.Radius.circular(18),
      ),
      ui.Paint()..color = const ui.Color(0x33FFFFFF),
    );
    final play = ui.Path()
      ..moveTo(84, 44)
      ..lineTo(84, 84)
      ..lineTo(116, 64)
      ..close();
    if (sourceId.endsWith('_comic')) {
      final ink = ui.Paint()
        ..color = const ui.Color(0xFFFFFFFF)
        ..strokeWidth = 5;
      canvas.drawLine(const ui.Offset(96, 38), const ui.Offset(96, 90), ink);
      canvas.drawLine(const ui.Offset(60, 50), const ui.Offset(82, 50), ink);
      canvas.drawLine(const ui.Offset(110, 50), const ui.Offset(132, 50), ink);
    } else {
      canvas.drawPath(play, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    }
    for (var i = 0; i < labels.length; i++) {
      final paragraph =
          (ui.ParagraphBuilder(
                  ui.ParagraphStyle(
                    textAlign: ui.TextAlign.center,
                    fontSize: labels[i].length > 4 ? 24 : 30,
                    fontWeight: ui.FontWeight.w700,
                  ),
                )
                ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
                ..addText(labels[i]))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 192));
      canvas.drawParagraph(
        paragraph,
        ui.Offset(0, labels.length == 1 ? 122 : 110.0 + i * 34),
      );
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(192, 192);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  Future<Uint8List?> _resolveBounded({
    required String origin,
    required List<String> explicit,
    Section? section,
    String? sourceId,
    bool bestQuality = false,
  }) async {
    final bundled = await _bundled(sourceId);
    if (!bestQuality && explicit.isEmpty && bundled?.label == false) {
      return bundled!.bytes;
    }
    if (_activeResolutions >= 2) {
      final ready = Completer<void>();
      if (bestQuality) {
        _waitingResolutions.addFirst(ready);
      } else {
        _waitingResolutions.add(ready);
      }
      await ready.future;
    } else {
      _activeResolutions++;
    }
    try {
      if (bestQuality) {
        return await _resolveBest(
              origin: origin,
              explicit: explicit,
              section: section,
              sourceId: sourceId,
              baseline: bundled?.label == false && explicit.isEmpty
                  ? bundled?.bytes
                  : null,
              ignoreCache: bundled?.label == true,
            ) ??
            bundled?.bytes;
      }
      return await _resolve(
            origin: origin,
            explicit: explicit,
            section: section,
            sourceId: sourceId,
          ) ??
          bundled?.bytes;
    } finally {
      if (_waitingResolutions.isNotEmpty) {
        _waitingResolutions.removeFirst().complete();
      } else {
        _activeResolutions--;
      }
    }
  }

  static Uint8List? _decodeIcon(({Uint8List bytes, String? type}) input) =>
      _asImage(input.bytes, input.type);

  /// 内存缓存上限；成功图标另存磁盘，避免重启后逐站重新抓取。
  final int maxEntries;

  /// 候选全挂时要不要再抓一次首页解析图标地址。
  final bool fetchHtmlHomepage;
  final Duration failureRetryAfter;
  final DateTime Function() _now;
  final Map<String, DateTime> _failedUntil = {};

  final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  int _cacheGeneration = 0;
  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};
  final Map<String, Future<Uint8List?>> _bestInflight = {};

  /// 主动获取时比较真实像素；列表自动加载仍走快速缓存，避免逐卡扫描网站。
  Future<Uint8List?> loadBest({
    required String origin,
    List<String> explicit = const [],
    Section? section,
    String? sourceId,
  }) {
    final key = _key(origin, explicit).isEmpty && sourceId != null
        ? 'source:$sourceId'
        : _key(origin, explicit);
    if (key.isEmpty) return Future.value();
    final running = _bestInflight[key];
    if (running != null) return running;
    final generation = _cacheGeneration;
    final task =
        () async {
          // 快速请求先结束，避免其稍后把高清缓存覆盖成小图。
          final pending = _inflight[key];
          if (pending != null) {
            try {
              await pending;
            } catch (_) {}
          }
          final bytes = await _resolveBounded(
            origin: origin,
            explicit: explicit,
            section: section,
            sourceId: sourceId,
            bestQuality: true,
          );
          final fallback = await _bundled(sourceId);
          final placeholder =
              fallback?.label == true && listEquals(bytes, fallback?.bytes);
          if (bytes != null && !placeholder && generation == _cacheGeneration) {
            _remember(key, bytes);
            try {
              final directory = await cacheDirectory?.call();
              if (directory != null && generation == _cacheGeneration) {
                await directory.create(recursive: true);
                if (generation == _cacheGeneration) {
                  File(
                    '${directory.path}/${sha256.convert(utf8.encode(key))}.png',
                  ).writeAsBytesSync(bytes, flush: true);
                }
              }
            } catch (_) {
              /* 缓存失败不影响本次预览。 */
            }
          }
          return bytes;
        }().whenComplete(() {
          _bestInflight.remove(key);
        });
    _bestInflight[key] = task;
    return task;
  }

  /// 取图标字节；拿不到返回 null（调用方回退首字母占位）。
  ///
  /// [origin] 是站点根（`https://a.com`）；[explicit] 是源自己声明的图标地址，
  /// 优先级最高。同一个 (origin, explicit) 组合只真正请求一次，成功结果
  /// 缓存住，失败短暂冷却后允许重新获取，避免列表重建反复请求离线站点。
  Future<Uint8List?> load({
    required String origin,
    List<String> explicit = const <String>[],
    Section? section,
    String? sourceId,
  }) {
    final key = _key(origin, explicit).isEmpty && sourceId != null
        ? 'source:$sourceId'
        : _key(origin, explicit);
    if (key.isEmpty) return Future<Uint8List?>.value();
    if (_cache.containsKey(key)) {
      return Future<Uint8List?>.value(_cache[key]);
    }
    final bestRunning = _bestInflight[key];
    if (bestRunning != null) return bestRunning;
    final failedUntil = _failedUntil[key];
    if (failedUntil != null && _now().isBefore(failedUntil)) {
      return Future<Uint8List?>.value();
    }
    _failedUntil.remove(key);
    final running = _inflight[key];
    if (running != null) return running;
    final generation = _cacheGeneration;
    final task =
        _loadCachedOrResolve(
              key,
              origin: origin,
              explicit: explicit,
              section: section,
              sourceId: sourceId,
            )
            .then((bytes) async {
              final fallback = await _bundled(sourceId);
              final placeholder =
                  fallback?.label == true && listEquals(bytes, fallback?.bytes);
              if (generation == _cacheGeneration) {
                _remember(key, placeholder ? null : bytes);
              }
              return bytes;
            })
            .whenComplete(() {
              // 用块体而不是箭头：箭头写法会把 `Map.remove` 的返回值（就是这条 future
              // 本身）当成「还要等它」——自我等待，永远不完成。
              if (generation == _cacheGeneration) _inflight.remove(key);
            });
    _inflight[key] = task;
    return task;
  }

  Uint8List? cached({
    required String origin,
    List<String> explicit = const [],
  }) => _cache[_key(origin, explicit)];

  Future<Uint8List?> _loadCachedOrResolve(
    String key, {
    required String origin,
    required List<String> explicit,
    Section? section,
    String? sourceId,
  }) async {
    File? file;
    final generation = _cacheGeneration;
    try {
      final directory = await cacheDirectory?.call();
      if (directory != null) {
        file = File(
          '${directory.path}/${sha256.convert(utf8.encode(key))}.png',
        );
        if (await file.exists() &&
            _now().difference(await file.lastModified()) <
                const Duration(days: 14) &&
            await file.length() <= maxBytes) {
          final bytes = _asImage(await file.readAsBytes(), null);
          if (bytes != null) return bytes;
        }
      }
    } catch (_) {
      /* Cache failure must not prevent network resolution. */
    }
    final bytes = await _resolveBounded(
      origin: origin,
      explicit: explicit,
      section: section,
      sourceId: sourceId,
    );
    final fallback = await _bundled(sourceId);
    final placeholder =
        fallback?.label == true && listEquals(bytes, fallback?.bytes);
    if (bytes != null &&
        !placeholder &&
        file != null &&
        generation == _cacheGeneration) {
      try {
        await file.parent.create(recursive: true);
        if (generation == _cacheGeneration) {
          file.writeAsBytesSync(bytes, flush: true);
        }
      } catch (_) {
        /* Optional cache. */
      }
    }
    return bytes;
  }

  /// 测试用：清掉缓存与在飞表。
  @visibleForTesting
  void clearCache() {
    _cacheGeneration++;
    _cache.clear();
    _failedUntil.clear();
    _inflight.clear();
  }

  Future<int> clearDiskCache() async {
    clearCache();
    final directory = await cacheDirectory?.call();
    if (directory == null || !directory.existsSync()) return 0;
    var freed = 0;
    for (final file
        in directory.listSync(followLinks: false).whereType<File>()) {
      if (!RegExp(r'[/\\][0-9a-f]{64}\.png$').hasMatch(file.path)) continue;
      freed += file.lengthSync();
      file.deleteSync();
    }
    return freed;
  }

  void _remember(String key, Uint8List? bytes) {
    if (_cache.length >= maxEntries && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    if (bytes != null) {
      _cache[key] = bytes;
      _failedUntil.remove(key);
    } else {
      if (_failedUntil.length >= maxEntries) {
        _failedUntil.remove(_failedUntil.keys.first);
      }
      _failedUntil[key] = _now().add(failureRetryAfter);
    }
  }

  static String _key(String origin, List<String> explicit) {
    final icons = explicit
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final site = origin.trim();
    if (site.isEmpty && icons.isEmpty) return '';
    return '$site|${icons.join(',')}';
  }

  Future<Uint8List?> _resolve({
    required String origin,
    required List<String> explicit,
    Section? section,
    String? sourceId,
  }) async {
    var reachable = false;
    var triedHomepage = false;
    final candidates = _candidates(origin, explicit);
    final declaredCount = _candidates('', explicit).length;
    final fastCount = declaredCount == 0 ? 1 : declaredCount;
    for (final (index, url) in candidates.indexed) {
      final attempt = await _fetch(
        url,
        section: section,
        sourceId: sourceId,
        referer: origin.isEmpty ? '' : '$origin/',
      );
      if (attempt.bytes != null) return attempt.bytes;
      reachable = reachable || attempt.reachable;
      // 常规 favicon 失效后立即读网页声明，避免每个站先等完三个猜测路径。
      if (index + 1 == fastCount &&
          reachable &&
          fetchHtmlHomepage &&
          origin.isNotEmpty) {
        triedHomepage = true;
        final bytes = await _resolveHomepage(
          origin: origin,
          section: section,
          sourceId: sourceId,
        );
        if (bytes != null) return bytes;
      }
    }
    if (triedHomepage || !fetchHtmlHomepage || origin.isEmpty || !reachable) {
      return null;
    }
    return _resolveHomepage(
      origin: origin,
      section: section,
      sourceId: sourceId,
    );
  }

  Future<Uint8List?> _resolveHomepage({
    required String origin,
    Section? section,
    String? sourceId,
  }) async {
    final home = await _fetchText(
      '$origin/',
      section: section,
      sourceId: sourceId,
    );
    if (home == null) return null;
    for (final url in _htmlCandidates(home.text, home.url)) {
      final attempt = await _fetch(
        url,
        section: section,
        sourceId: sourceId,
        referer: home.url,
      );
      if (attempt.bytes != null) return attempt.bytes;
    }
    return null;
  }

  static int _pixelQuality(Uint8List bytes) {
    try {
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width * info.height > 4 * 1024 * 1024) {
        return 0;
      }
      return info.width < info.height ? info.width : info.height;
    } catch (_) {
      return 0;
    }
  }

  Future<Uint8List?> _resolveBest({
    required String origin,
    required List<String> explicit,
    Section? section,
    String? sourceId,
    Uint8List? baseline,
    bool ignoreCache = false,
  }) async {
    Uint8List? best =
        baseline ?? (ignoreCache ? null : _cache[_key(origin, explicit)]);
    var quality = best == null ? 0 : await compute(_pixelQuality, best);
    final candidates = <String>{};
    var referer = origin;
    final site = _originOf(origin);
    for (final value in explicit.take(4)) {
      final url = _absolute(value, site);
      if (_isUsableUrl(url)) candidates.add(url);
    }
    if (fetchHtmlHomepage && site.isNotEmpty) {
      final home = await _fetchText(
        '$site/',
        section: section,
        sourceId: sourceId,
      );
      if (home != null) {
        referer = home.url;
        final document = html_parser.parse(home.text);
        final base = document.querySelector('base[href]')?.attributes['href'];
        final htmlBase = base == null ? home.url : _absolute(base, home.url);
        final manifests = document
            .querySelectorAll('link[rel]')
            .where(
              (tag) => (tag.attributes['rel'] ?? '')
                  .toLowerCase()
                  .split(RegExp(r'\s+'))
                  .contains('manifest'),
            );
        for (final tag in manifests.take(2)) {
          final url = _absolute(tag.attributes['href'] ?? '', htmlBase);
          if (!_isUsableUrl(url)) continue;
          final manifest = await _fetchText(
            url,
            section: section,
            sourceId: sourceId,
          );
          try {
            final value = manifest == null ? null : jsonDecode(manifest.text);
            if (value is Map && value['icons'] is List) {
              final icons = (value['icons'] as List).whereType<Map>().toList()
                ..sort(
                  (a, b) =>
                      _declaredSize('${b['sizes'] ?? ''}') -
                      _declaredSize('${a['sizes'] ?? ''}'),
                );
              for (final icon in icons.take(4)) {
                final src = _absolute('${icon['src'] ?? ''}', manifest!.url);
                if (_isUsableUrl(src)) candidates.add(src);
              }
            }
          } catch (_) {
            /* manifest 失效时继续找网页和约定路径。 */
          }
        }
        candidates.addAll(_htmlCandidates(home.text, home.url).take(10));
      }
    }
    candidates.addAll(_candidates(origin, explicit));
    final deadline = _now().add(const Duration(seconds: 30));
    for (final url in candidates.take(16)) {
      if (_now().isAfter(deadline)) break;
      final attempt = await _fetch(
        url,
        section: section,
        sourceId: sourceId,
        referer: referer,
      );
      final bytes = attempt.bytes;
      if (bytes == null) continue;
      final score = await compute(_pixelQuality, bytes);
      if (score > quality) {
        best = bytes;
        quality = score;
      }
    }
    return quality > 0 ? best : null;
  }

  static int _declaredSize(String sizes) {
    var largest = 0;
    for (final pair in RegExp(
      r'(\d+)x(\d+)',
      caseSensitive: false,
    ).allMatches(sizes)) {
      final width = int.tryParse(pair[1]!) ?? 0,
          height = int.tryParse(pair[2]!) ?? 0;
      final side = width < height ? width : height;
      if (side > largest) largest = side;
    }
    return largest;
  }

  /// 快速候选：源声明在前，约定路径在后；主动获取另外比较实际像素。
  static List<String> _candidates(String origin, List<String> explicit) {
    final out = <String>[];
    for (final url in explicit) {
      final text = url.trim();
      final resolved = _absolute(text, _originOf(origin));
      if (_isUsableUrl(resolved)) out.add(resolved);
    }
    final site = _originOf(origin);
    if (site.isNotEmpty) {
      for (final path in const <String>[
        '/favicon.ico',
        '/favicon.png',
        '/apple-touch-icon.png',
        '/static/favicon.ico',
      ]) {
        out.add('$site$path');
      }
    }
    return out.toSet().toList(growable: false);
  }

  /// 站点根：`https://a.com/x` → `https://a.com`（带端口也照留）。
  static String _originOf(String siteUrl) {
    final uri = Uri.tryParse(siteUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    if (!const <String>{'http', 'https'}.contains(uri.scheme)) return '';
    return uri.userInfo.isEmpty ? uri.origin : '';
  }

  static bool _isUsableUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (!const <String>{'http', 'https'}.contains(uri.scheme)) return false;
    return true;
  }

  /// 从首页 HTML 里挑图标地址（纯函数，单独可验证）。
  ///
  /// 规则照着浏览器那一套来：`apple-touch-icon` 优先（几乎都是方正的 PNG），
  /// 其余 `rel=icon` 按 `sizes` 从大到小排；SVG 在下载后转为 PNG。
  @visibleForTesting
  static List<String> iconLinksFromHtml(String html, String origin) {
    final document = html_parser.parse(html);
    final baseHref = document.querySelector('base[href]')?.attributes['href'];
    final site = baseHref == null ? origin : _absolute(baseHref, origin);
    final found = <({String url, int size, int apple})>[];
    for (final tag in document.querySelectorAll('link[rel]')) {
      final rel = (tag.attributes['rel'] ?? '').toLowerCase();
      if (!rel
          .split(RegExp(r'\s+'))
          .any(
            (token) =>
                token == 'icon' ||
                token == 'apple-touch-icon' ||
                token == 'apple-touch-icon-precomposed',
          )) {
        continue;
      }
      final href = tag.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final url = _absolute(href, site);
      if (!_isUsableUrl(url)) continue;
      final sizes = tag.attributes['sizes'] ?? '';
      final side = _declaredSize(sizes);
      found.add((url: url, size: side, apple: rel.contains('apple') ? 1 : 0));
    }
    found.sort((a, b) {
      if (a.apple != b.apple) return b.apple - a.apple;
      return b.size - a.size;
    });
    final out = <String>[];
    for (final item in found) {
      if (!out.contains(item.url)) out.add(item.url);
    }
    return out;
  }

  static List<String> _htmlCandidates(String html, String home) {
    final icons = iconLinksFromHtml(html, home);
    final origin = Uri.parse(home).origin;
    // 迁站后页面可能还引用旧域名图标；先尝试声明地址，再尝试本站同路径。
    final local = <String>[
      for (final icon in icons)
        if (Uri.parse(icon).origin != origin)
          Uri.parse(origin).resolve(Uri.parse(icon).path).toString(),
    ];
    final document = html_parser.parse(html);
    final base = document.querySelector('base[href]')?.attributes['href'];
    final htmlBase = base == null ? home : _absolute(base, home);
    final logos = <String>[];
    // 只认明确的站点 logo，不把封面、广告或文章图片当图标。
    for (final tag in document.querySelectorAll(
      'img.logo, img[id*="logo"], img[class*="logo"], '
      '.logo img, .site-logo img, .logo-site img, header img[alt], '
      'img[src*="logo"], img[data-src*="logo"]',
    )) {
      final label =
          '${tag.attributes['alt'] ?? ''} ${tag.attributes['class'] ?? ''} ${tag.attributes['id'] ?? ''} ${tag.attributes['src'] ?? ''} ${tag.attributes['data-src'] ?? ''}';
      if (tag.parent?.classes.any((name) => name.contains('logo')) != true &&
          !label.toLowerCase().contains('logo')) {
        continue;
      }
      final url = _absolute(
        tag.attributes['src'] ?? tag.attributes['data-src'] ?? '',
        htmlBase,
      );
      if (_isUsableUrl(url)) logos.add(url);
    }
    return {...icons, ...local, ...logos.take(3)}.toList();
  }

  /// 在 UI isolate 光栅化一次；列表、持久设置和磁盘缓存仍统一读取 PNG。
  static Future<Uint8List?> _svgPng(Uint8List bytes) async {
    try {
      final text = utf8.decode(bytes);
      if (text.toUpperCase().contains('<!ENTITY')) return null;
      final document = XmlDocument.parse(text);
      if (document.rootElement.name.local != 'svg') return null;
      for (final element in document.descendants.whereType<XmlElement>()) {
        for (final attribute in element.attributes) {
          if (attribute.name.local == 'href' &&
              !attribute.value.trim().startsWith('#') &&
              !RegExp(
                r'^data:image/(?:png|jpeg|gif|webp);base64,',
                caseSensitive: false,
              ).hasMatch(attribute.value.trim())) {
            return null;
          }
        }
      }
      final info = await vg.loadPicture(SvgStringLoader(text), null);
      try {
        final size = info.size;
        if (!size.width.isFinite ||
            !size.height.isFinite ||
            size.width <= 0 ||
            size.height <= 0) {
          return null;
        }
        final scale =
            192 / (size.width > size.height ? size.width : size.height);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..scale(scale);
        canvas.drawPicture(info.picture);
        final picture = recorder.endRecording();
        try {
          final image = await picture.toImage(
            (size.width * scale).round().clamp(1, 192),
            (size.height * scale).round().clamp(1, 192),
          );
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            return png?.buffer.asUint8List(
              png.offsetInBytes,
              png.lengthInBytes,
            );
          } finally {
            image.dispose();
          }
        } finally {
          picture.dispose();
        }
      } finally {
        info.picture.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static String _absolute(String href, String site) {
    final text = href.trim();
    if (text.isEmpty) return '';
    final base = Uri.tryParse(site);
    final uri = Uri.tryParse(text);
    if (uri == null) return '';
    return base?.hasScheme == true ? base!.resolveUri(uri).toString() : text;
  }

  /// 取一张图；状态码不是 200、内容不是图片（或解不了的 SVG）都当作「没有」。
  ///
  /// 返回值带上「这条请求有没有真的到过服务器」：全都没到过就不必再抓首页了。
  Future<({Uint8List? bytes, bool reachable})> _fetch(
    String url, {
    Section? section,
    String? sourceId,
    String referer = '',
  }) async {
    try {
      final response = await _request(
        url: url,
        headers: _headers(
          url,
          section: section,
          sourceId: sourceId,
          referer: referer,
        ),
        timeout: timeout,
        maxBytes: maxBytes,
      );
      if (response.statusCode != 200) {
        return (bytes: null, reachable: true);
      }
      final type = response.headers['content-type'] ?? '';
      final prefix = utf8
          .decode(response.body.take(512).toList(), allowMalformed: true)
          .trimLeft();
      final svg =
          type.toLowerCase().contains('svg') ||
          prefix.startsWith('<svg') ||
          (prefix.startsWith('<?xml') && prefix.contains('<svg'));
      return (
        bytes: svg
            ? await _svgPng(response.body)
            : await compute(_decodeIcon, (bytes: response.body, type: type)),
        reachable: true,
      );
    } on Object catch (error) {
      // 图标取不到是常态（站点没有 / 被墙 / 被 WAF 挡），不值得打扰用户；
      // 但排查「某个源为什么没图标」时日志里要能看到试过哪个地址。
      LumeLog.info('[源图标] 取不到 $url：$error');
      return (bytes: null, reachable: false);
    }
  }

  /// 取首页 HTML（只为解析图标地址，读满上限即断）。
  Future<({String text, String url})?> _fetchText(
    String url, {
    Section? section,
    String? sourceId,
  }) async {
    try {
      final response = await _request(
        url: url,
        headers: _headers(
          url,
          section: section,
          sourceId: sourceId,
          referer: url,
        ),
        timeout: timeout,
        maxBytes: maxBytes,
      );
      if (response.statusCode != 200) return null;
      return (text: response.text, url: response.url ?? url);
    } on Object catch (error) {
      LumeLog.info('[源图标] 首页解析失败 $url：$error');
      return null;
    }
  }

  /// 请求头：源自己域名上的请求带上该源**验证过的会话**（Cookie + UA）。
  ///
  /// 只发给源站自己的域名（[SourceRequestLog.ownsHost] 记的地址），其他域名一枚
  /// 都不带——把源站凭据泄漏给第三方域名是更严重的问题。
  Map<String, String> _headers(
    String url, {
    Section? section,
    String? sourceId,
    String referer = '',
  }) {
    final headers = <String, String>{'Accept': 'image/*,*/*;q=0.8'};
    if (referer.isNotEmpty) headers['Referer'] = referer;
    if (section == null || sourceId == null) return headers;
    if (!SourceRequestLog.ownsHost(sourceId, url)) return headers;
    final cookies = WafSessions.cookiesFor(section, sourceId)?.trim() ?? '';
    if (cookies.isNotEmpty) headers['Cookie'] = cookies;
    final ua = WafSessions.userAgentFor(section, sourceId)?.trim() ?? '';
    if (ua.isNotEmpty) headers['User-Agent'] = ua;
    return headers;
  }

  /// 内容确实是能画的图片才算数：先看 content-type，再看字节魔数（有些站把
  /// PNG 当 `image/x-icon` 发，也有站把 HTML 404 页当图标发）。
  static Uint8List? _asImage(Uint8List bytes, String? contentType) {
    if (bytes.isEmpty) return null;
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('svg')) return null;
    if (type.startsWith('text/') ||
        type.contains('html') ||
        type.contains('json')) {
      return null;
    }
    if (!_looksLikeImage(bytes)) return null;
    // Flutter's codecs do not decode Windows ICO containers.
    if (_startsWith(bytes, const [0, 0, 1, 0])) {
      try {
        // ICO entries are alternative sizes, not animation frames. Encoding
        // decodeIco's full frame list as PNG produces APNG and a pulsing icon.
        final decoded = img.IcoDecoder().decodeImageLargest(bytes);
        return decoded == null
            ? null
            : _asImage(
                Uint8List.fromList(img.encodePng(decoded, singleFrame: true)),
                null,
              );
      } catch (_) {
        return null;
      }
    }
    // Site logos should stay still even when the original is GIF/APNG/WebP.
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info != null && info.width * info.height <= 4 * 1024 * 1024) {
      final frame = decoder!.decodeFrame(0);
      if (frame != null &&
          frame.hasAlpha &&
          !frame.any((pixel) => pixel.aNormalized > .03)) {
        return null;
      }
    }
    if (info != null && info.numFrames > 1) {
      try {
        final frame = decoder!.decodeFrame(0);
        return frame == null ? null : img.encodePng(frame, singleFrame: true);
      } catch (_) {
        return null;
      }
    }
    return bytes;
  }

  /// 图片魔数：PNG / JPEG / GIF / BMP / WEBP / ICO。
  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    const png = <int>[0x89, 0x50, 0x4E, 0x47];
    const jpeg = <int>[0xFF, 0xD8, 0xFF];
    const gif = <int>[0x47, 0x49, 0x46];
    const bmp = <int>[0x42, 0x4D];
    const ico = <int>[0x00, 0x00, 0x01, 0x00];
    for (final magic in const <List<int>>[png, jpeg, gif, bmp, ico]) {
      if (_startsWith(bytes, magic)) return true;
    }
    // WEBP：RIFF....WEBP
    if (bytes.length >= 12 &&
        _startsWith(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
