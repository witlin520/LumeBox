import 'package:flutter/material.dart';

import 'source_card_metrics.dart';

/// 猫源卡片左滑露出的一个操作。
class SourceSwipeAction {
  const SourceSwipeAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// 左滑露出操作按钮的卡片；右滑 / 松手回弹。
///
/// 手势分工（与猫源现有交互一致）：
/// - 水平拖动 → 滑动卡片（本组件）；
/// - 长按不动 → 外层 `SourceDragTile` 的拖拽排序；
/// - 点击 → 卡片自身的 InkWell（选中站点 / 打开源）。
///
/// 之所以不用 `Dismissible`：那条路会把「滑走」当成删除语义，而猫源的左滑
/// 只是**露出菜单**，卡片必须留在原位。
class SourceSwipeTile extends StatefulWidget {
  const SourceSwipeTile({
    super.key,
    required this.child,
    required this.actions,
    this.height = SourceCardMetrics.height,
  });

  final Widget child;
  final List<SourceSwipeAction> actions;

  /// 卡片高度；源选择列表统一 50。
  final double height;

  @override
  State<SourceSwipeTile> createState() => _SourceSwipeTileState();
}

class _SourceSwipeTileState extends State<SourceSwipeTile>
    with SingleTickerProviderStateMixin {
  /// 每个操作按钮的宽度。
  static const double _actionWidth = 56;
  static final BorderRadius _radius = BorderRadius.circular(10);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_tick);
  double _dx = 0;
  double _from = 0;
  double _to = 0;

  double get _reveal => widget.actions.length * _actionWidth;

  void _tick() {
    setState(() => _dx = _from + (_to - _from) * _controller.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settle(double target) {
    _from = _dx;
    _to = target;
    _controller.forward(from: 0);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) _controller.stop();
    setState(() => _dx = (_dx + details.delta.dx).clamp(-_reveal, 0.0));
  }

  void _dragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity < -260 || (velocity <= 260 && _dx < -_reveal / 2);
    _settle(open ? -_reveal : 0);
  }

  void _run(VoidCallback action) {
    _settle(0);
    action();
  }

  Widget _action(SourceSwipeAction action) => Expanded(
    child: Material(
      color: action.color.withValues(alpha: .12),
      child: InkWell(
        onTap: () => _run(action.onTap),
        child: Center(
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: action.color,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) {
      return SizedBox(height: widget.height, child: widget.child);
    }
    return SizedBox(
      height: widget.height,
      child: Stack(
        // 卡片自己用 GlassCard 的柔和阴影；外层不再整体 ClipRRect，否则阴影
        // 会在卡片边缘被一刀切掉。只把背后的操作区裁成圆角即可。
        clipBehavior: _dx == 0 ? Clip.none : Clip.hardEdge,
        children: <Widget>[
          // 卡片收起时操作区不参与绘制：卡片阴影是半透明的，若把操作区
          // 一直垫在背后，阴影会把「设置 / 删除」的底色透成一条彩边。
          if (_dx != 0)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: _radius,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: _reveal,
                    child: Row(
                      children: <Widget>[
                        for (final action in widget.actions) _action(action),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _dragUpdate,
              onHorizontalDragEnd: _dragEnd,
              onHorizontalDragCancel: () => _settle(0),
              onTap: _dx != 0 ? () => _settle(0) : null,
              child: AbsorbPointer(absorbing: _dx != 0, child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}
