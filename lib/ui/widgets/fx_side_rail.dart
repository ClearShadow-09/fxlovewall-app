import 'package:flutter/material.dart';

import '../../theme/fx_motion.dart';

/// 侧边导航项。
///
/// 与 [FxNavItem]（底部导航用）字段一致，刻意分开定义：底部版本要图标在上、
/// 文字在下、固定 58×30 的胶囊；侧边版本是图标在左、文字在右、可折叠。
/// 两者共用同一份语义（icon + label），但布局约束完全不同，
/// 硬塞进一个 widget 会让两边都难受。
class FxRailItem {
  const FxRailItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Windows / 桌面端的可折叠侧边导航栏。
///
/// 需求：把安卓端的底部导航搬到侧面。展开 200px、收起 64px。
///
/// 折叠时的取舍：收起后只剩图标，文字用 Tooltip 补（桌面端鼠标悬停能看，
/// 安卓端长按也能看），所以信息没有丢。选中态用一个左侧的强调条 + 主题色
/// 图标表达 —— 这是桌面应用的通行语言。
class FxSideRail extends StatelessWidget {
  const FxSideRail({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    required this.collapsed,
    required this.onToggle,
  });

  final List<FxRailItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  /// true = 只显示图标（64px），false = 图标 + 文字（200px）。
  final bool collapsed;
  final VoidCallback onToggle;

  static const double expandedWidth = 200;
  static const double collapsedWidth = 64;

  double get width => collapsed ? collapsedWidth : expandedWidth;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: FxMotion.medium,
      curve: FxMotion.move,
      width: width,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        // 只画右侧一条分隔线，不做整圈描边（桌面端侧栏的常规做法）
        border: Border(
          right: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: <Widget>[
          // ---- 顶部：折叠开关 ----
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: <Widget>[
                _IconBtn(
                  icon: collapsed ? Icons.menu : Icons.menu_open,
                  tooltip: collapsed ? '展开侧边栏' : '收起侧边栏',
                  onTap: onToggle,
                ),
                if (!collapsed) ...<Widget>[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '复兴表白墙',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 6),

          // ---- 导航项 ----
          for (int i = 0; i < items.length; i++)
            _RailCell(
              item: items[i],
              selected: i == index,
              collapsed: collapsed,
              onTap: () => onChanged(i),
            ),

          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: collapsed
                ? const SizedBox.shrink()
                : Text(
                    'v1.2.0-beta',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RailCell extends StatefulWidget {
  const _RailCell({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final FxRailItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_RailCell> createState() => _RailCellState();
}

class _RailCellState extends State<_RailCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool on = widget.selected;

    final Widget row = Row(
      mainAxisAlignment: widget.collapsed
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      // 图标与文字**垂直居中**。
      //
      // ⚠️ 文字看起来偏上是因为中文排版：Flutter 的 Text 默认按拉丁字母的
      // 基线（baseline）对齐，而中文没有下伸部（descender），字形整体贴在
      // 基线上方，于是与居中的图标一比就显得「高了半个字」。
      // 这里显式给文字一个行高并把 Row 对齐设为 center，让两者的**视觉
      // 中心**重合，而不是让基线重合。
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          widget.item.icon,
          size: 21,
          color: on ? cs.primary : cs.onSurfaceVariant,
        ),
        if (!widget.collapsed) ...<Widget>[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 用 height:1.0 + textHeightBehavior 去掉字体自带的上方留白，
              // 否则中文的行盒会比字形高，居中也救不回来。
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              style: TextStyle(
                fontSize: 14,
                height: 1.0,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        // 收起时文字没了，用 Tooltip 补上；展开时也给，鼠标停久了能看到
        message: widget.item.label,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: on
              ? cs.primaryContainer
              : (_hover ? cs.surfaceContainerHighest : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (bool v) {
              if (v != _hover) setState(() => _hover = v);
            },
            child: SizedBox(
              height: 42,
              child: Stack(
                children: <Widget>[
                  // 选中态的左侧强调条
                  if (on)
                    Positioned(
                      left: 0,
                      top: 9,
                      bottom: 9,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.collapsed ? 0 : 12,
                    ),
                    child: row,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏顶部的小图标按钮（折叠开关）。
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
