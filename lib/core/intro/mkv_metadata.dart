import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'intro_models.dart';

/// Bounded EBML reads: inspect SeekHead, then fetch only Chapters/Tags. Neither
/// a whole MKV download nor a second playing decoder is required.
class MkvMetadataProbe {
  static const chaptersId = 0x1043a770, tagsId = 0x1254c367;
  Future<Map<String, Object?>> inspect(
    Uri uri,
    Map<String, String> headers,
    IntroCancellation token,
  ) async {
    final client = http.Client();
    try {
      Future<Uint8List> read(int offset, int count) async {
        token.check();
        if (uri.scheme == 'file') {
          final file = await File.fromUri(uri).open();
          try {
            await file.setPosition(offset);
            return await file.read(count);
          } finally {
            await file.close();
          }
        }
        final request = http.Request('GET', uri)
          ..headers.addAll({
            ...headers,
            'Range': 'bytes=$offset-${offset + count - 1}',
            'Accept-Encoding': 'identity',
          });
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 206 &&
            !(offset == 0 && response.statusCode == 200)) {
          throw StateError('MKV range metadata is unavailable');
        }
        if (response.statusCode == 206 &&
            !(response.headers['content-range'] ?? '').startsWith(
              'bytes $offset-',
            )) {
          throw const FormatException('Wrong MKV byte range');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 5),
        )) {
          token.check();
          bytes.add(
            chunk.length + bytes.length <= count
                ? chunk
                : chunk.sublist(0, count - bytes.length),
          );
          if (bytes.length >= count) break;
        }
        return bytes.takeBytes();
      }

      final head = await read(0, 65536);
      final root = _elements(head, 0, head.length);
      final segment = root.where((e) => e.id == 0x18538067).firstOrNull;
      if (segment == null) return {};
      final children = _elements(head, segment.start, head.length);
      final blocks = <Uint8List>[];
      final fetched = <int>{};
      for (final child in children) {
        if (child.id == chaptersId || child.id == tagsId) {
          blocks.add(head.sublist(child.header, child.end));
        }
        if (child.id != 0x114d9b74) continue;
        for (final seek in _elements(
          head,
          child.start,
          child.end,
        ).where((e) => e.id == 0x4dbb)) {
          int? id, position;
          for (final entry in _elements(head, seek.start, seek.end)) {
            if (entry.id == 0x53ab) id = _uint(head, entry.start, entry.end);
            if (entry.id == 0x53ac) {
              position = _uint(head, entry.start, entry.end);
            }
          }
          if ((id == chaptersId || id == tagsId) &&
              position != null &&
              fetched.length < 4 &&
              fetched.add(position)) {
            blocks.add(await read(segment.start + position, 524288));
          }
        }
      }
      return parseBlocks(blocks);
    } finally {
      client.close();
    }
  }

  static Map<String, Object?> parseBlocks(List<Uint8List> blocks) {
    final chapters = <Map<String, Object?>>[], tags = <Map<String, Object?>>[];
    final labels = <int, String>{};
    final global = <String, String>{};
    String text(Uint8List bytes, _Element e) =>
        utf8.decode(bytes.sublist(e.start, e.end), allowMalformed: true);
    void visit(Uint8List bytes, int start, int end, int depth) {
      if (depth > 10) return;
      for (final element in _elements(bytes, start, end)) {
        // A bounded range may end inside a metadata block. Never infer a
        // timestamp or chapter label from a partially downloaded element.
        if (!element.complete) continue;
        if (element.id == 0xb6) {
          final record = <String, Object?>{};
          for (final child in _elements(bytes, element.start, element.end)) {
            if (child.id == 0x73c4) {
              record['uid'] = _uint(bytes, child.start, child.end);
            }
            if (child.id == 0x91) {
              record['startMs'] =
                  _uint(bytes, child.start, child.end) ~/ 1000000;
            }
            if (child.id == 0x92) {
              record['endMs'] = _uint(bytes, child.start, child.end) ~/ 1000000;
            }
            if (child.id == 0x80) {
              for (final display in _elements(bytes, child.start, child.end)) {
                if (display.id == 0x85) record['title'] = text(bytes, display);
              }
            }
          }
          chapters.add(record);
          visit(bytes, element.start, element.end, depth + 1);
        } else if (element.id == 0x7373) {
          int? uid;
          final values = <String, String>{};
          void simpleTags(int start, int end, int level) {
            if (level > 8) return;
            for (final entry in _elements(
              bytes,
              start,
              end,
            ).where((e) => e.id == 0x67c8 && e.complete)) {
              String? name, value;
              for (final field in _elements(
                bytes,
                entry.start,
                entry.end,
              ).where((e) => e.complete)) {
                if (field.id == 0x45a3) name = text(bytes, field);
                if (field.id == 0x4487) value = text(bytes, field);
              }
              if (name != null && value != null) {
                values[name.toUpperCase().replaceAll(RegExp(r'[ -]'), '_')] =
                    value;
              }
              simpleTags(entry.start, entry.end, level + 1);
            }
          }

          simpleTags(element.start, element.end, 0);
          for (final child in _elements(bytes, element.start, element.end)) {
            if (child.id == 0x63c0) {
              for (final target in _elements(bytes, child.start, child.end)) {
                if (target.id == 0x63c4) {
                  uid = _uint(bytes, target.start, target.end);
                }
              }
            }
          }
          if (uid != null && values.isNotEmpty) {
            labels[uid] = [...values.keys, ...values.values].join(' ');
          } else if (uid == null) {
            global.addAll(values);
          }
        } else if ([chaptersId, tagsId, 0x45b9].contains(element.id)) {
          visit(bytes, element.start, element.end, depth + 1);
        }
      }
    }

    for (final block in blocks) {
      visit(block, 0, block.length, 0);
    }
    for (final chapter in chapters) {
      if (labels.containsKey(chapter['uid'])) {
        tags.add({...chapter, 'title': labels[chapter['uid']]});
      }
    }
    for (final prefix in [
      'OP',
      'ED',
      'INTRO',
      'OUTRO',
      'OPENING',
      'CREDITS',
      'RECAP',
      'PREV',
    ]) {
      int? timestamp(String edge) {
        final milliseconds = double.tryParse(
          global['${prefix}_${edge}_MS'] ?? '',
        );
        if (milliseconds != null &&
            milliseconds.isFinite &&
            milliseconds >= 0) {
          return milliseconds.round();
        }
        final parts = (global['${prefix}_$edge'] ?? '').trim().split(':');
        if (parts.length > 3) return null;
        var seconds = 0.0;
        for (var i = 0; i < parts.length; i++) {
          final value = double.tryParse(parts[i]);
          if (value == null ||
              !value.isFinite ||
              value < 0 ||
              (i > 0 && value >= 60)) {
            return null;
          }
          seconds = seconds * 60 + value;
        }
        return (seconds * 1000).round();
      }

      final start = timestamp('START'), end = timestamp('END');
      if (start != null && end != null && end > start) {
        tags.add({'title': prefix, 'startMs': start, 'endMs': end});
      }
    }
    return {'chapters': chapters, 'mkvTags': tags};
  }

  static int _uint(Uint8List bytes, int start, int end) {
    if (end - start > 8) return 0;
    var value = 0;
    for (var i = start; i < end; i++) {
      value = (value << 8) | bytes[i];
    }
    return value;
  }

  static List<_Element> _elements(Uint8List bytes, int start, int limit) {
    final result = <_Element>[];
    var at = start;
    (int, int)? vint(int offset, bool id) {
      if (offset >= limit || bytes[offset] == 0) return null;
      var length = 1, mask = 0x80;
      while (length <= 8 && bytes[offset] & mask == 0) {
        length++;
        mask >>= 1;
      }
      if (length > 8 || offset + length > limit) return null;
      var value = id ? bytes[offset] : bytes[offset] & (mask - 1);
      for (var i = 1; i < length; i++) {
        value = (value << 8) | bytes[offset + i];
      }
      return (value, length);
    }

    while (at < limit && result.length < 4096) {
      final id = vint(at, true);
      if (id == null) break;
      final size = vint(at + id.$2, false);
      if (size == null) break;
      final body = at + id.$2 + size.$2;
      final end = (body + size.$1).clamp(body, limit);
      result.add(_Element(id.$1, at, body, end, body + size.$1 <= limit));
      if (end <= at) break;
      at = end;
    }
    return result;
  }
}

class _Element {
  const _Element(this.id, this.header, this.start, this.end, this.complete);
  final int id, header, start, end;
  final bool complete;
}
