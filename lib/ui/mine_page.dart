import 'package:flutter/material.dart';

import 'widgets/fx_widgets.dart';

/// 「我的」页：只放两个内容入口。
///
/// 登录 / 注册 / 退出登录按需求放在设置页，这里不再重复。
class MinePage extends StatelessWidget {
  const MinePage({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: <Widget>[
          const FxStaggerIn(index: 0, child: FxPageTitle('我的')),
          FxStaggerIn(
            index: 1,
            child: FxRow(
              title: '我的帖子',
              icon: Icons.article_outlined,
              onTap: () => onOpen('/my-posts'),
            ),
          ),
          FxStaggerIn(
            index: 2,
            child: FxRow(
              title: '我的收藏',
              icon: Icons.star_outline,
              onTap: () => onOpen('/favorites'),
            ),
          ),
        ],
      ),
    );
  }
}
