import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/image_bytes_decoder.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:pointycastle/export.dart'
    show
        AESEngine,
        CBCBlockCipher,
        ECBBlockCipher,
        KeyParameter,
        ParametersWithIV;

/// App 侧的两条「内联/加密图」通路：
/// 1. `data:image/...;base64,...` 直接解码（源脚本解密后交出来的形态）；
/// 2. `lume-enc://aes-ecb/<key>/<url>` 与 `lume-enc://aes-cbc/<key>/<iv>/<url>`
///    —— 站点把封面加密后直接扔在 CDN 上（好妻网的 .ceb、9sex 的 .webp.txt），
///    解密放 App 用原生 AES 做（key 随 URI 带过来，不写进 App）。
void main() {
  // 1x1 透明 PNG
  const pngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  final pngBytes = base64Decode(pngBase64);
  final dataUri = 'data:image/png;base64,$pngBase64';

  Uint8List pkcs7Pad(Uint8List data) {
    final padLen = 16 - data.length % 16;
    final out = Uint8List(data.length + padLen)..setAll(0, data);
    for (var i = 0; i < padLen; i++) {
      out[data.length + i] = padLen;
    }
    return out;
  }

  test('data URI 直接解码成图片字节', () {
    expect(SectionImagePipeline.decodeDataUri(dataUri), pngBytes);
    expect(
      SectionImagePipeline.decodeDataUri('  $dataUri  '),
      pngBytes,
      reason: '前后空白要容忍（源里常有换行）',
    );
  });

  test('非 data / 非图片的地址返回 null（交给普通下载）', () {
    expect(SectionImagePipeline.decodeDataUri('https://a.com/b.jpg'), isNull);
    expect(
      SectionImagePipeline.decodeDataUri('data:text/plain;base64,QQ=='),
      isNull,
    );
    expect(SectionImagePipeline.decodeDataUri('data:image/png;base64'), isNull);
    expect(SectionImagePipeline.decodeDataUri(''), isNull);
  });

  test('非标准的 data:png;base64 也要能解（9sex 解密后的封面）', () {
    expect(
      SectionImagePipeline.decodeDataUri('data:png;base64,$pngBase64'),
      pngBytes,
    );
    expect(
      SectionImagePipeline.decodeDataUri('data:webp;base64,$pngBase64'),
      pngBytes,
    );
  });

  test('reverse 编码还原逐字节反转的图片（爱豆的 .ttf 封面）', () {
    final reversed = Uint8List.fromList(pngBytes.reversed.toList());
    final decoded = decodeSourceImage(reversed, {
      'x-lume-image-encoding': 'reverse',
    });
    expect(decoded, pngBytes);
  });

  test('strip-prefix-16 跳过杏吧图床的 16 字节头', () {
    final prefixed = Uint8List(16 + pngBytes.length)
      ..setAll(0, List<int>.generate(16, (i) => i + 1))
      ..setAll(16, pngBytes);
    final decoded = decodeSourceImage(prefixed, {
      'x-lume-image-encoding': 'strip-prefix-16',
    });
    expect(decoded, pngBytes);
    expect(
      decodeSourceImage(pngBytes, {'x-lume-image-encoding': 'strip-prefix-16'}),
      pngBytes,
      reason: '明文图不能被误伤',
    );
  });

  test('aes-ecb-base64 解 hxc 的 Base64 文本密文', () {
    final key = Uint8List.fromList(utf8.encode('46cc793c53dc451b'));
    // 明文是 data URI 文本；NoPadding 需要 16 字节对齐，用 NUL 补齐。
    final text = Uint8List.fromList(utf8.encode(dataUri));
    final paddedLength = (text.length + 15) ~/ 16 * 16;
    final plain = Uint8List(paddedLength)..setAll(0, text);
    final cipher = ECBBlockCipher(AESEngine())
      ..init(true, KeyParameter(key));
    final cipherBytes = Uint8List(plain.length);
    for (var off = 0; off < plain.length; off += 16) {
      cipher.processBlock(plain, off, cipherBytes, off);
    }
    final encoded = Uint8List.fromList(utf8.encode(base64Encode(cipherBytes)));
    final decoded = decodeSourceImage(encoded, {
      'x-lume-image-encoding': 'aes-ecb-base64',
      'x-lume-image-key': '46cc793c53dc451b',
    });
    expect(decoded, pngBytes);
  });

  test('aes-cbc-pkcs7-ivprefix 用文件头 16 字节当 IV（月色的 .jpg.aes）', () {
    final key = Uint8List.fromList(utf8.encode('yuese!niubia!666'));
    final iv = Uint8List.fromList(utf8.encode('0123456789abcdef'));
    final plain = pkcs7Pad(pngBytes);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final cipherBytes = Uint8List(plain.length);
    for (var off = 0; off < plain.length; off += 16) {
      cipher.processBlock(plain, off, cipherBytes, off);
    }
    final encoded = Uint8List(iv.length + cipherBytes.length)
      ..setAll(0, iv)
      ..setAll(iv.length, cipherBytes);
    final decoded = decodeSourceImage(encoded, {
      'x-lume-image-encoding': 'aes-cbc-pkcs7-ivprefix',
      'x-lume-image-key': 'yuese!niubia!666',
    });
    expect(decoded, pngBytes);
  });

  test('AES 逐块解密往返：ECB / CBC 都能还原 data URI 明文', () {
    final key = Uint8List.fromList(
      utf8.encode('82758dd12749c777ef579f1839ceea6a'),
    );
    final iv = Uint8List.fromList(utf8.encode('5efdtf6060e2o330'));
    final plain = pkcs7Pad(Uint8List.fromList(utf8.encode(dataUri)));

    Uint8List roundTrip(bool cbc) {
      final enc = cbc
          ? (CBCBlockCipher(AESEngine())
              ..init(true, ParametersWithIV(KeyParameter(key), iv)))
          : (ECBBlockCipher(AESEngine())..init(true, KeyParameter(key)));
      final cipherBytes = Uint8List(plain.length);
      for (var off = 0; off < plain.length; off += 16) {
        enc.processBlock(plain, off, cipherBytes, off);
      }
      final dec = cbc
          ? (CBCBlockCipher(AESEngine())
              ..init(false, ParametersWithIV(KeyParameter(key), iv)))
          : (ECBBlockCipher(AESEngine())..init(false, KeyParameter(key)));
      final out = Uint8List(cipherBytes.length);
      for (var off = 0; off < cipherBytes.length; off += 16) {
        dec.processBlock(cipherBytes, off, out, off);
      }
      final pad = out.last;
      return Uint8List.sublistView(out, 0, out.length - pad);
    }

    for (final cbc in <bool>[false, true]) {
      final restored = utf8.decode(roundTrip(cbc));
      expect(
        restored,
        dataUri,
        reason: cbc ? 'CBC（9sex .webp.txt）' : 'ECB（好妻网 .ceb）',
      );
      expect(SectionImagePipeline.decodeDataUri(restored), pngBytes);
    }
  });

  test('xor-prefix 只翻转开头 N 字节，后面的原图不能动', () {
    // Butterfly 系 App 的做法：整张图上传后只把前 100 字节和 imgKey 循环异或
    final key = Uint8List.fromList(utf8.encode('2019ysapp7527'));
    final body = Uint8List.fromList(
      <int>[...pngBytes, ...List<int>.filled(200, 0x5a)],
    );
    Uint8List obfuscate(Uint8List src, int length) {
      final out = Uint8List.fromList(src);
      for (var i = 0; i < length && i < out.length; i++) {
        out[i] ^= key[i % key.length];
      }
      return out;
    }

    for (final length in <int>[100, 64]) {
      final repaired = xorRepairImageBytes(obfuscate(body, length), key,
          length: length);
      expect(repaired, body, reason: '前 $length 字节异或回来要跟原图一致');
      expect(repaired.sublist(length), body.sublist(length),
          reason: '超出长度的部分本来就没加密，不能被二次翻转');
      // 源声明 coverHeaders 时走的就是这条通路
      final declared = decodeSourceImage(obfuscate(body, length), {
        'x-lume-image-encoding': 'xor-prefix',
        'x-lume-image-key': '2019ysapp7527',
        if (length != 100) 'x-lume-image-length': '$length',
      });
      expect(declared, body);
    }

    // 长度超过文件本身：只翻到文件末尾，不越界
    expect(
      xorRepairImageBytes(obfuscate(body, body.length), key, length: 4096),
      body,
    );
    // 空 key / 空数据原样返回，不抛异常
    expect(xorRepairImageBytes(body, Uint8List(0)), body);
    expect(xorRepairImageBytes(Uint8List(0), key), isEmpty);
  });
}
