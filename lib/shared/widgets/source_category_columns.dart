import 'source_card_metrics.dart';
import 'source_picker_scroll_list.dart';

import 'package:flutter/material.dart';

class SourceColumnSection {
  const SourceColumnSection({
    required this.id,
    required this.title,
    required this.children,
  });
  final String id, title;
  final List<Widget> children;
}

/// Two physical lanes. Each owns a ListView and never shares its scroll offset
/// with the other lane. A category is assigned whole, never split into cells.
class SourceCategoryColumns extends StatelessWidget {
  const SourceCategoryColumns({
    super.key,
    required this.sections,
    this.keyPrefix = 'picker',
    this.initialSectionId,
    this.initialChildIndex = 0,
    this.focusKey,
  });
  final List<SourceColumnSection> sections;
  final String keyPrefix;
  final String? initialSectionId;
  final int initialChildIndex;
  final GlobalKey? focusKey;

  @override
  Widget build(BuildContext context) {
    Widget lane(int index) {
      final groups = [
        for (var i = index; i < sections.length; i += 2) sections[i],
      ];
      final targetGroup = groups.indexWhere(
        (group) => group.id == initialSectionId,
      );
      final offset = targetGroup < 0
          ? 0.0
          : (groups
                            .take(targetGroup)
                            .fold<int>(
                              0,
                              (count, group) => count + group.children.length,
                            ) +
                        initialChildIndex) *
                    (SourceCardMetrics.height + SourceCardMetrics.rowGap) +
                (groups.length == 1 ? 0 : (targetGroup + 1) * 44.0);
      Widget header(SourceColumnSection group) => Semantics(
        header: true,
        child: Padding(
          key: ValueKey('$keyPrefix-group-${group.id}'),
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Text(
            group.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.length == 1) header(groups.single),
          Expanded(
            child: SourcePickerScrollList(
              key: PageStorageKey('$keyPrefix-column-$index'),
              focusKey: targetGroup < 0 ? null : focusKey,
              estimatedOffset: offset,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final group in groups) ...[
                  if (groups.length != 1) header(group),
                  if (group.children.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '暂无匹配的源',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  for (final child in group.children)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: SourceCardMetrics.rowGap,
                      ),
                      child: child,
                    ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SourceCardMetrics.horizontalPadding,
        ),
        child: Row(
          key: ValueKey('$keyPrefix-category-columns'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: lane(0)),
            const SizedBox(width: SourceCardMetrics.columnGap),
            Expanded(child: lane(1)),
          ],
        ),
      ),
    );
  }
}
