import '../../core/reading/comic_image_tools_settings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/translation/text_translation.dart';

class SourceText extends StatelessWidget {
  const SourceText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: TextTranslationService.shared,
    builder: (context, _) {
      final service = TextTranslationService.shared;
      return Text(
        service.displayOriginal ? text : service.lookup(text) ?? text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    },
  );
}

/// Translation is manual by default; long press enables live updates on this page.
class SourceTranslationAction extends StatefulWidget {
  const SourceTranslationAction({super.key, required this.texts});
  final List<String> texts;
  @override
  State<SourceTranslationAction> createState() =>
      _SourceTranslationActionState();
}

class _SourceTranslationActionState extends State<SourceTranslationAction> {
  bool busy = false;
  bool? _localLive;
  bool get live =>
      _localLive ?? ComicImageToolsSettings.instance.liveTranslation;
  void _settingsChanged() {
    if (!mounted) return;
    _localLive = null;
    liveAttempt = null;
    setState(() {});
    scheduleLive();
  }

  Timer? liveTimer;
  String? liveAttempt;
  String get liveIdentity => '$profile|${texts.join("\u0000")}';
  void scheduleLive() {
    liveTimer?.cancel();
    if (!live || busy || liveAttempt == liveIdentity || texts.isEmpty) return;
    liveTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || !live || busy) return;
      liveAttempt = liveIdentity;
      unawaited(translate(retryOnly: true));
    });
  }

  @override
  void dispose() {
    liveTimer?.cancel();
    ComicImageToolsSettings.instance.removeListener(_settingsChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _texts = _uniqueTexts(widget.texts);
    ComicImageToolsSettings.instance.addListener(_settingsChanged);
    scheduleLive();
    unawaited(TextTranslationService.shared.boot());
  }

  bool attempted = false;
  String? attemptedProfile;
  int processed = 0;
  late List<String> _texts;
  List<String> get texts => _texts;
  static List<String> _uniqueTexts(List<String> values) =>
      values.where((s) => s.trim().isNotEmpty).toSet().toList();
  String get profile {
    final settings = ComicImageToolsSettings.instance;
    return '${settings.source}|${settings.target}|${settings.translationMode}|${settings.endpoint}|${settings.model}';
  }

  @override
  void didUpdateWidget(covariant SourceTranslationAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.texts, widget.texts)) {
      attempted = false;
      _texts = _uniqueTexts(widget.texts);
      scheduleLive();
    }
  }

  String errorText(Object error) => error is MissingPluginException
      ? '设备端翻译需要 iOS 18 或以上'
      : error is FormatException
      ? error.message.toString()
      : error is PlatformException
      ? error.message ?? '翻译失败，原文保留'
      : error is TimeoutException
      ? '翻译请求超时，成功译文已保留；请检查翻译接口与网络后重试'
      : '翻译未完成，原文保留；请检查全局翻译设置与网络';

  Future<void> translate({bool retryOnly = false}) async {
    if (busy) return;
    final service = TextTranslationService.shared;
    final all = texts;
    final selectedProfile = profile;
    if (all.isEmpty) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('当前没有可翻译的内容，请等待加载完成')));
      return;
    }
    if (!retryOnly && all.every((s) => service.lookup(s) != null)) {
      service.toggleOriginal();
      return;
    }
    await service.boot();
    if (!mounted) return;
    if (!retryOnly && all.every((s) => service.lookup(s) != null)) {
      service.toggleOriginal();
      return;
    }
    final pending = all.where((s) => service.lookup(s) == null).toList();
    setState(() {
      busy = true;
      attempted = true;
      attemptedProfile = selectedProfile;
      processed = all.length - pending.length;
    });
    Object? failure;
    try {
      var start = 0;
      while (start < pending.length &&
          mounted &&
          selectedProfile == profile &&
          listEquals(all, texts)) {
        var end = start, size = 0;
        while (end < pending.length &&
            end - start < 100 &&
            size + pending[end].runes.length <= 40000) {
          size += pending[end].runes.length;
          end++;
        }
        if (end == start) throw const FormatException('文字过长，请分段翻译');
        try {
          await service.translate(pending.sublist(start, end));
        } catch (error) {
          failure = error;
          // A failed language must not prevent the remaining page from translating.
          if (error is! PlatformException ||
              error.code != 'translation_partial') {
            break;
          }
        }
        start = end;
        if (mounted) {
          setState(
            () =>
                processed = all.where((s) => service.lookup(s) != null).length,
          );
        }
      }
    } catch (error) {
      failure = error;
    } finally {
      if (mounted) {
        setState(() => busy = false);
        scheduleLive();
      }
      if (mounted &&
          selectedProfile == profile &&
          listEquals(all, texts) &&
          (!live || failure != null)) {
        final values = {for (final text in all) text: service.lookup(text)};
        final complete = values.values.where((value) => value != null).length;
        final translated = values.entries
            .where((entry) => entry.value != null && entry.value != entry.key)
            .length;
        final remaining = all.length - complete;
        if (service.displayOriginal && complete > 0) service.toggleOriginal();
        final summary = '已翻译 $translated 条，未完成 $remaining 条';
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 10),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    key: const ValueKey('source-translation-result'),
                  ),
                  if (complete > translated)
                    Text('原文保留 ${complete - translated} 条'),
                  if (failure != null) Text(errorText(failure)),
                ],
              ),
              action: remaining == 0
                  ? null
                  : SnackBarAction(
                      label: '重试未完成',
                      onPressed: () {
                        if (mounted) unawaited(translate(retryOnly: true));
                      },
                    ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: TextTranslationService.shared,
    builder: (context, _) {
      final service = TextTranslationService.shared;
      final remaining = texts
          .where((text) => service.lookup(text) == null)
          .length;
      final cached = texts.isNotEmpty && remaining == 0;
      return IconButton(
        onLongPress: () {
          setState(() {
            _localLive = !live;
            liveAttempt = null;
          });
          scheduleLive();
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(live ? '实时翻译已开启，新加载文字会自动翻译；长按关闭' : '实时翻译已关闭'),
              ),
            );
        },
        tooltip: busy
            ? '正在翻译… 已完成 $processed/${texts.length}'
            : cached && !service.displayOriginal
            ? '显示原文'
            : ComicImageToolsSettings.instance.target == 'zh-Hans'
            ? '翻译成中文'
            : '翻译成${ComicImageToolsSettings.languages[ComicImageToolsSettings.instance.target]}',
        constraints: const BoxConstraints.tightFor(width: 40, height: 44),
        onPressed: busy ? null : () => translate(),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Badge(
                isLabelVisible:
                    attempted && attemptedProfile == profile && remaining > 0,
                label: Text('$remaining'),
                child: Icon(
                  live ? Icons.auto_awesome : Icons.translate,
                  size: 18,
                ),
              ),
      );
    },
  );
}
