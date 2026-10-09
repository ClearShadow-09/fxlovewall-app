import 'package:flutter/material.dart';

import '../state/fx_settings.dart';
import '../theme/fx_motion.dart';
import '../theme/fx_theme.dart';
import 'widgets/fx_widgets.dart';

/// 首次启动的新手引导（需求 4）。
///
/// 5 步：欢迎 → 软件/网页主题 → 主题色 → 字号 → 圆角 + 动画。
/// 每项设置都是**即时生效**的 —— 用户在选择时就能看到整页配色/字号跟着变，
/// 而不是「先选完再一起应用」。这也是把 onChanged 直接接到 FxSettings 的原因：
/// FxSettings 一 notify，整个 MaterialApp 立刻重建。
///
/// 可以跳过：右上角「跳过」直接写入 splashSeen/onboardSeen 标记进主界面。
/// 只走一次：由 FxSettings.onboardSeen 控制（见 main.dart 的 _Bootstrap）。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.settings, required this.onDone});

  final FxSettings settings;
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int _lastStep = 4;

  /// 只在「软件主题」下才问主题色/圆角/动画 —— 网页主题是一个字节都不注入的，
  /// 那些设置在那边没有落点，问了反而误导（与设置页的收窄规则保持一致）。
  int _step = 0;
  final PageController _pager = PageController();

  FxSettings get _s => widget.settings;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() => _step = step.clamp(0, _lastStep));
    _pager.animateToPage(
      _step,
      duration: FxMotion.medium,
      curve: FxMotion.move,
    );
  }

  void _finish() {
    _s.onboardSeen = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // ---- 顶部：进度点 + 跳过 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i <= _lastStep; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: FxMotion.fast,
                      curve: FxMotion.enter,
                      width: i == _step ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i <= _step ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: Text(
                      '跳过',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            // ---- 主体：分页 ----
            Expanded(
              child: PageView(
                controller: _pager,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (int i) => setState(() => _step = i),
                children: <Widget>[
                  _welcome(cs),
                  _themeMode(cs),
                  _accent(cs),
                  _font(cs),
                  _shape(cs),
                ],
              ),
            ),

            // ---- 底部：上一步 / 下一步 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(
                children: <Widget>[
                  if (_step > 0)
                    TextButton(
                      onPressed: () => _go(_step - 1),
                      child: const Text('上一步'),
                    ),
                  const Spacer(),
                  if (_step < _lastStep)
                    FilledButton(
                      onPressed: () => _go(_step + 1),
                      child: const Text('下一步'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('开始使用'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 各步骤

  Widget _stepBody(String title, String desc, List<Widget> children) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      children: <Widget>[
        Text(title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          desc,
          style: TextStyle(fontSize: 13, height: 1.6, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }

  Widget _welcome(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 用软件自己的图标（灰底那张），而不是手画的蓝色方块。
            // 与启动页、桌面图标三处保持一致 —— 用户从桌面点进来、
            // 看启动页、再看到引导页，看到的应该是同一个 logo。
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFFABABAD),
                borderRadius: BorderRadius.circular(19),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/ic_launcher.png',
                width: 78,
                height: 78,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    Icon(Icons.favorite, size: 34, color: cs.onPrimary),
              ),
            ),
            const SizedBox(height: 20),
            const Text('欢迎使用复兴表白墙',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              '接下来花 20 秒做几个外观设置，\n选好之后随时可以在「设置」里改。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.7, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeMode(ColorScheme cs) {
    return _stepBody(
      '选择界面风格',
      '「软件主题」会重绘网页界面（隐藏站点头部、卡片圆角化）；'
          '「网页主题」原样显示站点，只保留底部导航。',
      <Widget>[
        FxSegmented(
          labels: const <String>['软件主题', '网页主题'],
          selected: _s.webTheme ? 1 : 0,
          onChanged: (int i) => _s.webTheme = (i == 1),
        ),
        const SizedBox(height: 18),
        if (!_s.webTheme) ...<Widget>[
          const FxLabel('主题模式'),
          FxSegmented(
            labels: const <String>['跟随系统', '浅色', '深色'],
            selected: !FxSettings.themeModes.contains(_s.themeMode)
                ? 0
                : FxSettings.themeModes.indexOf(_s.themeMode),
            onChanged: (int i) => _s.themeMode = FxSettings.themeModes[i],
          ),
        ] else ...<Widget>[
          FxSwitchRow(
            title: '跟随系统深浅色',
            subtitle: '站点没有深色模式，开启后由软件叠加一层深色滤镜',
            value: _s.webFollowSystem,
            onChanged: (bool v) => _s.webFollowSystem = v,
          ),
        ],
      ],
    );
  }

  Widget _accent(ColorScheme cs) {
    return _stepBody(
      '挑一个主题色',
      '链接、按钮、图标和选中态都会用这个颜色。',
      <Widget>[
        FxSwatches(
          selected: _s.accentIndex,
          onChanged: (int i) => _s.accentIndex = i,
        ),
        const SizedBox(height: 22),
        // 即时预览：让用户直接看到这一色在真实控件上的样子
        Row(
          children: <Widget>[
            FilledButton(onPressed: () {}, child: const Text('主要按钮')),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: () {}, child: const Text('次要按钮')),
          ],
        ),
      ],
    );
  }

  Widget _font(ColorScheme cs) {
    return _stepBody(
      '设置字号',
      '软件界面和网页文字会一起变化，下面就是实际大小。',
      <Widget>[
        FxSegmented(
          labels: const <String>['小', '标准', '大', '特大'],
          selected: _s.fontStep,
          onChanged: (int i) => _s.fontStep = i,
        ),
        const SizedBox(height: 22),
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(fxRadius(context)),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '示例：捞捞今天复兴集市做在中间的女生呀，好漂亮好温柔啊。',
              style: TextStyle(fontSize: 14.5, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _shape(ColorScheme cs) {
    return _stepBody(
      '圆角与动画',
      '圆角默认更方一些（8px）。动画可以按需减少，省电也更利索。',
      <Widget>[
        const FxLabel('圆角'),
        FxSegmented(
          labels: const <String>['直角', '较小', '默认', '较大', '大'],
          selected: _nearestRadiusStep(),
          onChanged: (int i) => _s.cornerRadius = FxSettings.radiusSteps[i],
        ),
        const SizedBox(height: 18),
        const FxLabel('动画'),
        FxSegmented(
          labels: const <String>['全部', '关键', '无动画'],
          selected: _s.motionChoice,
          onChanged: (int i) => _s.motionChoice = i,
        ),
      ],
    );
  }

  int _nearestRadiusStep() {
    int best = 0;
    double bd = double.infinity;
    for (int k = 0; k < FxSettings.radiusSteps.length; k++) {
      final double d = (FxSettings.radiusSteps[k] - _s.cornerRadius).abs();
      if (d < bd) {
        bd = d;
        best = k;
      }
    }
    return best;
  }
}
