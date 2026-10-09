import 'package:flutter/material.dart';

import 'widgets/fx_widgets.dart';

/// 「其他」页：站点的两个独立板块入口。
class OtherPage extends StatelessWidget {
  const OtherPage({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: <Widget>[
          const FxStaggerIn(index: 0, child: FxPageTitle('其他')),
          FxStaggerIn(
            index: 1,
            child: FxRow(
              title: '每日小签',
              subtitle: '/daily',
              icon: Icons.calendar_today_outlined,
              onTap: () => onOpen('/daily'),
            ),
          ),
          FxStaggerIn(
            index: 2,
            child: FxRow(
              title: '你知道吗',
              subtitle: '/did-you-know',
              icon: Icons.lightbulb_outline,
              onTap: () => onOpen('/did-you-know'),
            ),
          ),
        ],
      ),
    );
  }
}
