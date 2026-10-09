import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置。字段与旧 Kotlin 版的 SharedPreferences 一一对应，
/// 连 key 名都保持一致，方便日后从旧版迁移。
///
/// v1.1.0 新增三组：
///   · [webTheme]     「网页主题」——与「软件主题」互斥，网页侧零注入
///   · [motionLevel]  动画控制：全部 / 关键 / 无动画
///   · [cornerRadius] 圆角大小（默认 8px，比旧版的 16~20px 方得多）
class FxSettings extends ChangeNotifier {
  FxSettings._(this._prefs);

  final SharedPreferences _prefs;

  // ------------------------------------------------------------------ 常量

  /// 主题模式取值，顺序对应设置页的三段控件。
  static const List<String> themeModes = <String>['system', 'light', 'dark'];

  /// 每页帖子数；0 表示「全部」（关闭分页）。
  static const List<int> pageSizes = <int>[10, 20, 30, 50, 0];

  /// 字号档位：小 / 标准 / 大 / 特大。整体比 0.8.x 下调一档。
  static const List<double> fontScales = <double>[0.78, 0.90, 1.02, 1.15];

  /// 动画档位：0=全部 1=关键 2=无动画。
  static const List<String> motionModes = <String>['all', 'key', 'none'];

  static const int defaultFontStep = 1;
  static const int defaultPageSize = 10;
  static const int defaultMotionLevel = 0;

  /// 圆角默认值。需求原话是「默认应该更方一些」，所以取 8px。
  static const double defaultCornerRadius = 8.0;
  static const double minCornerRadius = 0.0;
  static const double maxCornerRadius = 20.0;

  /// 圆角滑块上的 5 个档位（对应设置页的分段控件）。
  static const List<double> radiusSteps = <double>[0, 4, 8, 12, 16];

  // ------------------------------------------------------------------ 读取

  static Future<FxSettings> load() async =>
      FxSettings._(await SharedPreferences.getInstance());

  // ------------------------------------------------------------------ 字段

  String get themeMode {
    final String v = _prefs.getString('themeMode') ?? 'system';
    return themeModes.contains(v) ? v : 'system';
  }

  set themeMode(String v) {
    _prefs.setString('themeMode', v);
    notifyListeners();
  }

  /// 「网页主题」开关。
  ///
  /// 打开后网页侧**一个字节都不注入**：站点自己的头部、搜索框、最新/最热标签
  /// 全部原样显示，只保留原生底部导航。外观设置也随之收窄到
  /// 「深浅色跟随系统」+「字号」两项。
  bool get webTheme => _prefs.getBool('webTheme') ?? false;

  set webTheme(bool v) {
    _prefs.setBool('webTheme', v);
    notifyListeners();
  }

  /// 网页主题下是否跟随系统深浅色。
  ///
  /// 站点本身没有深色模式，所以这一项控制的是**叠加给整个网页的深色滤镜**
  /// （见 [webDarkFilterCss]），而不是切换站点自己的配色。
  bool get webFollowSystem => _prefs.getBool('webFollowSystem') ?? true;

  set webFollowSystem(bool v) {
    _prefs.setBool('webFollowSystem', v);
    notifyListeners();
  }

  /// 启动页是否已经展示过（只首次显示，见 SplashPage）。
  bool get splashSeen => _prefs.getBool('splashSeen') ?? false;

  set splashSeen(bool v) {
    _prefs.setBool('splashSeen', v);
    // 刻意不 notifyListeners()：标记位变化不应该触发任何重建。
  }

  /// 新手引导是否已经走完（需求 4，只首次显示）。
  bool get onboardSeen => _prefs.getBool('onboardSeen') ?? false;

  set onboardSeen(bool v) {
    _prefs.setBool('onboardSeen', v);
    // 同上：纯标记位，不通知重建。
  }

  int get accentIndex =>
      (_prefs.getInt('accent') ?? 0).clamp(0, 7);

  set accentIndex(int v) {
    _prefs.setInt('accent', v);
    notifyListeners();
  }

  /// 背景图（data URI 形式，空字符串表示不使用）。
  /// 与旧版一样直接存 base64：选图时已用 image_picker 降采样过，
  /// 体积可控，且省掉一套文件生命周期管理。
  String get bgImageData => _prefs.getString('bgData') ?? '';

  set bgImageData(String v) {
    if (v.isEmpty) {
      _prefs.remove('bgData');
    } else {
      _prefs.setString('bgData', v);
    }
    notifyListeners();
  }

  double get bgOpacity => (_prefs.getDouble('bgOpacity') ?? 1.0).clamp(0.0, 1.0);

