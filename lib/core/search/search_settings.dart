import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chinese_search_map.dart';

class SearchSettings extends ChangeNotifier {
  SearchSettings._();
  static final instance = SearchSettings._();
  bool simplify = true;
  bool exact = false;
  File? _file;
  Future<void> _writing = Future.value();
  Future<void> boot() async {
    try {
      _file = File(
        '${(await getApplicationSupportDirectory()).path}/search_settings.json',
      );
      if (await _file!.exists()) {
        final data =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        simplify = data['simplify'] != false;
        exact = data['exact'] == true;
      }
    } catch (_) {
      /* A damaged preference must not prevent searching. */
    }
  }

  Future<void> update({bool? simplify, bool? exact}) async {
    if (_file == null) await boot();
    this.simplify = simplify ?? this.simplify;
    this.exact = exact ?? this.exact;
    notifyListeners();
    final data = jsonEncode({'simplify': this.simplify, 'exact': this.exact});
    _writing = _writing.catchError((Object _) {}).then((_) async {
      if (_file == null) await boot();
      final file = _file;
      if (file != null) {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(data, flush: true);
        await temp.rename(file.path);
      }
    });
    await _writing;
  }

  static final int _maxLength = searchChineseMap.keys.fold(
    1,
    (n, key) => key.length > n ? key.length : n,
  );
  static String toSimplified(String input) {
    final out = StringBuffer();
    var index = 0;
    while (index < input.length) {
      String? value;
      var length = (input.length - index).clamp(1, _maxLength);
      for (; length > 0; length--) {
        value = searchChineseMap[input.substring(index, index + length)];
        if (value != null) break;
      }
      if (value != null) {
        out.write(value);
        index += length;
      } else {
        out.write(input[index++]);
      }
    }
    return out.toString();
  }

  String prepare(String input) =>
      simplify ? toSimplified(input.trim()) : input.trim();
  bool accepts(String title, String query) =>
      !exact ||
      query.trim().isEmpty ||
      prepare(title).toLowerCase() == prepare(query).toLowerCase();

  /// Some sites return their homepage/recommendations when search has no hits.
  /// Aggregate results must have title evidence even with exact mode disabled.
  bool acceptsAggregate(String title, String query) {
    String normalize(String value) {
      final width = String.fromCharCodes(
        prepare(value).runes.map(
          (rune) => rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune,
        ),
      );
      return width
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
          .trim();
    }

    final needle = normalize(query);
    final candidate = normalize(title);
    if (needle.isEmpty || candidate.isEmpty) return false;
    if (exact) return candidate == needle;
    final compact = candidate.replaceAll(' ', '');
    return needle.split(' ').every((term) {
      // Short Latin words must not match the middle of unrelated words.
      if (RegExp(r'^[a-z0-9]+$').hasMatch(term)) {
        return RegExp('(^|[^a-z0-9])${RegExp.escape(term)}(?=\$|[^a-z0-9])')
            .hasMatch(candidate);
      }
      return compact.contains(term);
    });
  }
}
