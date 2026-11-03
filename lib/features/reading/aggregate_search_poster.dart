import 'package:flutter/material.dart';

import '../../core/reading/reading.dart';
import '../../shared/widgets/source_translation.dart';
import 'poster_card.dart';
import 'section_toolbar.dart';

/// Logical-pixel dimensions for the reference three-column search layout.
abstract final class AggregateSearchLayout {
  static const columns = 3;
  static const gridPadding = 10.0;
  static const columnGap = 8.0;
  static const rowGap = 16.0;
  static const coverHeightRatio = 1.38;
  static const coverRadius = 8.0;
  static const titleGap = 7.0;
  static const titleSize = 12.5;
  static const titleLineHeight = 1.25;
  static const dividerSlotWidth = 1.0;
  static const siteRowMinHeight = 46.0;
  static const siteRowRadius = 8.0;
  static const selectedSiteOpacity = .065;
  static const selectedIndicatorWidth = 2.0;
  static const selectedIndicatorHeight = 22.0;
  static const dividerOpacity = .08;
  static const siteSeparatorOpacity = .07;

  // Keep the source rail at the requested proportion across screen sizes.
  static double sidebarWidth(double width) => width * .26;
  static double cellWidth(double width) =>
      (width - 2 * gridPadding - (columns - 1) * columnGap) / columns;
  static double itemExtent(double width, double textScale) =>
      cellWidth(width) * coverHeightRatio +
      titleGap +
      titleSize * titleLineHeight * textScale * 2;
}

/// Search keeps its two-line caption below the cover, independently of the
/// reader's global overlay-title preference. Complete metadata stays available.
class AggregateSearchPoster extends StatelessWidget {
  const AggregateSearchPoster({
    super.key,
    required this.hit,
    required this.metadata,
    required this.onTap,
    this.pipeline,
  });
  final SearchHit hit;
  final String metadata;
  final VoidCallback onTap;
  final SectionImagePipeline? pipeline;

  String get _badge {
    final duration = hit.item.duration;
    if (duration != null) {
      final seconds = '${duration.inSeconds.remainder(60)}'.padLeft(2, '0');
      return '${duration.inMinutes}:$seconds';
    }
    final subtitle = hit.item.subtitle?.trim() ?? '';
    return subtitle.isNotEmpty
        ? subtitle.split(RegExp(r'\s*[·|｜]\s*')).first
        : '来源 ${hit.sourceName}';
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 1, maxScaleFactor: 2);
    return Tooltip(
      message: '${hit.item.title}\n$metadata',
      child: Semantics(
        button: true,
        label: '${hit.item.title}，$metadata',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(
              AggregateSearchLayout.coverRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => ClipRRect(
                      key: ValueKey(
                        'search-cover-${hit.sourceId}-${hit.item.id}',
                      ),
                      borderRadius: BorderRadius.circular(
                        AggregateSearchLayout.coverRadius,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CoverThumb(
                            title: hit.item.title,
                            pipeline: pipeline,
                            url: hit.item.cover,
                            headers: hit.item.coverHeaders,
                            width:
                                (constraints.maxWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .ceil()
                                    .clamp(1, 1200),
                          ),
                          Positioned(
                            left: 4,
                            right: 4,
                            bottom: 4,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .42),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _badge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: MediaQuery.textScalerOf(context)
                                      .clamp(
                                        minScaleFactor: 1,
                                        maxScaleFactor: 1.4,
                                      ),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    height: 1.15,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AggregateSearchLayout.titleGap),
                SizedBox(
                  height:
                      scaler.scale(AggregateSearchLayout.titleSize) *
                      AggregateSearchLayout.titleLineHeight *
                      2,
                  child: MediaQuery.withClampedTextScaling(
                    minScaleFactor: 1,
                    maxScaleFactor: 2,
                    child: SourceText(
                      hit.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: AggregateSearchLayout.titleSize,
                        height: AggregateSearchLayout.titleLineHeight,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
