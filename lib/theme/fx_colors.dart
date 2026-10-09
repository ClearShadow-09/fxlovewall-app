import 'dart:ui';

/// Material 3 色板 + 主题色推导。
///
/// 这里的 blend / lighten / darken 与 AccentCss 的输出格式，严格照搬旧 Kotlin 版
/// MainActivity / AccentPalette 的同一套系数，保证两个版本的网页配色完全一致。
class FxColors {
  FxColors._();

  /// 主题色候选。默认蓝色 = 站点原生链接色。
  static const List<Color> accents = <Color>[
    Color(0xFF315EFB), // 蓝（默认）
    Color(0xFF6750A4), // 紫罗兰（原设计稿主色）
    Color(0xFFE53935), // 红
    Color(0xFFD81B60), // 粉
    Color(0xFFF57C00), // 橙
    Color(0xFF2E7D32), // 绿
    Color(0xFF00838F), // 青
    Color(0xFFF9A825), // 琥珀
  ];

  static const int defaultAccentIndex = 0;

  static Color base(int index) =>
      accents[index.clamp(0, accents.length - 1)];

  /// 按比例把 [c] 向 [toward] 混合（与 Kotlin 的 AccentPalette.Blend 同系数）。
  static Color blend(Color c, Color toward, double ratio) {
    int ch(double a, double b) => (a * (1 - ratio) + b * ratio).round();
    return Color.fromARGB(
      255,
      ch(c.r * 255, toward.r * 255),
      ch(c.g * 255, toward.g * 255),
      ch(c.b * 255, toward.b * 255),
    );
  }

  static Color lighten(Color c, double f) => blend(c, const Color(0xFFFFFFFF), f);
  static Color darken(Color c, double f) => blend(c, const Color(0xFF000000), f);

  // --------------------------------------------------------------- 主题色派生

  /// 当前生效的主色（按明暗取亮色/暗色变体）。
  static Color primary(int index, bool dark) =>
      dark ? lighten(base(index), 0.35) : base(index);

  static Color onPrimary(int index, bool dark) =>
      dark ? darken(base(index), 0.55) : const Color(0xFFFFFFFF);

  /// 卡片 / 标签 chip / 导航激活底使用的容器色。
  static Color container(int index, bool dark) => dark
      ? blend(const Color(0xFF141218), base(index), 0.24)
      : blend(const Color(0xFFFEF7FF), base(index), 0.13);

  static Color onContainer(int index, bool dark) => dark
      ? lighten(base(index), 0.5)
      : darken(base(index), 0.4);

  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// "r, g, b" 三段（逗号分隔），供 CSS 的 `rgba(var(--x), .18)` 使用。
  ///
  /// ⚠️ **必须是逗号分隔，不能是空格分隔。**
  /// `rgba()` 是 CSS Color 3 的老语法，它的通道只吃逗号分隔的数字。
  /// 空格分隔（`49 94 251`）是 CSS Color 4 里 `rgb()` 的新写法，在
  /// `var()` 替换进 `rgba()` 之后，Chromium 会判定整条声明非法并**直接丢弃**
  /// —— 表现就是背景完全没画上去（不是回落到默认值，而是这条声明不存在）。
  ///
  /// 这个坑在模拟器上实测过：变量值明明是对的
  /// （`--fx-card-bg = rgba(49 94 251, .18)`），但探针元素的
  /// `backgroundColor` 是 `rgba(0,0,0,0)`，说明整条声明被丢弃了。
  static String rgbTriplet(Color c) {
    final int argb = c.toARGB32();
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    return '$r, $g, $b';
  }

  /// 生成覆盖 CSS 变量的样式片段，逐字符对齐旧 Kotlin 版的输出格式。
  static String accentCss(int index) {
    final Color b = base(index);
    final String lp = hex(b);
    const String lon = '#ffffff';
    final String lc = hex(blend(const Color(0xFFFEF7FF), b, 0.13));
    final String loc = hex(darken(b, 0.4));
    final String dp = hex(lighten(b, 0.35));
    final String don = hex(darken(b, 0.55));
    final String dc = hex(blend(const Color(0xFF141218), b, 0.24));
    final String doc = hex(lighten(b, 0.5));

    // --fx-primary-rgb：亮色用本色，深色用提亮后的那个（与 --fx-primary 一致），
    // 这样卡片底色的色相在任何模式下都跟着主题色走。
    final String lrgb = rgbTriplet(b);
    final String drgb = rgbTriplet(lighten(b, 0.35));

    return ':root{--fx-primary:$lp;--fx-on-primary:$lon;'
        '--fx-container:$lc;--fx-on-container:$loc;'
        '--fx-primary-rgb:$lrgb;}'
        'html.fx-dark{--fx-primary:$dp;--fx-on-primary:$don;'
        '--fx-container:$dc;--fx-on-container:$doc;'
        '--fx-primary-rgb:$drgb;}';
  }
}

/// 亮/暗两套中性色 token，取值与 Kotlin 版 res/values/colors.xml、
/// values-night/colors.xml 一一对应。
class FxTokens {
  const FxTokens({
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.error,
  });

  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color error;

  // ⚠️ 这套中性色原先直接照搬 Material 3 baseline（surface #FEF7FF、
  // container #F3EDF7…）。M3 baseline 的中性色其实**带紫调** —— 那是
  // 从默认紫色种子推导出来的。于是无论用户选什么主题色，原生界面
  // （设置页、我的、底部导航背景）永远泛着淡紫，用户反馈「一直是紫色」。
  // 现在改成真正的中性灰白：色相交给主题色去表达，中性层不掺紫。
  static const FxTokens light = FxTokens(
    surface: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF4F5F7),
    surfaceContainerHigh: Color(0xFFECEEF1),
    surfaceContainerHighest: Color(0xFFE2E5EA),
    onSurface: Color(0xFF1A1C1E),
    onSurfaceVariant: Color(0xFF45474C),
    outline: Color(0xFF75777C),
    outlineVariant: Color(0xFFC6C8CD),
    error: Color(0xFFB3261E),
  );

  static const FxTokens dark = FxTokens(
    surface: Color(0xFF141518),
    surfaceContainer: Color(0xFF1C1F24),
    surfaceContainerHigh: Color(0xFF24272D),
    surfaceContainerHighest: Color(0xFF2E323A),
    onSurface: Color(0xFFE3E4E8),
    onSurfaceVariant: Color(0xFFC6C8CD),
    outline: Color(0xFF8F9196),
    outlineVariant: Color(0xFF464A50),
    error: Color(0xFFF2B8B5),
  );

  static FxTokens of(bool dark) => dark ? FxTokens.dark : FxTokens.light;
}
