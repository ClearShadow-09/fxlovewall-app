import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/fx_settings.dart';
import 'theme/fx_colors.dart';
import 'theme/fx_motion.dart';
import 'theme/fx_theme.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_page.dart';
import 'ui/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FxSettings settings = await FxSettings.load();
  // 动画档位在整棵树构建之前就要定下来 —— FxMotion 的时长是全局静态的，
  // 一旦有控件在写死 level 之前建成，那一帧就会用错节奏。
  FxMotion.level = settings.motionLevel;
  runApp(FxWallApp(settings: settings));
}

class FxWallApp extends StatelessWidget {
  const FxWallApp({super.key, required this.settings});

  final FxSettings settings;

  @override
  Widget build(BuildContext context) {
    // 设置变更（主题模式 / 主题色 / 圆角 / 字号 / 动画 / 网页主题）要立刻重建整棵树
    return AnimatedBuilder(
      animation: settings,
      builder: (BuildContext context, _) {
        FxMotion.level = settings.motionLevel;

        final bool dark = resolveDark(settings);
        final FxTokens tokens = FxTokens.of(dark);
        // 状态栏跟随主题，与旧版一致（亮色=深色图标，深色=浅色图标）
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: tokens.surface,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: tokens.surfaceContainer,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          ),
        );
        return MaterialApp(
          title: '复兴表白墙',
          debugShowCheckedModeBanner: false,
          theme: FxTheme.light(settings),
          darkTheme: FxTheme.dark(settings),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (BuildContext context, Widget? child) {
            // 字号：整个原生界面按设置缩放。
            //
            // 这是「字号缩放点了没反应」的正解 —— 旧实现只往网页里注入
            // 6 个选择器的 calc()，用户在设置页点「大 / 特大」时眼前
            // 一个字都不会变，所以反馈成「没反应」。现在设置页自己也会跟着缩放。
            //
            // 网页那边由 FxSettings.fontCss 用 zoom 单独负责，两者互不叠加。
            final MediaQueryData mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(settings.fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _Bootstrap(settings: settings),
        );
      },
    );
  }
}

/// 启动页 → 主界面的交接。
///
/// 用 AnimatedSwitcher 做一次淡入淡出：启动页整体淡出、主界面淡入，
/// 而不是硬切（需求 20 的「平滑过渡」）。
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.settings});

  final FxSettings settings;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  // 启动顺序：启动页 → 新手引导（仅首次）→ 主界面。
  //
  // 需求变更（item 3）：启动页**每次开软件都显示**，不再受 splashSeen 限制。
  // 它是应用身份的一部分（logo + 名称 + 网址 + 进度），每次冷启动给用户一个
  // 明确的「正在启动」反馈，比直接闪进主界面更稳。
  // 新手引导仍然只看 onboardSeen —— 那个是配置向导，只该出现一次。
  //
  // 注意：进程还活着时切回来（热启动）不会重建 _Bootstrap，所以不会重复播放，
  // 只有真正冷启动才会看到。
  bool _showSplash = true;
  bool _showOnboarding = false;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return AnimatedSwitcher(
        duration: FxMotion.slow,
        switchInCurve: FxMotion.enter,
        switchOutCurve: FxMotion.exit,
        child: SplashPage(
          key: const ValueKey<String>('splash'),
          onDone: () {
            // 仍然记下标记位（供别处判断是否初次安装），但不再用它决定是否播放
            widget.settings.splashSeen = true;
            if (!mounted) return;
            setState(() {
              _showSplash = false;
              // 首次安装：启动页看完接着走新手引导
              _showOnboarding = !widget.settings.onboardSeen;
            });
          },
        ),
      );
    }
    if (_showOnboarding) {
      return AnimatedSwitcher(
        duration: FxMotion.medium,
        switchInCurve: FxMotion.enter,
        switchOutCurve: FxMotion.exit,
        child: OnboardingPage(
          key: const ValueKey<String>('onboarding'),
          settings: widget.settings,
          onDone: () {
            if (mounted) setState(() => _showOnboarding = false);
          },
        ),
      );
    }
    return HomeShell(settings: widget.settings);
  }
}
