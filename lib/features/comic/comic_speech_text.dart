import '../../core/reading/comic_image_tools.dart';

/// OCR line offsets use UTF-16, matching Dart strings and native speech events.
class ComicSpeechLine {
  const ComicSpeechLine(this.region, this.start, this.end);
  final ComicTextRegion region;
  final int start, end;
}

class ComicSpeechText {
  ComicSpeechText(List<ComicTextRegion> regions) {
    final buffer = StringBuffer();
    for (final region in regions) {
      final value = region.text.trim();
      if (value.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      final start = buffer.length;
      buffer.write(value);
      lines.add(ComicSpeechLine(region, start, buffer.length));
    }
    text = buffer.toString();
  }
  late final String text;
  final List<ComicSpeechLine> lines = [];

  ComicSpeechLine? lineAt(int offset) {
    if (lines.isEmpty) return null;
    return lines.firstWhere(
      (line) => offset < line.end,
      orElse: () => lines.last,
    );
  }
}

class ComicSpeechCursor {
  const ComicSpeechCursor(this.url, this.page, this.offset);
  final String url;
  final ComicSpeechText page;
  final int offset;
  ComicSpeechLine? get line => page.lineAt(offset);
  String get text => line?.region.text.trim() ?? '';
  int get start {
    if (text.isEmpty) return 0;
    var value = (offset - (line?.start ?? 0)).clamp(0, text.length - 1);
    // A native offset must not leave half of an emoji in a TextSpan.
    if (value > 0 &&
        text.codeUnitAt(value) >= 0xDC00 &&
        text.codeUnitAt(value) <= 0xDFFF) {
      value--;
    }
    return value;
  }

  int get end {
    if (text.isEmpty) return 0;
    final unit = text.codeUnitAt(start);
    return (start + (unit >= 0xD800 && unit <= 0xDBFF ? 2 : 1)).clamp(
      0,
      text.length,
    );
  }
}
