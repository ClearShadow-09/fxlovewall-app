import 'package:flutter/material.dart';

import '../../theme/fx_motion.dart';

class FxNavItem {
  const FxNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 底部导航栏。
///
/// 视觉与旧 Kotlin 版逐项对齐：药丸 58×30、图标 22、文字 11sp，
/// 选中项 = 浅色药丸底 + 主题色文字/图标。
/// 动效：药丸用 AnimatedContainer 淡入，图标轻微回弹（FxMotion.pop）。
class FxBottomNav extends StatelessWidget {
  const FxBottomNav({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<FxNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: _NavCell(
                item: items[i],
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavCell extends StatefulWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FxNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavCell> createState() => _NavCellState();
}

class _NavCellState extends State<_NavCell> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color fg = widget.selected ? cs.primary : cs.onSurfaceVariant;

    return InkWell(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedScale(
        // 按下时整格轻微下沉，抬起回弹 —— 克制，不夸张
        scale: _down ? 0.94 : 1.0,
        duration: FxMotion.micro,
        curve: FxMotion.pop,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // 药丸底：选中淡入 + 轻微放大
            AnimatedContainer(
              duration: FxMotion.fast,
              curve: FxMotion.enter,
              width: 58,
              height: 30,
              decoration: BoxDecoration(
                color: widget.selected ? cs.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedScale(
                scale: widget.selected ? 1.0 : 0.92,
                duration: FxMotion.fast,
                curve: FxMotion.pop,
                child: Icon(widget.item.icon, size: 22, color: fg),
              ),
            ),
            const SizedBox(height: 1),
            AnimatedDefaultTextStyle(
              duration: FxMotion.fast,
              curve: FxMotion.enter,
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontWeight:
                    widget.selected ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(widget.item.label),
            ),
          ],
        ),
      ),
    );
  }
}
