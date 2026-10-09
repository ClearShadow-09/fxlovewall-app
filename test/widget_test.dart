import 'package:flutter_test/flutter_test.dart';
import 'package:fxwall/theme/fx_colors.dart';

void main() {
  test('主题色 CSS 输出格式与旧 Kotlin 版一致', () {
    final String css = FxColors.accentCss(0);
    // 默认蓝 #315efb
    expect(css.contains('--fx-primary:#315efb'), isTrue);
    expect(css.contains('html.fx-dark{'), isTrue);
    // 亮/暗各一套，共 2 次 --fx-primary:<色值>。
    // 注意用带冒号的模式：--fx-primary-rgb 里也含 "--fx-primary" 子串，
    // 直接匹配裸变量名会数成 4 个。
    expect('--fx-primary:'.allMatches(css).length, 2);
    // 卡片底色由 RGB 分量派生，明暗各一份
    expect('--fx-primary-rgb:'.allMatches(css).length, 2);
  });

  test('色值混合与 Kotlin 的 Blend 同系数', () {
    // blend(0xFEF7FF, base=0x315EFB, 0.13) 应得到浅蓝容器色，
    // 与旧版 AccentPalette 的输出逐字符一致
    final String css = FxColors.accentCss(0);
    expect(css.contains('--fx-container:#e3e3fe'), isTrue);
  });

  test('暗色变体按系数提亮', () {
    final String css = FxColors.accentCss(0);
    // lighten(#315EFB, 0.35) = #7996fc
    expect(css.contains('--fx-primary:#7996fc'), isTrue);
  });
}
