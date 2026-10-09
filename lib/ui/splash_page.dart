import 'package:flutter/material.dart';

import '../theme/fx_motion.dart';

/// 启动页（需求 20）：1.5 秒，logo + 应用名 + 网址，然后平滑过渡进主界面。
///
/// 只在**首次启动**显示（由 FxSettings.splashSeen 记录）—— 需求原话是
/// 「1.5s 启动画面」，但每次冷启动都等 1.5 秒对常用用户是负担，
/// 所以确认后按「仅首次」实现。
///
/// logo 是纯矢量画的（圆角方块 + 对话气泡 + 心），不依赖任何图片资源：
/// 这样换主题色时会跟着变，也不用为各 DPI 准备一堆 PNG。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.onDone});

  /// 停留结束后的回调。由 main.dart 用来切到主界面。
  final VoidCallback? onDone;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: FxMotion.splashHold,
  );

  // logo：0 → 45% 弹入
  late final Animation<double> _logoA = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
  );
  // 应用名：15% → 60% 淡入上移
  late final Animation<double> _nameA = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.15, 0.60, curve: Curves.easeOutCubic),
  );
  // 网址：30% → 75% 淡入上移
  late final Animation<double> _urlA = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.30, 0.75, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (FxMotion.off) {
      // 无动画档：直接进主界面，不做停留
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call());
      return;
    }
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedBuilder(
              animation: _logoA,
              builder: (BuildContext context, _) {
                final double t = _logoA.value.clamp(0.0, 1.0);
                return Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.84 + 0.16 * t,
                    child: const _Logo(),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            _fadeUp(
              _nameA,
              Text(
                '复兴表白墙',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _fadeUp(
              _urlA,
              Text(
                'www.fxlovewall.me',
                style: TextStyle(
                  fontSize: 12.5,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 46),
            _fadeUp(
              _urlA,
              SizedBox(
                width: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 2.5,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fadeUp(Animation<double> a, Widget child) {
    return AnimatedBuilder(
      animation: a,
      builder: (BuildContext context, Widget? c) {
        final double t = a.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

/// 启动页 logo：直接用**软件自己的图标**（灰底 + FX BIAOBAI QIANG）。
///
/// 原来是手画的一个蓝色圆角方块 + 对话气泡，与桌面上的图标不一致 ——
/// 用户从桌面点进来看到的图标，和启动页里的是两样东西。
/// 现在读 Android 的 mipmap/ic_launcher，两处完全一致。
///
/// 为什么要给一圈浅灰底 + 圆角：ic_launcher.png 本身是方形的灰底图，
/// 直接贴上去在浅色背景下会看到生硬的直角边。包一层同色圆角既保留图标
/// 原样，又和启动页的观感统一。
class _Logo extends StatelessWidget {
  const _Logo();

  /// 见 android/app/src/main/res/values/colors.xml 的
  /// ic_launcher_background —— 与图标底色保持同一个值。
  static const Color _iconBg = Color(0xFFABABAD);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: _iconBg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/ic_launcher.png',
        width: 92,
        height: 92,
        fit: BoxFit.cover,
        // 图标缺失时退回一个中性占位，不让启动页崩掉或显示红叉
        errorBuilder: (BuildContext c, Object e, StackTrace? s) => const Icon(
          Icons.favorite,
          size: 42,
          color: Colors.white,
        ),
      ),
    );
  }
}
