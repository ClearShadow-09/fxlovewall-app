import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../state/fx_settings.dart';
import 'fx_colors.dart';

/// 依据主题模式 + 系统亮度解析出当前是否为深色。
///
/// 「网页主题」下不使用 [FxSettings.themeMode]，而是看
/// [FxSettings.webFollowSystem]：站点没有深色模式，所以那里的深色只是
/// 一层叠加滤镜，语义就是「跟不跟系统」。
bool resolveDark(FxSettings settings) {
  if (settings.webTheme) {
    if (!settings.webFollowSystem) {
      return false;
    }
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }
  switch (settings.themeMode) {
    case 'dark':
      return true;
    case 'light':
      return false;
    default:
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  }
}

/// 当前生效的圆角半径。
///
/// 半径存在 ThemeData.cardTheme.shape 里（唯一事实来源），控件通过这个函数读，
/// 就不必把 FxSettings 一路透传到每个叶子 widget。
double fxRadius(BuildContext context) {
  final ShapeBorder? s = Theme.of(context).cardTheme.shape;
  if (s is RoundedRectangleBorder) {
    final BorderRadius b = s.borderRadius.resolve(TextDirection.ltr);
    return b.topLeft.x;
  }
  return FxSettings.defaultCornerRadius;
}

/// 原生界面（侧边栏、设置页、按钮等）的字体栈。
///
/// ## 为什么要显式指定
///
/// 原来写的是 `Typography.material2021(platform: TargetPlatform.android)` ——
/// 也就是**硬编码**用 Android 的字体栈（Roboto）。在 Windows 上，Roboto
/// 没有中文字形，系统会退到某个默认字体，中文看起来又细又挤（用户反馈
/// 「本地的字体好丑」就是这个）。
///
/// ## 为什么按名字引用而不是打包字体
///
/// 微软雅黑是微软 + 方正的共同版权字体，**不允许随应用分发**；但它是
/// Windows 系统自带字体，用「按字体名引用」的方式调用完全合法。
/// 这样安装包也不会变大（这些字体动辄 17-19MB）。
///
/// 回退链覆盖了常见情况：
///   微软雅黑（Win 自带）→ 思源黑体（部分系统/用户自装）→ 等线（Win10+ 自带）
///   → PingFang SC（macOS）→ 系统中文字体兜底
///
/// 注意：**网页内容不受这里影响** —— theme.css 里已有自己的一套
/// font-family（同样以微软雅黑打头），那是给 WebView 用的。
const List<String> _fxFontFallback = <String>[
  'Microsoft YaHei UI', // 微软雅黑（UI 变体，优先，界面观感更好）
  'Microsoft YaHei',    // 微软雅黑
  'Noto Sans SC',       // 思源黑体（OFL，部分系统预装）
  'DengXian',           // 等线（Windows 10+ 自带）
  'PingFang SC',        // macOS
  'Hiragino Sans GB',   // macOS 旧版
  'Source Han Sans SC', // 思源黑体另一名
  'WenQuanYi Micro Hei',// Linux
  'sans-serif',
];

/// 依据当前平台选字体栈与排版基准。
///
/// 桌面端用 [TargetPlatform.windows] 的排版基准（字号/行高更贴合桌面），
/// 移动端保持原来的 android。
TargetPlatform _fxTypePlatform() {
  if (kIsWeb) return TargetPlatform.android;
  if (Platform.isWindows) return TargetPlatform.windows;
  if (Platform.isMacOS) return TargetPlatform.macOS;
  if (Platform.isLinux) return TargetPlatform.linux;
  return TargetPlatform.android;
}

/// 构建 Material 3 主题。
///
/// 刻意不使用 ColorScheme.fromSeed 派生整套色 —— 旧 Kotlin 版的色值是精确指定的
/// （primary #6750A4、卡片 #E8DEF8…），派生出来的会漂移。这里直接给定关键色。
class FxTheme {
  FxTheme._();

  static ThemeData light(FxSettings s) => _build(s, false);
  static ThemeData dark(FxSettings s) => _build(s, true);

  static ThemeData _build(FxSettings s, bool dark) {
    final FxTokens t = FxTokens.of(dark);
    final Color primary = FxColors.primary(s.accentIndex, dark);
    final Color onPrimary = FxColors.onPrimary(s.accentIndex, dark);
    final Color container = FxColors.container(s.accentIndex, dark);
    final Color onContainer = FxColors.onContainer(s.accentIndex, dark);

    // 圆角：需求原话「默认应该更方一些」，默认 8px，可由设置页调整。
    final double r = s.cornerRadius;
    final BorderRadius radius = BorderRadius.circular(r);
    final BorderRadius radiusSmall = BorderRadius.circular(r * 0.6);

    final ColorScheme scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
      secondary: primary,
      onSecondary: onPrimary,
      secondaryContainer: container,
      onSecondaryContainer: onContainer,
      error: t.error,
      onError: dark ? const Color(0xFF601410) : Colors.white,
      surface: t.surface,
      onSurface: t.onSurface,
      surfaceContainerLowest: dark ? const Color(0xFF0F0D13) : Colors.white,
      surfaceContainerLow: t.surfaceContainer,
      surfaceContainer: t.surfaceContainer,
      surfaceContainerHigh: t.surfaceContainerHigh,
      surfaceContainerHighest: t.surfaceContainerHighest,
      onSurfaceVariant: t.onSurfaceVariant,
      outline: t.outline,
      outlineVariant: t.outlineVariant,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: t.onSurface,
      onInverseSurface: t.surface,
      inversePrimary: container,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.surface,
      canvasColor: t.surface,
      splashFactory: InkSparkle.splashFactory,
      // 全局字体回退链。
      //
      // ⚠️ 这一条比 textTheme 里那套更重要：项目里有 40 多处内联的
      // `TextStyle(fontSize: ...)`，它们**不经过 textTheme**，只靠
      // textTheme.apply 是覆盖不到的。ThemeData.fontFamilyFallback 会作用到
      // 所有经由 Theme 解析的默认文字样式，是唯一能一次管住全场的开关。
      fontFamilyFallback: _fxFontFallback,
      // 动效统一走 FxMotion 的节奏
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      // 字体：按平台选排版基准，再统一挂上中文字体回退链。
      //
      // ⚠️ 不要再用硬编码的 TargetPlatform.android（原来就是那样，
      // Windows 上中文因此很难看，见文件顶部 _fxFontFallback 的说明）。
      textTheme: Typography.material2021(platform: _fxTypePlatform())
          .black
          .apply(
            bodyColor: t.onSurface,
            displayColor: t.onSurface,
            fontFamilyFallback: _fxFontFallback,
          ),
      dividerColor: t.outlineVariant,
      cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: radius)),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: radius)),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
        backgroundColor: t.onSurface,
        contentTextStyle: TextStyle(fontSize: 13, color: t.surface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radiusSmall)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radiusSmall)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radiusSmall)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
      ),
    );
  }
}
