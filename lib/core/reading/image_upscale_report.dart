import 'dart:async';

class ImageUpscaleReport {
  const ImageUpscaleReport(
    this.status, {
    this.width,
    this.height,
    this.outputWidth,
    this.outputHeight,
    this.reason = '',
  });
  final String status, reason;
  final int? width, height, outputWidth, outputHeight;
  String get label => switch (status) {
    'processed' => '已完成 AI 超分',
    'skipped' => '无需超分，显示原图',
    _ => '超分未完成，已保留原图',
  };
  String get summary => [
    label,
    if (width != null && height != null)
      '$width×$height'
          '${outputWidth != null && outputHeight != null ? ' → $outputWidth×$outputHeight' : ''}',
    if (reason.isNotEmpty) reason,
  ].join(' · ');

  // 每个解码任务自己的回调，避免并发图片互相拿到对方的处理状态。
  static final Object zoneKey = Object();
  void publish() {
    final callback = Zone.current[zoneKey];
    if (callback is void Function(ImageUpscaleReport)) callback(this);
  }
}
