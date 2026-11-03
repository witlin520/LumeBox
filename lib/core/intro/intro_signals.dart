import 'dart:math' as math;
import 'dart:typed_data';

import 'intro_models.dart';

class IntroSample {
  const IntroSample({
    required this.atMs,
    required this.gray,
    this.pcm = const [],
    this.text = '',
    this.textY,
    this.ai = const {},
    this.jpeg,
    this.lines = const [],
    this.warnings = const [],
  });
  final int atMs;

  /// Native side supplies 32×32 luminance, not a full decoded frame.
  final Uint8List gray;
  final List<double> pcm;
  final String text;
  final double? textY;
  final Map<String, double> ai;
  final Uint8List? jpeg;
  final List<Map<String, Object?>> lines;
  final List<String> warnings;
}

class IntroSignals {
  static final _cosines = List.generate(
    8,
    (frequency) => List.generate(
      32,
      (x) => math.cos((2 * x + 1) * frequency * math.pi / 64),
    ),
  );
  static String dHash(Uint8List pixels) {
    var bits = BigInt.zero;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = pixels[(y * 4) * 32 + (x * 31 ~/ 8)];
        final right = pixels[(y * 4) * 32 + ((x + 1) * 31 ~/ 8)];
        bits = (bits << 1) | (left > right ? BigInt.one : BigInt.zero);
      }
    }
    return bits.toRadixString(16).padLeft(16, '0');
  }

  static String pHash(Uint8List pixels) {
    final horizontal = List.generate(
      32,
      (y) => List.generate(8, (u) {
        var sum = 0.0;
        for (var x = 0; x < 32; x++) {
          sum += pixels[y * 32 + x] * _cosines[u][x];
        }
        return sum;
      }),
    );
    final low = <double>[];
    for (var v = 0; v < 8; v++) {
      for (var u = 0; u < 8; u++) {
        var total = 0.0;
        for (var y = 0; y < 32; y++) {
          total += horizontal[y][u] * _cosines[v][y];
        }
        low.add(total);
      }
    }
    final sorted = low.skip(1).toList()..sort();
    final median = sorted[31];
    var bits = BigInt.zero;
    for (var i = 0; i < low.length; i++) {
      bits =
          (bits << 1) | (i > 0 && low[i] > median ? BigInt.one : BigInt.zero);
    }
    return bits.toRadixString(16).padLeft(16, '0');
  }

  static int hamming(String a, String b) {
    var difference = BigInt.parse(a, radix: 16) ^ BigInt.parse(b, radix: 16);
    var n = 0;
    while (difference != BigInt.zero) {
      difference &= difference - BigInt.one;
      n++;
    }
    return n;
  }

  static double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0, aa = 0.0, bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    return aa * bb > 1e-12 ? (dot / math.sqrt(aa * bb)).clamp(-1, 1) : 0;
  }

  static double rms(List<double> samples) => samples.isEmpty
      ? 0
      : math.sqrt(samples.fold(0.0, (v, n) => v + n * n) / samples.length);

  /// 16 kHz mono PCM, 25 ms Hann windows, 10 ms stride, 26 mel filters,
  /// 13 DCT coefficients. Only bounded clips (≤ 0.96 s) enter this function.
  static List<double> mfcc(List<double> pcm) {
    if (pcm.length < 400) return [];
    const size = 512, filters = 26;
    final mean = List<double>.filled(13, 0);
    final edges = List<int>.generate(filters + 2, (i) {
      final mel =
          i * (2595 * math.log(1 + 8000 / 700) / math.ln10) / (filters + 1);
      return ((size + 1) * 700 * (math.pow(10, mel / 2595) - 1) / 16000)
          .floor()
          .clamp(0, 256);
    });
    var count = 0;
    // At most 12 windows per sample: MFCC is a fingerprint, not a decoder.
    for (
      var start = 0;
      start + 400 <= pcm.length && count < 12;
      start += math.max(160, (pcm.length ~/ 12 ~/ 160) * 160)
    ) {
      final real = List<double>.filled(size, 0),
          imag = List<double>.filled(size, 0);
      for (var i = 0; i < 400; i++) {
        real[i] =
            (pcm[start + i] - (start + i > 0 ? .97 * pcm[start + i - 1] : 0)) *
            (.5 - .5 * math.cos(2 * math.pi * i / 399));
      }
      _fft(real, imag);
      final power = List<double>.generate(
        257,
        (i) => (real[i] * real[i] + imag[i] * imag[i]) / size,
      );
      final mel = List<double>.generate(filters, (f) {
        var sum = 0.0;
        for (var k = edges[f]; k < edges[f + 1]; k++) {
          sum +=
              power[k] * (k - edges[f]) / math.max(1, edges[f + 1] - edges[f]);
        }
        for (var k = edges[f + 1]; k < edges[f + 2]; k++) {
          sum +=
              power[k] *
              (edges[f + 2] - k) /
              math.max(1, edges[f + 2] - edges[f + 1]);
        }
        return math.log(math.max(sum, 1e-10));
      });
      for (var c = 0; c < 13; c++) {
        for (var f = 0; f < filters; f++) {
          mean[c] += mel[f] * math.cos(math.pi * c * (f + .5) / filters);
        }
      }
      count++;
    }
    // Remove DC log energy; comparing gain shouldn't match unrelated silence.
    return count == 0 ? [] : mean.skip(1).map((v) => v / count).toList();
  }

  static void _fft(List<double> real, List<double> imag) {
    final n = real.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final r = real[i], im = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = r;
        imag[j] = im;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      for (var i = 0; i < n; i += len) {
        for (var j = 0; j < len ~/ 2; j++) {
          final angle = -2 * math.pi * j / len,
              c = math.cos(angle),
              s = math.sin(angle);
          final k = i + j, m = k + len ~/ 2;
          final r = c * real[m] - s * imag[m], im = s * real[m] + c * imag[m];
          real[m] = real[k] - r;
          imag[m] = imag[k] - im;
          real[k] += r;
          imag[k] += im;
        }
      }
    }
  }

  static bool _textured(Uint8List gray) {
    if (gray.length != 1024) return false;
    final mean = gray.fold(0, (a, b) => a + b) / gray.length;
    final variance =
        gray.fold(0.0, (v, n) => v + (n - mean) * (n - mean)) / gray.length;
    return variance > 64;
  }

  static Map<String, Object?> fingerprint(
    IntroSample sample,
    IntroOptions options,
  ) => {
    'at': sample.atMs,
    if (_textured(sample.gray) &&
        (options.enabled('phash') || options.enabled('joint')))
      'p': pHash(sample.gray),
    if (_textured(sample.gray) && options.enabled('dhash'))
      'd': dHash(sample.gray),
    if ((options.enabled('mfcc') || options.enabled('joint')) &&
        rms(sample.pcm) > .003)
      'm': mfcc(sample.pcm),
  };
}
