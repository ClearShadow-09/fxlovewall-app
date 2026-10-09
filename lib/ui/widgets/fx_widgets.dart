import 'package:flutter/material.dart';

import '../../theme/fx_colors.dart';
import '../../theme/fx_motion.dart';
import '../../theme/fx_theme.dart';

/// 进错峰入场：按索引延迟一点点上移。
///
/// ⚠️ 刻意**不用 Opacity**（需求 14）。
/// 早先的做法是「淡入 + 上移」，但在列表末尾，某一项的 local 可能长时间停在
/// 中间值，看起来就是「底部文字一直是半透明、发虚发灰」，被反馈成动画有问题。
/// 现在只做位移，元素从头到尾都是完全不透明的，既保留进场感又不会糊。
///
/// 起跑时间：每项晚 4.5%，最多晚到 55%（避免长列表排到最后还没开始）。
/// 所有项共用同一个总时长，各自只是起跑时间不同。
class FxStaggerIn extends StatelessWidget {
  const FxStaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (FxMotion.off) return child;
    final double start = (index * 0.045).clamp(0.0, 0.55);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: FxMotion.staggerTotal,
      curve: FxMotion.enter,
      builder: (BuildContext context, double t, Widget? c) {
        final double local = ((t - start) / (1 - start)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, (1 - local) * FxMotion.itemShift),
          child: c,
        );
      },
      child: child,
    );
  }
}

/// 开关行。轨道与滑块都用主题色，切换时滑块平滑滑过去。
class FxSwitch extends StatelessWidget {
  const FxSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: FxMotion.fast,
        curve: FxMotion.enter,
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: FxMotion.fast,
          curve: FxMotion.move,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: value ? cs.onPrimary : cs.outline,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// 标题 + 右侧开关的一整行。
class FxSwitchRow extends StatelessWidget {
  const FxSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(fontSize: 15)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                FxSwitch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 页面大标题。
class FxPageTitle extends StatelessWidget {
  const FxPageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
        ),
      );
}

/// 分组小标题（设置页的「外观 / 浏览 / 账号 / 其他」），用主题色。
class FxSectionTitle extends StatelessWidget {
  const FxSectionTitle(this.text, {super.key, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: accent,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// 控件上方的标题。
class FxLabel extends StatelessWidget {
  const FxLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 15)),
      );
}

/// 标题下方的说明文字。
class FxSubLabel extends StatelessWidget {
  const FxSubLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// 点击行：按下时轻微缩放 + 原生水波纹，两端动效都来自 FxMotion。
class FxRow extends StatefulWidget {
  const FxRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailingText,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  State<FxRow> createState() => _FxRowState();
}

class _FxRowState extends State<FxRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedScale(
        scale: _down ? 0.985 : 1.0,
        duration: FxMotion.micro,
        curve: FxMotion.enter,
        child: Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(fxRadius(context)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    Icon(widget.icon, size: 22, color: cs.primary),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(widget.title, style: const TextStyle(fontSize: 15)),
                        if (widget.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.trailingText != null)
                    Text(
                      widget.trailingText!,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    Icon(Icons.chevron_right,
                        size: 20, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 互斥分段控件：选中块用 AnimatedPositioned 平滑滑动，而不是硬切。
class FxSegmented extends StatelessWidget {
  const FxSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  static const double _h = 42;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int n = labels.length;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = (c.maxWidth - _gap * (n - 1)) / n;
        return SizedBox(
          height: _h,
          child: Stack(
            children: <Widget>[
              // 滑块
              AnimatedPositioned(
                duration: FxMotion.fast,
                curve: FxMotion.move,
                left: selected * (w + _gap),
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < n; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: FxMotion.fast,
                            curve: FxMotion.enter,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: i == selected
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 主题色色块：选中时外环扩散 + 轻微放大。
class FxSwatches extends StatelessWidget {
  const FxSwatches({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (int i = 0; i < FxColors.accents.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: FxMotion.fast,
                curve: FxMotion.pop,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FxColors.accents[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == selected ? cs.onSurface : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: AnimatedScale(
                  scale: i == selected ? 1.0 : 0.86,
                  duration: FxMotion.fast,
                  curve: FxMotion.pop,
                  child: i == selected
                      ? Icon(Icons.check,
                          size: 18,
                          color: ThemeData.estimateBrightnessForColor(
                                      FxColors.accents[i]) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black87)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
