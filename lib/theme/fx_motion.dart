import 'package:flutter/animation.dart';

/// 全应用统一的动效参数。
///
/// 风格定为「Material 3 标准动效」：短时长、标准缓动、位移很小 —— 快而不飘，
/// 也就是需求里说的「优美利索」。所有动画都必须从这里取时长/曲线，
/// 不允许在页面里写魔法数字，否则几十处交互会各走各的节奏。
///
/// v1.1.0 起支持「动画控制」三档（[level]）：
///   0 = 全部   —— 原样，所有微动效都在
///   1 = 关键   —— 只保留页面级过渡，去掉按下缩放、错峰入场等装饰性动效
///   2 = 无动画 —— 全部时长归零，位移归零
///
/// 网页主题会把 level 强制成 2，因为那个模式下网页侧本来就零注入。
class FxMotion {
  FxMotion._();

  /// 当前动画档位：0=全部 1=关键 2=无动画。由 main.dart 依据设置写入。
  static int level = 0;

  /// 完全关闭动画。
  static bool get off => level >= 2;

  /// 只保留关键动效。
  static bool get keyOnly => level == 1;

  /// 装饰性动效（按下缩放、错峰入场、回弹）是否启用。
  static bool get decorative => level == 0;

  /// 按档位压缩时长。[key] 为 true 的是页面级过渡，在「关键」档下保留。
  static Duration _d(int ms, {bool key = false}) {
    if (off) return Duration.zero;
    if (keyOnly && !key) return Duration.zero;
    return Duration(milliseconds: ms);
  }

  // ------------------------------------------------------------------ 时长
  /// 按下/抬起、颜色变化等即时反馈。
  static Duration get micro => _d(120);

  /// 常规过渡：导航切换、分段控件、色块选中。
  static Duration get fast => _d(180);

  /// 页面级过渡：整页切换、主题切换。
  static Duration get medium => _d(240, key: true);

  /// 强调过渡：启动淡入、错误页出现。
  static Duration get slow => _d(320, key: true);

  /// 设置页错峰入场的总时长。
  static Duration get staggerTotal => _d(620);

  /// 刷新过渡（新旧页面交接）的总时长。
  static Duration get refresh => _d(1000, key: true);

  /// 启动页停留时长。
  static Duration get splashHold => _d(1500, key: true);

  // ------------------------------------------------------------------ 曲线
  /// 进场：快出慢停，最常用的「利索」手感。
  static const Curve enter = Curves.easeOutCubic;

  /// 双向过渡：起止都平滑。
  static const Curve move = Curves.easeInOutCubic;

  /// 退场：与 enter 反向。
  static const Curve exit = Curves.easeInCubic;

  /// 图标选中：轻微回弹，克制不夸张（幅度远小于 Curves.elasticOut）。
  static const Curve pop = Curves.easeOutBack;

  // ------------------------------------------------------------------ 位移量
  /// 页面切换时的位移距离。刻意很小 —— 大位移在频繁切换时会显得拖沓。
  static double get pageShift => decorative ? 8.0 : 0.0;

  /// 列表/卡片入场位移。
  static double get itemShift => decorative ? 12.0 : 0.0;

  /// 单个条目入场动画的间隔（stagger）。
  static Duration get stagger => _d(40);
}
