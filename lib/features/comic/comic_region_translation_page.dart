import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;

import '../../core/reading/comic_image_tools.dart';
import 'comic_page_composition.dart';

class ComicRegionTranslationResult {
  const ComicRegionTranslationResult(this.bytes, this.selection);
  final Uint8List bytes;
  final Rect selection;
}

/// Selection coordinates always refer to the full original image, not the
/// reader's zoom, cropped margins or split-page viewport.
class ComicRegionTranslationPage extends StatefulWidget {
  const ComicRegionTranslationPage({
    super.key,
    required this.loadImage,
    this.tools,
  });
  final Future<Uint8List> Function() loadImage;
  final ComicImageTools? tools;
  @override
  State<ComicRegionTranslationPage> createState() => _RegionState();
}

class _RegionState extends State<ComicRegionTranslationPage> {
  late final tools = widget.tools ?? ComicImageTools();
  ui.Image? image;
  Uint8List? result;
  Rect? selection;
  final points = <Offset>[];
  bool busy = true;
  bool selecting = true;
  String message = '正在加载原图…';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      final bytes = await widget.loadImage();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        math.min(
          1800 / descriptor.width,
          math.min(
            8192 / descriptor.height,
            math.sqrt(8000000 / (descriptor.width * descriptor.height)),
          ),
        ),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      final decoded = (await codec.getNextFrame()).image;
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() {
        image = decoded;
        busy = false;
        message = '用手指圈出对话框，或沿对角拖动框选；切换浏览可缩放长图。';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = '原图加载失败，请返回后重试';
        });
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  void dispose() {
    image?.dispose();
    if (widget.tools == null) tools.dispose();
    super.dispose();
  }

  void point(Offset local, Size display, {bool start = false}) {
    if (busy) return;
    final p = Offset(
      (local.dx / display.width).clamp(0, 1),
      (local.dy / display.height).clamp(0, 1),
    );
    setState(() {
      if (start) {
        points.clear();
        result = null;
      }
      points.add(p);
      final xs = points.map((p) => p.dx), ys = points.map((p) => p.dy);
      selection = Rect.fromLTRB(
        xs.reduce((a, b) => a < b ? a : b),
        ys.reduce((a, b) => a < b ? a : b),
        xs.reduce((a, b) => a > b ? a : b),
        ys.reduce((a, b) => a > b ? a : b),
      );
    });
  }

  Future<void> translate() async {
    final source = image?.clone(), rect = selection;
    if (source == null ||
        rect == null ||
        rect.width < .005 ||
        rect.height < .005 ||
        busy) {
      source?.dispose();
      return;
    }
    setState(() {
      busy = true;
      message = '正在翻译选定区域…';
    });
    ui.Image? cropped, translated;
    try {
      final bounds = Rect.fromLTRB(
        (rect.left * source.width).floorToDouble(),
        (rect.top * source.height).floorToDouble(),
        (rect.right * source.width).ceilToDouble(),
        (rect.bottom * source.height).ceilToDouble(),
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        source,
        bounds,
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
        Paint(),
      );
      final cropPicture = recorder.endRecording();
      cropped = await cropPicture.toImage(
        bounds.width.toInt(),
        bounds.height.toInt(),
      );
      cropPicture.dispose();
      final png = (await cropped.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      Uint8List replacement;
      if (tools.preferences.serverTranslation) {
        replacement = await tools.translateImageOnServer(png);
      } else {
        final regions = await tools.translateSelectedRegion(png);
        if (regions.isEmpty) throw const FormatException('选区未识别到可翻译的文字，请重新圈选');
        replacement = await composeComicPage(
          image: cropped,
          source: Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          colorMatrix: const [
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ],
          brightness: 1,
          displayWidth: bounds.width,
          translations: regions,
        );
      }
      if (!mounted) return;
      final codec = await ui.instantiateImageCodec(replacement);
      translated = (await codec.getNextFrame()).image;
      codec.dispose();
      final recorder2 = ui.PictureRecorder();
      final canvas = Canvas(recorder2)..drawImage(source, Offset.zero, Paint());
      canvas.drawImageRect(
        translated,
        Rect.fromLTWH(
          0,
          0,
          translated.width.toDouble(),
          translated.height.toDouble(),
        ),
        bounds,
        Paint(),
      );
      final picture = recorder2.endRecording();
      final output = await picture.toImage(source.width, source.height);
      picture.dispose();
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      if (mounted) {
        setState(() {
          result = bytes!.buffer.asUint8List();
          message = tools.lastTranslationWarning ?? '选区翻译完成，确认后应用到当前页';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is FormatException
              ? error.message
              : '选区翻译失败，请检查翻译引擎配置后重试',
        );
      }
    } finally {
      cropped?.dispose();
      translated?.dispose();
      source.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('翻译选定区域'),
      actions: [
        TextButton(
          onPressed: busy ? null : () => setState(() => selecting = !selecting),
          child: Text(selecting ? '缩放浏览' : '圈选区域'),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(message)),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: image == null
              ? const SizedBox()
              : LayoutBuilder(
                  builder: (_, box) {
                    final width = box.maxWidth;
                    final size = Size(
                      width,
                      width * image!.height / image!.width,
                    );
                    return InteractiveViewer(
                      panEnabled: !selecting,
                      scaleEnabled: !selecting,
                      constrained: false,
                      minScale: .25,
                      maxScale: 5,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: GestureDetector(
                          dragStartBehavior: DragStartBehavior.down,
                          key: const ValueKey('comic-region-canvas'),
                          onPanStart: selecting && !busy
                              ? (d) => point(d.localPosition, size, start: true)
                              : null,
                          onPanUpdate: selecting && !busy
                              ? (d) => point(d.localPosition, size)
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (result != null)
                                Image.memory(result!, fit: BoxFit.fill)
                              else
                                RawImage(image: image, fit: BoxFit.fill),
                              if (selection != null && result == null)
                                Positioned.fromRect(
                                  rect: Rect.fromLTWH(
                                    selection!.left * size.width,
                                    selection!.top * size.height,
                                    selection!.width * size.width,
                                    selection!.height * size.height,
                                  ),
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .12),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            selection = null;
                            result = null;
                            points.clear();
                            selecting = true;
                          }),
                    child: const Text('重新圈选'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: busy || selection == null
                        ? null
                        : result == null
                        ? translate
                        : () => Navigator.pop(
                            context,
                            ComicRegionTranslationResult(result!, selection!),
                          ),
                    child: Text(result == null ? '翻译选区' : '应用到当前页'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
