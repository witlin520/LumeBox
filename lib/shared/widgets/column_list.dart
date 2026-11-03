import 'package:flutter/material.dart';

/// Shared list spacing and cell styling for source and collection drawers.
class ColumnList extends StatelessWidget {
  const ColumnList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.columns = 2,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.spacing = 10,
    this.shrinkWrap = false,
    this.physics,
    this.childAspectRatio,
    this.mainAxisExtent,
    this.decorateItems = true,
    this.itemPadding = const EdgeInsets.symmetric(vertical: 12),
  }) : assert(columns > 0);
  final int itemCount, columns;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding, itemPadding;
  final double spacing;
  final bool shrinkWrap, decorateItems;
  final ScrollPhysics? physics;
  final double? childAspectRatio;

  /// 多列网格的单元高度（未缩放值）；为空时沿用原来的 152。
  final double? mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    Widget item(BuildContext context, int index) {
      Widget child = ListTileTheme.merge(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        horizontalTitleGap: 6,
        minLeadingWidth: 24,
        child: ColumnListItemScope(child: itemBuilder(context, index)),
      );
      child = Padding(padding: itemPadding, child: child);
      if (decorateItems) {
        child = Material(
          color: columns == 1
              ? Colors.transparent
              : Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF303034)
              : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(10),
          child: child,
        );
      }
      return child;
    }

    if (columns > 1) {
      return GridView.builder(
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: physics,
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: childAspectRatio ?? 1,
          mainAxisExtent: childAspectRatio == null
              ? (mainAxisExtent ?? 152)
              : null,
        ),
        itemBuilder: item,
      );
    }
    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: itemCount,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E5EA)),
      itemBuilder: item,
    );
  }
}

/// Lets existing row cards omit their own surface inside a shared list cell.
class ColumnListItemScope extends InheritedWidget {
  const ColumnListItemScope({super.key, required super.child});
  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ColumnListItemScope>() != null;
  @override
  bool updateShouldNotify(ColumnListItemScope oldWidget) => false;
}
