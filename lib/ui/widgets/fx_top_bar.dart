import 'package:flutter/material.dart';

import '../../theme/fx_motion.dart';

/// 首页顶部的搜索框 + 「最新 / 最热门 / 手气不错」胶囊 + 「今日幸运物品」纯文字。
///
/// 视觉对齐旧 Kotlin 版：描边圆角输入框（无浮标「标签」，那是早期已删掉的失误），
/// 选中胶囊 = 实心主题色 + 白字，未选中 = 浅色底 + 主题色字。
///
/// v1.1.0 改动（需求 1）：
///   · 「手气不错」从站点里那行（本就被 CSS 隐藏）挪到「最热门」同一排
///   · 三个胶囊整体缩小一号（高 40→34，字号 14→13，图标 17→15，内边距 18→13）
///   · 下方加一行「今日幸运物品」——主题色可交互纯文字，不是按钮
class FxTopBar extends StatefulWidget {
  const FxTopBar({
    super.key,
    required this.query,
    required this.sort,
    required this.onSearch,
    required this.onSort,
    required this.onLuckyPost,
    required this.onLuckyItem,
    this.luckyText,
  });

  final String query;
  final String sort;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSort;

  /// 手气不错：跳站点的 /lucky-post（随机打开一条公开帖子）。
  final VoidCallback onLuckyPost;

  /// 今日幸运物品：直接打 /daily-lucky-item。
  final VoidCallback onLuckyItem;

  /// 抽到的文字（需求 2）。非空时**替换**「今日幸运物品」这行文字本身，
  /// 而不是另弹一个层 —— 结果就长在用户刚才点的地方。
  final String? luckyText;

  @override
  State<FxTopBar> createState() => _FxTopBarState();
}

class _FxTopBarState extends State<FxTopBar> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.query);
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 搜索框：聚焦时描边过渡到主题色（AnimatedContainer）
          AnimatedContainer(
            duration: FxMotion.fast,
            curve: FxMotion.enter,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius(context)),
              border: Border.all(
                color: _focused ? cs.primary : cs.outline,
                width: _focused ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 13),
                AnimatedSwitcher(
                  duration: FxMotion.fast,
                  child: Icon(
                    Icons.search,
                    key: ValueKey<bool>(_focused),
                    size: 20,
                    color: _focused ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: widget.onSearch,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '搜索标签、关键词或帖子编号（如 12）',
                      hintStyle: TextStyle(fontSize: 13, color: cs.outline),
                    ),
                  ),
                ),
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 17),
                    color: cs.onSurfaceVariant,
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {});
                      widget.onSearch('');
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 三个胶囊同一排。整体缩小一号：高 34 / 字号 13 / 内边距 13。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _Pill(
                  label: '最新',
                  icon: Icons.mail_outline,
                  active: widget.sort != 'hot',
                  onTap: () => widget.onSort('latest'),
                ),
                const SizedBox(width: 8),
                _Pill(
                  label: '最热门',
                  icon: Icons.local_fire_department_outlined,
                  active: widget.sort == 'hot',
                  onTap: () => widget.onSort('hot'),
                ),
                const SizedBox(width: 8),
                _Pill(
                  label: '手气不错',
                  icon: Icons.casino_outlined,
                  active: false,
                  ghost: true,
                  onTap: widget.onLuckyPost,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _LuckyItemLink(onTap: widget.onLuckyItem, result: widget.luckyText),
        ],
      ),
    );
  }

  double _radius(BuildContext context) {
    final ShapeBorder? s = Theme.of(context).cardTheme.shape;
    if (s is RoundedRectangleBorder) {
      return s.borderRadius.resolve(TextDirection.ltr).topLeft.x * 1.5;
    }
    return 14;
  }
}

/// 「今日幸运物品」：主题色纯文字，可点，带按下缩放 —— 刻意不做成按钮。
///
/// 需求 2：抽到结果后，**这行文字本身**换成服务端返回的那句随机串
/// （例如「今日请注意……」），不再弹底部弹层。抽到之后仍然可点，
/// 但服务端对同一账号每天只给一次结果，重复点会返回同一句。
class _LuckyItemLink extends StatefulWidget {
  const _LuckyItemLink({required this.onTap, this.result});

  final VoidCallback onTap;

  /// 非空 = 已抽到，直接显示它，不再显示「今日幸运物品」。
  final String? result;

  @override
  State<_LuckyItemLink> createState() => _LuckyItemLinkState();
}

class _LuckyItemLinkState extends State<_LuckyItemLink> {
  bool _down = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool got = (widget.result ?? '').trim().isNotEmpty;
    final String label = got ? widget.result!.trim() : '今日幸运物品';

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () async {
          setState(() => _busy = true);
          await Future<void>.delayed(const Duration(milliseconds: 220));
          if (mounted) setState(() => _busy = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.96 : 1.0,
          duration: FxMotion.micro,
          curve: FxMotion.enter,
          child: AnimatedOpacity(
            opacity: _busy ? 0.55 : 1.0,
            duration: FxMotion.fast,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              // 文字换成结果后可能变长，用 AnimatedSize 让这一行的高度
              // 平滑变化，而不是把下面的内容硬顶一下
              child: AnimatedSize(
                duration: FxMotion.fast,
                curve: FxMotion.enter,
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: FxMotion.fast,
                  switchInCurve: FxMotion.enter,
                  switchOutCurve: FxMotion.exit,
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.18),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  child: Text(
                    label,
                    key: ValueKey<String>(label),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      color: cs.primary,
                      decoration:
                          got ? TextDecoration.none : TextDecoration.underline,
                      decorationColor: cs.primary.withValues(alpha: 0.45),
                      decorationThickness: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 筛选胶囊。选中/未选中之间用 AnimatedContainer 过渡底色与文字色。
///
/// [ghost] 用于「手气不错」：它不是一个筛选状态，所以永远不点亮，
/// 只在按下时轻微变深，避免和「最新 / 最热门」的二选一语义混淆。
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.ghost = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FxMotion.fast,
        curve: FxMotion.enter,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: <Widget>[
            AnimatedScale(
              scale: active ? 1.0 : 0.94,
              duration: FxMotion.fast,
              curve: FxMotion.pop,
              child: Icon(
                icon,
                size: 15,
                color: active
                    ? cs.onPrimary
                    : (ghost ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: FxMotion.fast,
              curve: FxMotion.enter,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active
                    ? cs.onPrimary
                    : (ghost ? cs.primary : cs.onSurfaceVariant),
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
