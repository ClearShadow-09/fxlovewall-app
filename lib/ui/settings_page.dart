import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../state/fx_settings.dart';
import '../theme/fx_motion.dart';
import 'widgets/fx_widgets.dart';

/// 设置页：主题 / 外观 / 浏览 / 账号 / 其他。
///
/// v1.1.0 变化：
///   · 顶部多了一个「软件主题 / 网页主题」的总开关（需求 17）
///   · 「网页主题」下外观只剩「深浅色跟随系统」+「字号」—— 因为那个模式
///     网页侧零注入，主题色/背景/圆角/动画都无从施加
///   · 新增「圆角」（默认 8px）与「动画」（全部/关键/无动画）
///   · 去掉背景图预览（需求 7）
///   · 进场动画不再使用透明度（需求 14）
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.loggedIn,
    required this.onLogin,
    required this.onRegister,
    required this.onLogout,
    required this.onOpenSite,
    required this.onClearCache,
    required this.onCheckUpdate,
    this.versionName = '未知',
  });

  final FxSettings settings;
  final bool loggedIn;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenSite;
  final Future<void> Function() onClearCache;

  /// 需求 7：手动检查更新。
  final Future<void> Function() onCheckUpdate;

  /// 当前版本号，由原生读出（避免引入 package_info_plus，省体积）。
  final String versionName;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  FxSettings get _s => widget.settings;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool web = _s.webTheme;
    int i = 0;

    /// 依次取号，保证错峰顺序跟着实际渲染顺序走 ——
    /// 网页主题下少了一半控件，硬编码的 index 会留下空档。
    Widget next(Widget child) => FxStaggerIn(index: i++, child: child);

    final List<Widget> rows = <Widget>[
      next(const FxPageTitle('设置')),

      // ---------------- 主题总开关 ----------------
      next(FxSectionTitle('主题', accent: cs.primary)),
      next(const FxSubLabel(
          '「软件主题」会重绘网页界面；「网页主题」原样显示站点，只保留底部导航')),
      next(FxSegmented(
        labels: const <String>['软件主题', '网页主题'],
        selected: web ? 1 : 0,
        onChanged: (int v) => _s.webTheme = (v == 1),
      )),

      // ---------------- 外观 ----------------
      next(FxSectionTitle('外观', accent: cs.primary)),

      if (web) ...<Widget>[
        next(const FxLabel('深浅色跟随系统')),
        next(const FxSubLabel('站点没有深色模式，开启后由软件给整个网页叠加深色滤镜')),
        next(FxSwitchRow(
          title: '跟随系统深浅色',
          subtitle: _s.webFollowSystem ? '跟随系统的浅色 / 深色' : '固定使用浅色',
          value: _s.webFollowSystem,
          onChanged: (bool v) => _s.webFollowSystem = v,
        )),
      ] else ...<Widget>[
        next(const FxLabel('主题模式')),
        next(FxSegmented(
          labels: const <String>['跟随系统', '浅色', '深色'],
          selected: !FxSettings.themeModes.contains(_s.themeMode)
              ? 0
              : FxSettings.themeModes.indexOf(_s.themeMode),
          onChanged: (int v) => _s.themeMode = FxSettings.themeModes[v],
        )),
        next(const FxLabel('主题色')),
        next(const FxSubLabel('将网页里的链接、按钮和图标切换为所选颜色')),
        next(FxSwatches(
          selected: _s.accentIndex,
          onChanged: (int v) => _s.accentIndex = v,
        )),
        next(const FxLabel('背景')),
        next(const FxSubLabel('用图片替换网页的灰色底层')),
        next(_buildBgControls(cs)),
      ],

      // 字号：两种主题下都提供
      next(const FxLabel('字号')),
      next(FxSubLabel(web ? '调整软件界面的字号' : '调整软件界面与网页的字号')),
      next(FxSegmented(
        labels: const <String>['小', '标准', '大', '特大'],
        selected: _s.fontStep,
        onChanged: (int v) => _s.fontStep = v,
      )),

      if (!web) ...<Widget>[
        next(const FxLabel('圆角')),
        next(const FxSubLabel('卡片、按钮、输入框的圆角大小，默认更方一些')),
        next(FxSegmented(
          labels: const <String>['直角', '较小', '默认', '较大', '大'],
          selected: _nearestRadiusStep(),
          onChanged: (int v) => _s.cornerRadius = FxSettings.radiusSteps[v],
        )),
        next(const FxLabel('动画')),
        next(const FxSubLabel('「关键」只保留页面切换，「无动画」关闭所有动效')),
        next(FxSegmented(
          labels: const <String>['全部', '关键', '无动画'],
          selected: _s.motionChoice,
          onChanged: (int v) => _s.motionChoice = v,
        )),
      ],

      // ---------------- 浏览 ----------------
      if (!web) ...<Widget>[
        next(FxSectionTitle('浏览', accent: cs.primary)),
        next(const FxLabel('每页帖子数')),
        next(const FxSubLabel('首页、搜索结果、我的帖子等列表每页显示的条数')),
        next(FxSegmented(
          labels: const <String>['10', '20', '30', '50', '全部'],
          selected: !FxSettings.pageSizes.contains(_s.pageSize)
              ? 0
              : FxSettings.pageSizes.indexOf(_s.pageSize),
          onChanged: (int v) => _s.pageSize = FxSettings.pageSizes[v],
        )),
      ],

      // ---------------- 账号 ----------------
      next(FxSectionTitle('账号', accent: cs.primary)),
      if (widget.loggedIn)
        next(FxRow(
          title: '退出登录',
          icon: Icons.logout,
          onTap: () => widget.onLogout(),
        ))
      else ...<Widget>[
        next(FxRow(
            title: '登录', icon: Icons.person_outline, onTap: widget.onLogin)),
        next(FxRow(title: '注册', icon: Icons.add, onTap: widget.onRegister)),
      ],

      // ---------------- 其他 ----------------
      next(FxSectionTitle('其他', accent: cs.primary)),
      next(FxRow(
        title: '清除缓存',
        subtitle: '清除网页缓存，不会退出登录',
        icon: Icons.delete_outline,
        onTap: () => widget.onClearCache(),
      )),
      next(FxRow(
        title: '检查更新',
        subtitle: '当前版本 ${widget.versionName}',
        icon: Icons.system_update_alt,
        onTap: () => widget.onCheckUpdate(),
      )),
      next(FxRow(
        title: '官网地址',
        subtitle: 'www.fxlovewall.me',
        icon: Icons.open_in_new,
        onTap: widget.onOpenSite,
      )),
      next(_buildAbout(cs)),
    ];

    return Container(
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: rows,
      ),
    );
  }

  /// 把当前半径映射到最接近的档位（用户可以从来路不同地改过它）。
  int _nearestRadiusStep() {
    final double r = _s.cornerRadius;
    int best = 0;
    double bd = double.infinity;
    for (int k = 0; k < FxSettings.radiusSteps.length; k++) {
      final double d = (FxSettings.radiusSteps[k] - r).abs();
      if (d < bd) {
        bd = d;
        best = k;
      }
    }
    return best;
  }

  /// 背景设置。需求 7：**去掉透明度滑块下面的背景图预览** —— 那张缩略图
  /// 在深色下会连带影响可读性，而且选完图在网页上立刻就看到了，不需要预览。
  Widget _buildBgControls(ColorScheme cs) {
    final bool has = _s.bgImageData.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: _pickBackground,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('选择图片'),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              opacity: has ? 1 : 0.4,
              duration: FxMotion.fast,
              child: OutlinedButton.icon(
                onPressed: has ? _removeBackground : null,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('移除图片'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            const Text('图片透明度', style: TextStyle(fontSize: 13)),
            Expanded(
              child: Slider(
                value: _s.bgOpacity,
                onChanged: (double v) => _s.bgOpacity = v,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${(_s.bgOpacity * 100).round()}%',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAbout(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, size: 22),
          const SizedBox(width: 14),
          const Expanded(child: Text('关于', style: TextStyle(fontSize: 15))),
          Text(widget.versionName,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Future<void> _pickBackground() async {
    try {
      final XFile? f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 82,
      );
      if (f == null) return;
      final Uint8List bytes = await f.readAsBytes();
      final String ext = f.path.split('.').last.toLowerCase();
      final String mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      _s.bgImageData = 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取图片失败：$e')),
        );
      }
    }
  }

  void _removeBackground() => _s.bgImageData = '';
}