  set bgOpacity(double v) {
    _prefs.setDouble('bgOpacity', v.clamp(0.0, 1.0));
    notifyListeners();
  }

  int get fontStep => (_prefs.getInt('fontStep') ?? defaultFontStep).clamp(0, 3);

  set fontStep(int v) {
    _prefs.setInt('fontStep', v);
    notifyListeners();
  }

  int get pageSize {
    final int v = _prefs.getInt('pageSize') ?? defaultPageSize;
    return pageSizes.contains(v) ? v : defaultPageSize;
  }

  set pageSize(int v) {
    _prefs.setInt('pageSize', v);
    notifyListeners();
  }

  String get sort => (_prefs.getString('sort') == 'hot') ? 'hot' : 'latest';

  set sort(String v) {
    _prefs.setString('sort', v == 'hot' ? 'hot' : 'latest');
    notifyListeners();
  }

  /// 动画档位 0/1/2。网页主题强制 2（无动画）。
  int get motionLevel {
    if (webTheme) return 2;
    final int v = _prefs.getInt('motion') ?? defaultMotionLevel;
    return v.clamp(0, 2);
  }

  /// 用户在设置页选的那一档（网页主题下也如实反映，不受强制覆盖影响）。
  int get motionChoice =>
      (_prefs.getInt('motion') ?? defaultMotionLevel).clamp(0, 2);

  set motionChoice(int v) {
    _prefs.setInt('motion', v.clamp(0, 2));
    notifyListeners();
  }

  double get cornerRadius => (_prefs.getDouble('radius') ?? defaultCornerRadius)
      .clamp(minCornerRadius, maxCornerRadius);

  set cornerRadius(double v) {
    _prefs.setDouble('radius', v.clamp(minCornerRadius, maxCornerRadius));
    notifyListeners();
  }

  // ------------------------------------------------------------------ 派生

  double get fontScale => fontScales[fontStep];

  /// 背景图的原始字节（用于同时喂给 Flutter 原生侧和网页 CSS）。
  Uint8List? get bgBytes {
    final String d = bgImageData;
    final int comma = d.indexOf(',');
    if (d.isEmpty || comma < 0) {
      return null;
    }
    try {
      return base64Decode(d.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// 网页 CSS 用的背景片段。
  String get bgCss {
    if (bgImageData.isEmpty) {
      return '';
    }
    return ':root{--fx-bg:url("$bgImageData");'
        '--fx-bg-opacity:${bgOpacity.toStringAsFixed(2)};}';
  }

  /// 圆角片段。--fx-radius 交给 theme.css 里所有胶囊/卡片/输入框消费。
  String get radiusCss {
    final String r = cornerRadius.toStringAsFixed(1);
    final String small = (cornerRadius * 0.6).toStringAsFixed(1);
    return ':root{--fx-radius:${r}px;--fx-radius-sm:${small}px;}';
  }

  /// 网页字号片段。
  ///
  /// 旧实现在 theme.css 的若干选择器上算 `calc(14.5px * var(--fx-font))`，
  /// 只覆盖了 6 个类，用户点了「大 / 特大」几乎看不出变化，被反馈成
  /// 「点击没反应」。现在改成对整页做 zoom —— 文字、间距、控件同比例放大，
  /// 肉眼一定看得见，而且不用逐个选择器枚举。
  String get fontCss {
    final double f = fontScale;
    if ((f - 1.0).abs() < 0.001) {
      return '';
    }
    return 'html{zoom:${f.toStringAsFixed(3)} !important;}';
  }

  /// 「网页主题 + 跟随系统深色」时叠加给整个网页的深色滤镜。
  ///
  /// 站点本身没有深色模式（CSS 里 `dark` / `prefers-color-scheme` 各出现 0 次），
  /// 所以这里用反色 + 色相旋转 180° 把整页翻成深色；再对图片/视频做一次反向
  /// 处理，免得照片变成底片。
  ///
  /// ⚠️ 只在**网页主题**下使用。软件主题走的是注入 theme.css 那句话，
  /// 颜色是设计稿里的精确值，不是算法翻转出来的。
  String get webDarkFilterCss {
    if (!webTheme) {
      return '';
    }
    return '''
html.fx-web-dark{filter:invert(1) hue-rotate(180deg) !important;background:#12131a !important;}
html.fx-web-dark img,html.fx-web-dark video,html.fx-web-dark canvas,
html.fx-web-dark svg image,html.fx-web-dark iframe,
html.fx-web-dark [style*="background-image"]{
  filter:invert(1) hue-rotate(180deg) !important;
}
''';
  }
}
