import 'package:flutter/services.dart';

/// 读取打包进 assets 的注入资源。
///
/// 这三个文件由 build_apk.ps1 从 `..\app\res\raw\` 复制而来，是全平台唯一的事实
/// 来源 —— 旧 Kotlin 版和 node 测试读的都是同一份，改一次两端同时生效。
class FxWebAssets {
  FxWebAssets._();

  static String? _themeCss;
  static String? _pagerJs;
  static String? _layoutFixJs;

  static Future<String> themeCss() async =>
      _themeCss ??= await rootBundle.loadString('assets/theme.css');

  static Future<String> pagerJs() async =>
      _pagerJs ??= await rootBundle.loadString('assets/pager.js');

  static Future<String> layoutFixJs() async =>
      _layoutFixJs ??= await rootBundle.loadString('assets/layout_fix.js');

  /// 把分页脚本里的每页条数占位符换成真实值（与旧版同一套替换）。
  static Future<String> pagerJsFor(int pageSize) async =>
      (await pagerJs()).replaceFirst('__PER__', '$pageSize');
}
