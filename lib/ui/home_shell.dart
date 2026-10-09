import 'dart:async';
import 'dart:collection';
import 'dart:convert' show utf8;
import 'dart:io' show Directory, File, FileMode, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zikzak_inappwebview/zikzak_inappwebview.dart';

import '../state/fx_settings.dart';
import '../theme/fx_motion.dart';
import '../update/fx_update.dart';
import '../web/fx_bridge.dart';
import '../web/fx_lucky.dart';
import 'mine_page.dart';
import 'other_page.dart';
import 'settings_page.dart';
import 'widgets/fx_bottom_nav.dart';
import 'widgets/fx_side_rail.dart';
import 'widgets/fx_top_bar.dart';
import 'widgets/fx_update_dialog.dart';

/// 原生通道统一走 `kDeviceChannel`（定义在 update/fx_update.dart，名字是
/// `com.fxlovewall.app/device`，与 MainActivity.kt 里注册的一致）。
///
/// ⚠️ 这里曾经另外声明了一个 `com.fxlovewall.app/cache` 的通道 —— 通道名
/// 对不上，所有调用都抛 MissingPluginException 并被 catch 吞掉，
/// 「清除缓存」因此静默失效。不要在这里再声明第二个通道常量。

/// 卡片底色诊断开关�?
///
/// 排查「卡片主题色底不生效」时打开，把 WebView 里真正算出来�?
/// computedStyle / 像素结果打到 logcat（debugPrint �?logcat）�?
/// 该问题已定位并改�?layout_fix.js 内联上色（见 theme.css �?
/// layout_fix.js �?paintCards 的注释），所以这里保持关闭�?
/// 以后再遇到「注入的样式不生效」可以直接改�?true 复用它�?
const bool kDebugCardProbe = false;

/// 是否启用「原生坐标判定分享」这条兜底路径�?
///
/// 默认 **false**：网页里�?JS 拦截器（bindShareForms）在桥修好后能正常工作，
/// 再叠一层原生判定会让同一次点击触发两次（实测会把剪贴板写乱）�?
///
/// 留这个开关是为了将来某个平台�?JS 桥又失效时能立刻切回�?—�?
/// 实现�?`_maybeShareAt`（已实测可用，只是当前不需要）�?
const bool kUseNativeShareFallback = false;
/// 桌面端判定�?
///
/// �?`Platform.isWindows/isLinux/isMacOS` 而不是「屏幕宽�?> x」：
/// 安卓平板横屏虽然宽，但用户手里是触摸设备，底部导航更顺手�?
/// 桌面窗口就算被拖得很窄，鼠标点侧栏也比点底栏自然�?
/// 这是「按输入方式分流」而不是「按尺寸分流」�?
bool get _isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

/// 主壳：导�?+ 网页�?+ 三个原生页�?
///
/// 与旧 Kotlin 版的结构一一对应�?
///   · 网页层常驻在树上（绝不重建，否则 WebView 会丢状态、重新加载）
///   · 原生页以覆盖层的形式淡入到网页之�?
///   · 搜索栏与筛选胶囊只在首页信息流出现
///
/// 安卓端用底部导航；Windows / macOS / Linux 端把同一组导航项搬到
/// **可折叠侧边栏**�?00px 展开 / 64px 收起）。两种壳共用这一份状态与
/// 业务逻辑，只有「导航摆在哪」不�?—�?�?[_buildBottomNav] �?
/// [_buildSideRail] 的注释�?
///
/// ⚠️ v1.1.0 修的关键 bug（需�?13）：
///   旧实现用 `_isWebTab = _tab=='home' || _tab=='post'` 决定「原生覆盖层要不�?
///   让开」。于是从「我的」点「我的帖子」时，`_navigate('/my-posts')` 把网�?
///   加载出来了，�?`_tab` 仍然。'mine'，覆盖层继续压在 WebView 上面 —�?
///   页面**加载成功了，只是永远看不�?*，表现就是「点了没反应」�?
///   更糟的是 `_syncNav('/my-posts')` 又把 `_tab` 映射。'mine'，自己把自己按住�?
///
///   现在拆成两个独立的量�?
///     _tab       只管底部导航高亮（和网页路径解耦）
///     _webFront  只管「现在最上面是网页还是原生页�?
///   从原生页打开网页 = `_openWeb()`，它只翻 `_webFront`，不动高亮�?
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.settings});

  final FxSettings settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const String _host = 'www.fxlovewall.me';
  static const String _base = 'https://$_host';

  static const List<FxNavItem> _navItems = <FxNavItem>[
    FxNavItem(icon: Icons.home_outlined, label: '首页'),
    FxNavItem(icon: Icons.person_outline, label: '我的'),
    FxNavItem(icon: Icons.add, label: '发帖'),
    FxNavItem(icon: Icons.grid_view_outlined, label: '其他'),
    FxNavItem(icon: Icons.settings_outlined, label: '设置'),
  ];

  static const List<String> _tabs = <String>[
    'home', 'mine', 'post', 'other', 'settings'
  ];

  /// 侧边栏用的导航项（与 _navItems 同一组语义，只是布局不同）�?
  static const List<FxRailItem> _railItems = <FxRailItem>[
    FxRailItem(icon: Icons.home_outlined, label: '首页'),
    FxRailItem(icon: Icons.person_outline, label: '我的'),
    FxRailItem(icon: Icons.add, label: '发帖'),
    FxRailItem(icon: Icons.grid_view_outlined, label: '其他'),
    FxRailItem(icon: Icons.settings_outlined, label: '设置'),
  ];

  /// 这三个是原生页，其余走网页�?
  static const List<String> _nativeTabs = <String>['mine', 'other', 'settings'];

  late final FxBridge _bridge;
  InAppWebViewController? _web;

  String _tab = 'home';
  String _path = '/';
  String _query = '';
  bool _loggedIn = false;
  bool _loading = false;
  bool _failed = false;
  double _progress = 0;

  /// 网页层是否在最上面。false = 原生页覆盖着�?
  bool _webFront = true;

  // 上滑刷新（观察式：不改动 WebView 的手势处理）
  bool _atTop = true;
  double _pullStart = 0;
  double _pull = 0;

  /// 本次按下的起点与「是否移动过」，用于区分点击与滑动（分享判定用）�?
  Offset? _tapStart;
  bool _tapMoved = false;

  // 刷新过渡遮罩
  double _cover = 0;
  Duration _coverDur = FxMotion.fast;
  DateTime _coverStart = DateTime.now();
  int _coverMinMs = 0;
  bool _coverOverlay = false;
  Timer? _coverSafety;

  // 滚动位置
  double _lastY = 0;
  String _lastUrlKey = '';
  double? _pendingRestoreY;
  bool _forceTopOnLoad = false;
  bool _userRefresh = false;

  /// 首页信息流的滚动位置。在「首�?�?帖子详情」时记下，供返回时还原�?
  /// �?-1 表示「没有待还原的位置」，�?null 写起来顺�?
  double _savedHomeY = -1;

  // 二次返回退�?
  DateTime? _lastBackAt;

  String? _pagerText;

  /// 今日幸运物品抽到的文字（需�?2）。null = 还没抽过，显示默认文案�?
  String? _luckyText;

  /// 正在抽取（防连点）�?
  bool _luckyBusy = false;

  /// 启动时的静默更新检查只跑一次�?
  bool _updateChecked = false;

  /// 桌面端侧边栏是否收起（只显示图标）。默认展开，让首次使用者看得到文字�?
  bool _railCollapsed = false;

  /// 桌面端注入兜底用的轮询计时器（见 [_startDesktopPoll]）�?
  Timer? _desktopPoll;

  /// 桌面端：当前这一页是否已经注入过�?
  bool _desktopInjected = false;

  /// 上一次弹出「请先登录」的时间，用于防连点�?
  DateTime? _lastLoginPrompt;

  /// 当前版本号（原生读出，主要给设置页和更新检查用）�?
  FxAppVersion _version = FxAppVersion.unknown;

  FxSettings get _s => widget.settings;

  /// 顶部搜索栏只�?*软件主题**的首页信息流显示�?
  /// 网页主题下站点自带头部与搜索框，再叠一个就重复了�?
  bool get _showTopBar =>
      !_s.webTheme && _webFront && _tab == 'home' && _path == '/';

  @override
  void initState() {
    super.initState();
    _bridge = FxBridge(settings: _s, onEvent: _onWebEvent);
    _s.addListener(_onSettingsChanged);
    // 需�?7：启动时静默检查一次更新。延�?3 秒，别和首屏渲染抢时间；
    // 检查失败（没网 / 未配置仓库）完全不打扰用户�?
    unawaited(_loadVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(seconds: 3), () => unawaited(_checkUpdate(silent: true)));
    });
  }

  /// 读当前版本号（原�?packageManager）。失败保持「未知」，不影响其它功能�?
  Future<void> _loadVersion() async {
    final FxAppVersion v = await FxAppVersion.read();
    if (mounted) setState(() => _version = v);
  }

  /// 需�?7：查 GitHub 最�?release�?
  ///
  /// [silent] = true（启动时）：只有**确实有新版本**才弹层，其余情况静默�?
  /// [silent] = false（用户点「检查更新」）：无论结果都给他一个反馈�?
  Future<void> _checkUpdate({required bool silent}) async {
    if (_updateChecked && silent) return;
    _updateChecked = true;

    if (silent) {
      final FxUpdateResult r = await FxUpdate.check();
      if (!mounted) return;
      if (r.status == FxUpdateStatus.available && r.release != null) {
        await FxUpdateDialog.show(context, r.release!);
      }
      return;
    }

    // 手动检查：给个「正在检查」的即时反馈，避免用户以为没反应
    _toast('正在检查更新…');
    final FxUpdateResult r = await FxUpdate.check();
    if (!mounted) return;
    if (r.status == FxUpdateStatus.available && r.release != null) {
      await FxUpdateDialog.show(context, r.release!);
    } else {
      showUpdateToast(context, r);
    }
  }

  Future<void> _checkUpdateManual() => _checkUpdate(silent: false);

  @override
  void dispose() {
    _coverSafety?.cancel();
    _desktopPoll?.cancel();
    _s.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    // 主题�?/ 字号 / 背景 / 圆角 / 动画 / 每页条数 / 网页主题变了
    // �?重新注入并刷新原生界�?
    if (mounted) setState(() {});
    _inject();
  }

  // ---------------------------------------------------------------- 网页事件

  void _onWebEvent(FxWebEvent e) {
    switch (e.type) {
      case 'pager':
        if (!mounted) return;
        setState(() {
          _pagerText = (e.text ?? '').isEmpty ? null : e.text;
        });
      case 'nav':
        if (e.path != null) _syncNav(e.path!);
      case 'lucky':
        // 幸运物品已改�?Flutter 原生直连（见 _luckyItem），这条保留兼容旧注�?
        _applyLuckyCompat(e.ok ?? false, e.text ?? '');
      case 'busy':
        // 需�?4：网页自己在响应（表单提�?/ 站内链接 / 站点加载态）�?
        // 这类操作不换地址，onLoadStart 不会来，所以这里补一层薄膜过渡�?
        // 已经在整页遮罩里就不要再叠一层�?
        if (_cover != 1) {
          _beginCover(minMs: 1000, overlay: true);
        }
      case 'idle':
        // 站点请求收尾：让薄膜走完至少 1 秒再散（需求「同样做一�?1s 的过渡」）
        if (_coverOverlay) _endCoverWhenReady();
      case 'needLogin':
        // 需�?3：未登录点了点赞/收藏/评论/举报 �?引导登录
        _promptLogin();
      case 'share':
        // 需�?5：网页侧请求呼出系统分享面板
        unawaited(_shareText(e.text ?? '', e.subject ?? ''));
      case 'ready':
        break;
    }
  }

  /// 每次网页跳转都重算底部导航高亮（与旧�?tabForPath 同规则）�?
  void _syncNav(String path) {
    final String target = _tabForPath(path);
    if (!mounted) return;
    setState(() {
      _path = path;
      // ⚠️ 只在网页层在最上面时才改高亮。否则后台的网页导航会把用户
      // 正看着的设置页/我的页顶掉（需�?13 的另一半）�?
      if (_webFront && _tabs.contains(target) && target != _tab) {
        _tab = target;
      }
    });
  }

  /// 与旧 Kotlin �?tabForPath 同规则�?
  String _tabForPath(String path) {
    if (path.isEmpty || path == '/') return 'home';
    if (path.startsWith('/my-posts') || path.startsWith('/favorites')) {
      return 'mine';
    }
    if (path.startsWith('/post/new')) return 'post';
    if (path.startsWith('/daily') ||
        path.startsWith('/did-you-know') ||
        path.startsWith('/lucky-post')) {
      return 'other';
    }
    return _tab; // 帖子详情 / 登录页等：保持当前高�?
  }

  Future<void> _inject() async {
    final InAppWebViewController? c = _web;
    if (c == null) {
      _fxlog('skip: no controller');
      return;
    }
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await _bridge.injectAll(c, dark: dark);
      _fxlog('ok dark=$dark webTheme=${_s.webTheme} pageSize=${_s.pageSize}');
    } catch (e, st) {
      // ⚠️ 以前这里没包 try：Windows 上如�?evaluateJavascript 抛错�?
      // 异常会被 onLoadStop �?async 边界吃掉，表现出来就�?
      // 「注入完全没效果」但一行日志都没有（正是这次踩的坑）�?
      _fxlog('FAILED: $e\n$st');
    }
    if (kDebugCardProbe) {
      try {
        // 直接派发 submit 事件，验证「JS 拦截�?�?�?�?Dart」这条链�?
        // 这条链通了，就说明剩下的只是模拟点击的问题，不是代码问题�?
        const String probe = r'''
(function(){
  try{
    var f = document.querySelector('.share-post-form');
    if (!f) return 'no-form';
    var ev = new Event('submit', {bubbles:true, cancelable:true});
    f.dispatchEvent(ev);
    return 'dispatched prevented=' + ev.defaultPrevented;
  }catch(e){ return 'ERR ' + e; }
})()''';
        final Object? r = await c.evaluateJavascript(source: probe);
        _fxlog('probe: ${r.toString()}');
      } catch (e) {
        _fxlog('probe failed: $e');
      }
    }
  }

  /// 把诊断写到文件�?
  ///
  /// 为什么不�?debugPrint：Windows 桌面上它走的是调试器输出通道�?
  /// 双击运行或重定向 stdout 都抓不到（实测日志文�?0 行）�?
  /// 写文件最可靠，也方便贴给排查者�?
  ///
  /// ⚠️ 必须显式指定 UTF-8：用默认编码写中文，在中�?Windows 上会变成
  /// 乱码（`来自表白墙` �?`鏉ヨ嚜琛ㄧ櫧澧欑殑`），排查时会被误导成
  /// 「数据本身坏了」�?
  void _fxlog(String msg) {
    try {
      final File f = File('${Directory.systemTemp.path}/fxlovewall-diag.log');
      f.writeAsStringSync('$msg\n',
          mode: FileMode.append, flush: true, encoding: utf8);
    } catch (_) {}
    debugPrint('[FX] $msg');
  }

  /// 桌面端的注入兜底：轮询页面状态（�?onWebViewCreated 的注释）�?
  ///
  /// �?400ms 问一�?`document.readyState` �?`location.href`�?
  ///   · 文档就绪（interactive/complete）→ 注入，然后进入「已注入」状�?
  ///   · href 变了 �?视为一次导航，重置注入标记，下次就绪时重新注入
  ///
  /// 轮询而不是依赖回调，是因�?Windows 平台�?loadingState 监听没能装上
  /// （原因见 onWebViewCreated 注释）。轮询成本很低（一次字符串比较），
  /// 而且完全不受平台实现差异影响�?
  void _startDesktopPoll() {
    _desktopPoll?.cancel();
    _desktopPoll = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      final InAppWebViewController? c = _web;
      if (c == null || !mounted) return;
      try {
        final Object? r = await c.evaluateJavascript(source: '(function(){'
            'try{return (document.readyState||"")+"|"+location.pathname'
            '+(location.search||"");}catch(e){return "";}})()');
        final String s = r?.toString() ?? '';
        if (s.isEmpty) return;
        final List<String> parts = s.split('|');
        if (parts.length < 2) return;
        final String state = parts[0];
        // 只取 pathname（去�?query）：_syncNav 的判据是 path�?
        // 带上 `?q=&sort=latest` 会让 `/` 判定失败�?
        final String path = parts[1].split('?').first;
        final bool ready = state == 'interactive' || state == 'complete';
        if (!ready) return;

        if (path != _lastUrlKey) {
          // 视为导航：同步底�?侧栏高亮，并允许重新注入�?
          // ⚠️ 必须�?_syncNav（它会同时更�?_path），不能只改 _lastUrlKey
          // —�?顶部搜索栏的显示条件�?`_path == '/'`，只更新 key 的话
          // 桌面端永远不显示搜索栏（踩过）�?
          _lastUrlKey = path;
          _desktopInjected = false;
          _syncNav(path);
        }
        if (_desktopInjected) return;
        _desktopInjected = true;
        await _inject();
        await _refreshLogin();
        _endCoverWhenReady();
      } catch (_) {
        // 页面还没准备好时 evaluateJavascript 会抛，忽略即�?
      }
    });
  }

  // ---------------------------------------------------------------- 导航

  String _homeUrl() =>
      '$_base/?q=${Uri.encodeComponent(_query)}&sort=${_s.sort}';

  /// 载入一个地址。默认拉一次过渡遮罩，免得刷新过程中闪出没注入样式的原始网页�?
  Future<void> _navigate(String url, {bool cover = true}) async {
    if (mounted) setState(() => _failed = false);
    _forceTopOnLoad = true;
    _pendingRestoreY = null;
    if (cover) _beginCover(minMs: 280);
    await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// 从原生页打开一个网页地址（需�?13 的正解）�?
  void _openWeb(String path) {
    if (mounted) {
      setState(() {
        _webFront = true;
        _failed = false;
      });
    }
    _navigate('$_base$path');
  }

  void _switchTab(String tab) {
    final bool wantsWeb = !_nativeTabs.contains(tab);

    if (!wantsWeb) {
      // 原生页：只翻遮罩层，不碰网页
      setState(() {
        _tab = tab;
        _webFront = false;
      });
      if (tab == 'settings') _refreshLogin();
      return;
    }

    // 已经在同一个网页分区上：回到该分区的根（与旧版一致）
    if (tab == _tab && _webFront) {
      if (tab == 'home') {
        _refreshPage();
      } else {
        _navigate('$_base/post/new');
      }
      return;
    }

    setState(() {
      _tab = tab;
      _webFront = true;
    });
    if (tab == 'home') {
      // 需�?3：只有「从帖子详情点返回」才回到那条帖子在列表里的位置；
      // 其它任何入口（底部导航、详情里点别的链接）都回顶�?
      // 所以这里显式清掉待恢复的位置，只有 [_handleBack] 会把它放回去�?
      _pendingRestoreY = null;
      _forceTopOnLoad = true;
      _navigate(_homeUrl());
    } else {
      _navigate('$_base/post/new');
    }
  }

  Future<void> _refreshLogin() async {
    // 判据是「DOM 里有没有 logout 表单」，不是「cookie 里有没有 session」—�?
    // 站点给每个匿名访客都会下发只�?csrf_token �?session cookie�?
    final InAppWebViewController? c = _web;
    if (c == null) return;
    final bool v = await _bridge.isLoggedIn(c);
    if (mounted && v != _loggedIn) {
      setState(() => _loggedIn = v);
    }
  }

  Future<void> _logout() async {
    // 站点退出是 POST /logout（需 CSRF token）：先跳到已登录页面，加载完成后提交
    setState(() {
      _tab = 'mine';
      _webFront = false;
    });
    await _navigate('$_base/my-posts', cover: false);
  }

  Future<void> _submitLogout() async {
    final InAppWebViewController? c = _web;
    if (c == null) return;
    try {
      final Object? r = await c.evaluateJavascript(source:
          "(function(){var f=document.querySelector('form[action*=\"logout\"]');"
          "if(f){f.submit();return 'ok';}return 'none';})();");
      if (r.toString().contains('none')) {
        // 找不�?logout 表单就把本站 Cookie 全清掉，效果等同退�?
        // （这�?WebView 只服务本站，清空不会有副作用�?
        await CookieManager.instance().deleteAllCookies();
      }
    } catch (_) {
      // 忽略
    }
    await _refreshLogin();
  }

  Future<void> _openExternal(String url) async {
    final Uri? u = Uri.tryParse(url);
    if (u == null) return;
    if (!await launchUrl(u, mode: LaunchMode.externalApplication)) {
      // 打不开就算�?
    }
  }

  // ------------------------------------------------------- 刷新过渡（需�?11�?

  /// 「刷�?/ 跳转时加�?1s 的过渡：旧页面消�?+ 只有背景的过�?+ 新页面出现」�?
  ///
  /// 遮罩由两层组成（�?[_buildCover]）：
  ///   1. 用户设的背景图（同透明度）—�?需�?5：过渡时保留背景
  ///   2. 主题底色 —�?它必�?*不透明**，否则会露出底下未注入样式的原始网页
  /// 所以顺序是：底色在最下面保证「绝不露原页」，背景图叠在它上面做观感�?
  ///
  /// 时长�?[_beginCover]/[_endCoverWhenReady] 这对函数凑满：遮罩至少停�?
  /// [minMs]，但必须等页面真的就绪才放行，所以是 max(最短停�? 实际耗时)�?
  ///
  /// [overlay] �?true �?*�?*盖住旧页面，只在最上层做一层淡入淡出的�?
  /// 和背景同透明度的薄膜（需�?4）：网页自己响应（点分页、提交表单等
  /// 不换地址的操作）时用这个，既有一致的过渡观感，又不会把页面擦掉�?
  void _beginCover({required int minMs, bool overlay = false}) {
    _coverSafety?.cancel();
    _coverMinMs = minMs;
    _coverStart = DateTime.now();
    if (!mounted) return;
    setState(() {
      _coverOverlay = overlay;
      _coverDur = FxMotion.fast;
      _cover = 1;
    });
    // 兜底：万一 onLoadStop / onReceivedError 都没来，遮罩也必须自己退下去�?
    // 否则用户面对的就是一块永远不消失的色块�?
    _coverSafety = Timer(Duration(milliseconds: minMs + 2500), _releaseCover);
  }

  void _endCoverWhenReady() {
    if (_cover != 1) return;
    final int elapsed = DateTime.now().difference(_coverStart).inMilliseconds;
    final int rest = (_coverMinMs - elapsed).clamp(0, 8000);
    _coverSafety?.cancel();
    if (rest == 0) {
      _releaseCover();
    } else {
      _coverSafety = Timer(Duration(milliseconds: rest), _releaseCover);
    }
  }

  void _releaseCover() {
    _coverSafety?.cancel();
    if (!mounted) return;
    setState(() {
      _coverDur = FxMotion.slow;
      _cover = 0;
    });
  }

  /// 用户主动刷新：遮�?1 秒，且回到页面顶部（需�?10 + 11）�?
  Future<void> _refreshPage() async {
    final InAppWebViewController? c = _web;
    if (c == null) return;
    _userRefresh = true;
    _pendingRestoreY = null;
    _forceTopOnLoad = true;
    _beginCover(minMs: 1000);
    try {
      await c.scrollTo(x: 0, y: 0);
    } catch (_) {}
    await c.reload();
  }

  // ------------------------------------------------------- 上滑刷新

  void _onPointerDown(PointerDownEvent e) {
    _pullStart = e.position.dy;
    _pull = 0;
    // 这两个只有启用原生分享兜底时才需要，顺手记下开销可忽�?
    _tapStart = e.position;
    _tapMoved = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    // 记录是否发生过明显移动：只有「几乎没动」才算点击（分享判定要用），
    // 否则滑动浏览时会被误判成点到了分享按钮�?
    if (_tapStart != null &&
        (e.position - _tapStart!).distance > 12) {
      _tapMoved = true;
    }
    if (!_atTop) {
      if (_pull != 0) setState(() => _pull = 0);
      return;
    }
    final double dy = e.position.dy - _pullStart;
    // 只跟手向下拉；页面已在顶部时 WebView 本身不会滚动，所以不冲突
    if (dy > 0) {
      setState(() => _pull = dy.clamp(0, 160));
    } else if (_pull != 0) {
      setState(() => _pull = 0);
    }
  }

  void _onPointerUp(PointerEvent e) {
    final bool trigger = _pull > 90;
    final bool wasTap = !_tapMoved && _pull < 12;
    final Offset? start = _tapStart;
    setState(() => _pull = 0);
    _tapStart = null;
    _tapMoved = false;
    if (trigger) {
      _refreshPage();
      return;
    }
    // ⚠️ 分享原计划在这里做「原生坐标判定」，现已**停用**�?
    //
    // 原因：桥对象修好之后，网页里�?JS 拦截器（bindShareForms）已经能
    // 正常工作 —�?实测日志�?
    //     share req: text=[来自表白墙的最新分享：…]
    //     share result: true
    // 而这条原生兜底会**重复触发**同一次点击（两条路径都发请求），
    // 反而把剪贴板写乱。既�?JS 那条路已经通了，就不要再留第二条�?
    //
    // 保留 _maybeShareAt 的实现与开关，便于将来某个平台桥又坏掉时快速启用�?
    if (kUseNativeShareFallback && wasTap && start != null) {
      unawaited(_maybeShareAt(start));
    }
  }

  /// 反复把页面滚�?[y]，直到它稳住（需�?1 / 10）�?
  ///
  /// 为什么不能只滚一次：WebView �?`scrollTo` 会被**当时的文档高�?*夹住�?
  /// 站点是服务端整页渲染，`onLoadStop` 触发时图片往往还没解码、卡片还�?
  /// 撑开，文档只有最终高度的一�?—�?这时 `scrollTo(5000)` 实际只能�?2500�?
  /// 等布局长回来后用户就停在「网页正中间」，正是反馈里的现象�?
  ///
  /// 所以分四拍写回：立刻、下一帧�?00ms�?000ms。只要有一拍赶上布局完成
  /// 就会落到正确位置；后面的拍子写的是同一个值，不会抖�?
  Future<void> _restoreScroll(InAppWebViewController c, double y) async {
    final int target = y.round();
    for (final int delay in <int>[0, 16, 400, 1000]) {
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      if (!mounted) return;
      try {
        await c.scrollTo(x: 0, y: target);
      } catch (_) {
        return;
      }
      // 到最后两拍时校准一下：如果实际位置已经接近目标就提前收工，
      // 免得在用户已经手动滑动之后又把他拽回去�?
      if (delay >= 400) {
        try {
          final int? cy = await c.getScrollY();
          if (cy == null) continue;
          final int cur = cy;
          if ((cur - target).abs() <= 8) {
            _lastY = cur.toDouble();
            return;
          }
          // 用户自己滑走了就别再纠正
          if ((cur - target).abs() > 120) {
            _lastY = cur.toDouble();
            return;
          }
        } catch (_) {}
      }
    }
    _lastY = target.toDouble();
  }

  /// 回顶同理（需�?10）：多写几拍，避免被矮文档夹住或又被内容顶下去�?
  ///
  /// �?[_restoreScroll] 的区别：这里目标恒为 0，所以要一直写到用�?
  /// 没有自己往下滑为止�?
  Future<void> _scrollTopAndKeep(InAppWebViewController c) async {
    for (final int delay in <int>[0, 16, 400, 1000]) {
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      if (!mounted) return;
      try {
        final int? cy = await c.getScrollY();
        final int cur = cy ?? 0;
        // 用户已经自己滑动过了（下拉想看点别的），就不再强行拉回顶
        if (delay >= 400 && cur > 60) {
          _lastY = cur.toDouble();
          return;
        }
        await c.scrollTo(x: 0, y: 0);
      } catch (_) {
        return;
      }
    }
    _lastY = 0;
  }

  // ------------------------------------------------------- 返回键（需�?12�?

  /// 返回�?/ 边缘返回手势：先逐级往上，只有在首页根部连按两次才真正退出�?
  Future<void> _handleBack() async {
    // 1) 原生页压在网页上 �?退回首�?
    if (!_webFront) {
      _switchTab('home');
      _resetExit();
      return;
    }

    // 2) 网页自身还能后退 �?后退一�?
    final InAppWebViewController? c = _web;
    if (c != null) {
      try {
        if (await c.canGoBack()) {
          // 需�?3：从帖子详情返回首页时，回到那条帖子原来的位置�?
          // 判据是「当前在帖子详情�?「记过首页位置」两项同时成立；
          // 其它后退（登录页、分类页…）一律回顶�?
          if (_path.startsWith('/post/') && _savedHomeY >= 0) {
            _pendingRestoreY = _savedHomeY;
            _forceTopOnLoad = false;
          }
          await c.goBack();
          _resetExit();
          return;
        }
      } catch (_) {}
    }

    // 3) 不在首页根部 �?回首页（这种情况回顶，不还原位置�?
    if (_tab != 'home' || _path != '/') {
      _savedHomeY = -1;
      _switchTab('home');
      _resetExit();
      return;
    }

    // 4) 已经在首页根�?�?连按两次才退�?
    final DateTime now = DateTime.now();
    final DateTime? last = _lastBackAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    _toast('再按一次返回键退出应用');
  }

  void _resetExit() => _lastBackAt = null;

  void _toast(String msg) {
    if (!mounted) return;
    final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1600),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      ),
    );
  }

  // --------------------------------------------------- 今日幸运物品（需�?1�?

  /// 抽今日幸运物品，并把它显示在「今日幸运物品」那行文字上（需�?2）�?
  ///
  /// 改为 **Flutter 原生直连**（见 FxLucky 的注释）：原来在 WebView 里跑
  /// fetch 依赖 `window.FxWall` 注入成功 + 当前页面有那个被隐藏的表单，
  /// 实测点了没反应。原生直连不依赖任何注入，也不依赖当前在哪一页�?
  ///
  /// ⚠️ �?`dart:io` �?HttpClient 有自己独立的 cookie jar，和 WebView 不通�?
  /// 所以这里显式把 WebView �?cookie 读出来喂给它 —�?否则用户明明登录了，
  /// 接口也会当他没登录（未登录时服务端返�?400 + 一整页 HTML）�?
  Future<void> _luckyItem() async {
    if (_luckyBusy) return;
    setState(() => _luckyBusy = true);
    try {
      final FxLuckyResult r = await FxLucky.draw(
        cookiesProvider: _webCookies,
        onSetCookie: _writeWebCookie,
      );
      if (!mounted) return;
      if (r.ok && r.message.trim().isNotEmpty) {
        setState(() => _luckyText = r.message.trim());
      } else {
        setState(() => _luckyText = null);
        _toast(r.message.trim().isEmpty ? '抽取失败，请稍后再试' : r.message.trim());
      }
    } finally {
      if (mounted) setState(() => _luckyBusy = false);
    }
  }

  /// 读出 WebView 里本站的 cookie，拼�?`k=v; k=v` 形式�?
  Future<String> _webCookies() async {
    try {
      final List<Cookie> list =
          await CookieManager.instance().getCookies(url: WebUri(_base));
      return list.map((Cookie c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  /// 把服务端新下发的 cookie 写回 WebView，保持两边会话一致�?
  Future<void> _writeWebCookie(Uri url, String setCookie) async {
    try {
      // Set-Cookie 形如 `name=value; Path=/; HttpOnly`，取第一段即�?
      final String pair = setCookie.split(';').first.trim();
      final int eq = pair.indexOf('=');
      if (eq <= 0) return;
      final String name = pair.substring(0, eq).trim();
      final String value = pair.substring(eq + 1).trim();
      if (name.isEmpty) return;
      await CookieManager.instance().setCookie(
        url: WebUri('${url.scheme}://${url.host}'),
        name: name,
        value: value,
        path: '/',
      );
    } catch (_) {}
  }

  /// 兼容旧注入路径留下的 lucky 事件（网页那版已废弃，但胶水里还留着�?
  /// 万一别处触发也不该崩）�?
  void _applyLuckyCompat(bool ok, String text) {
    if (!mounted) return;
    if (ok && text.trim().isNotEmpty) {
      setState(() => _luckyText = text.trim());
    }
  }

  // ------------------------------------------------------- 未登录引导（需�?3�?

  /// 未登录时点了点赞/收藏/评论/举报 �?直接引导到登录页�?
  ///
  /// 刻意**�?*弹「请先登录」的确认框：那多一次点击，而用户点点赞的意�?
  /// 很明确。直接跳登录页，登录成功后站点自己会回到原页面�?
  void _promptLogin() {
    if (!mounted) return;
    // 防连点：同一个动作被快速点两次不该排两次跳�?
    final DateTime now = DateTime.now();
    if (_lastLoginPrompt != null &&
        now.difference(_lastLoginPrompt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastLoginPrompt = now;
    _toast('登录后才能点赞、收藏和评论');
    _openWeb('/login');
  }

  // ------------------------------------------------------- 分享（需�?5�?

  /// 呼出系统分享面板。文案由网页侧从站点�?data-share-text 取�?
  Future<void> _shareText(String text, String subject) async {
    _fxlog('share req: text=[$text]');
    if (text.trim().isEmpty) {
      _fxlog('share ABORT: text empty');
      return;
    }
    final bool ok = await FxUpdate.share(text.trim(), subject: subject);
    _fxlog('share result: $ok');
    if (!mounted) return;
    if (ok) {
      // 桌面端没有系统分享面板，实际行为是「复制到剪贴板」，所以要如实告诉用户
      if (_isDesktop) _toast('链接已复制到剪贴板');
    } else {
      _toast('没有找到可分享的应用');
    }
  }

  /// 手指抬起后，判断这次点击是否落在某个「分享」按钮上（需�?5）�?
  ///
  /// ## 为什么改成原生判�?
  ///
  /// 原方案是往页面注入 JS，拦�?.share-post-form �?submit/click，再通过
  /// `window.flutter_inappwebview.callHandler` 回传�?Dart�?
  ///
  /// 但实测（探针输出）：
  ///     fiw=undefined | FxWall=object | FxWall.send=function
  ///     call=THREW:Cannot read properties of undefined (reading 'callHandler')
  /// 也就�?*桥对�?`window.flutter_inappwebview` 压根没被注入**，`send()`
  /// 每次都抛异常，而它外面套着 `try/catch {}` —�?异常被静默吞掉，
  /// 表现为「点了完全没反应，且一行日志都没有」。两端都中招�?
  ///
  /// 与其去赌各平台的注入时序，不如彻底不依赖它：�?Flutter 在拿到点�?
  /// 坐标后，�?`document.elementFromPoint` 问页面「这个点上是什么元素」，
  /// 如果落在分享按钮里就�?`data-share-text` 取回来�?
  /// 这条路径只用�?evaluateJavascript（两端都稳定可用），不碰任何桥对象�?
  ///
  /// 代价：站点的分享计数（POST /post/N/share）不再发生。这是既有的�?
  /// 用户已确认的取舍（需�?5 明确选了「原生分享面板」）�?
  Future<void> _maybeShareAt(Offset globalPos) async {
    _fxlog('maybeShareAt: $globalPos');
    final InAppWebViewController? c = _web;
    if (c == null || !mounted) {
      _fxlog('maybeShareAt: no controller/mounted');
      return;
    }
    // 页面坐标系：Listener 给的是全局坐标，先换算�?WebView 内部坐标
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Offset local = box.globalToLocal(globalPos);
    // ⚠️ 不要手工扣顶栏高度猜坐标 —�?猜错就整个失效（踩过�?
    // 扣了 104px，实际该�?104，导�?y 偏上 104 而永远找不到按钮）�?
    // 改为让页面自己换算：�?Flutter 的局部坐标交�?JS�?
    // 由它�?document.elementFromPoint 判断，并�?getBoundingClientRect
    // 交叉验证到底是哪个元素�?
    final double px = local.dx;
    final double py = local.dy;

    try {
      final Object? r = await c.evaluateJavascript(source: '''
(function(){
  try{
    var el = document.elementFromPoint($px, $py);
    if (!el) { return 'NONE'; }
    var f = el.closest ? el.closest('.share-post-form') : null;
    if (!f) {
      return 'MISS:' + el.tagName + '.' + (el.className || '');
    }
    return 'HIT:' + (f.getAttribute('data-share-text') || 'FALLBACK');
  }catch(e){ return 'ERR ' + e; }
})()''');
      final String s = r?.toString() ?? '';
      _fxlog('maybeShareAt: ($px,$py) -> $s');
      if (s.startsWith('HIT:')) {
        final String payload = s.substring(4);
        if (payload == 'FALLBACK' || payload.isEmpty) {
          await _shareText('来自表白墙的分享：\$_base', '复兴表白墙');
        } else {
          await _shareText(payload, '复兴表白墙');
        }
      }
    } catch (e) {
      _fxlog('maybeShareAt err: $e');
    }
  }

  // ------------------------------------------------- 清除缓存（需求 16）

  /// 清缓存并报告清掉了多少 —— 但**绝不动 Cookie**，所以不会把用户踢下线。
  ///
  /// ⚠️ 这里曾经用错通道名（`com.fxlovewall.app/cache`），而 Kotlin 侧注册的是
  /// `com.fxlovewall.app/device` —— 调用直接抛 MissingPluginException，
  /// 被 catch 吞掉后表现为「清除缓存按钮点了没反应」。
  /// 方法名同样要对齐：量大小是 `cacheSize`（不是 `size`）。
  Future<void> _clearCache() async {
    int before = 0;
    try {
      before = (await kDeviceChannel.invokeMethod<int>('cacheSize')) ?? 0;
    } catch (e) {
      // 通道不可用（例如非 Android）就退化成只报「已清除」
      _fxlog('cacheSize failed: $e');
    }

    await InAppWebViewController.clearAllCache();
    try {
      await kDeviceChannel.invokeMethod<void>('clearWebStorage');
    } catch (_) {}

    int after = before;
    if (before > 0) {
      // clearAllCache 是异步落盘的，稍微等一下再量，否则差值是 0
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        after = (await kDeviceChannel.invokeMethod<int>('cacheSize')) ?? before;
      } catch (_) {}
    }

    final int freed = (before - after).clamp(0, before);
    _toast(freed > 0
        ? '已清除缓存 ${_fmtSize(freed)}'
        : '缓存已清除');
    await _refreshLogin();
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return PopScope(
      // 需�?12：返回键永远不直接退出，先交�?_handleBack 逐级往上�?
      // canPop:false 之后，系统的边缘返回手势也会走同一条路�?
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          bottom: false,
          child: Row(
            children: <Widget>[
              // ---- 桌面端：侧边栏（安卓端不显示�?---
              if (_isDesktop)
                FxSideRail(
                  items: _railItems,
                  index: _tabs.indexOf(_tab),
                  onChanged: (int i) => _switchTab(_tabs[i]),
                  collapsed: _railCollapsed,
                  onToggle: () =>
                      setState(() => _railCollapsed = !_railCollapsed),
                ),
              // ---- 内容区：顶部搜索 + 网页/原生�?----
              Expanded(
                child: Column(
                  children: <Widget>[
                    // 顶部搜索区：淡入淡出 + 轻微上移，只在软件主题的首页信息流出�?
                    AnimatedSize(
                      duration: FxMotion.fast,
                      curve: FxMotion.enter,
                      child: AnimatedSwitcher(
                        duration: FxMotion.fast,
                        switchInCurve: FxMotion.enter,
                        switchOutCurve: FxMotion.exit,
                        transitionBuilder:
                            (Widget child, Animation<double> a) =>
                                FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.06),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: _showTopBar
                            ? FxTopBar(
                                key: const ValueKey<String>('topbar'),
                                query: _query,
                                sort: _s.sort,
                                onSearch: (String q) {
                                  _query = q;
                                  _navigate(_homeUrl());
                                },
                                onSort: (String v) {
                                  _s.sort = v;
                                  _navigate(_homeUrl());
                                },
                                onLuckyPost: () => _openWeb('/lucky-post'),
                                onLuckyItem: () => unawaited(_luckyItem()),
                                luckyText: _luckyText,
                              )
                            : const SizedBox.shrink(
                                key: ValueKey<String>('notopbar')),
                      ),
                    ),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 安卓端保留底部导航；桌面端导航已搬到左侧，这里不再显示�?
        bottomNavigationBar: _isDesktop
            ? null
            : FxBottomNav(
                items: _navItems,
                index: _tabs.indexOf(_tab),
                onChanged: (int i) => _switchTab(_tabs[i]),
              ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: <Widget>[
        // ---- 网页层：常驻，绝不从树上移除 ----
        Positioned.fill(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: _buildWebView()),
                // 下拉刷新指示�?
                _buildPullIndicator(),
                // 顶部加载进度
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _loading ? 1 : 0,
                    duration: FxMotion.fast,
                    child: LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
                if (_failed) _buildError(),
                // ---- 刷新过渡遮罩：盖住旧页面 / 盖住未注入样式的原始网页 ----
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: _cover < 0.02,
                    child: AnimatedOpacity(
                      opacity: _cover,
                      duration: _coverDur,
                      curve: FxMotion.enter,
                      child: _buildCover(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ---- 原生页覆盖层：淡�?+ 轻微上移 ----
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _webFront,
            child: AnimatedSwitcher(
              duration: FxMotion.medium,
              switchInCurve: FxMotion.enter,
              switchOutCurve: FxMotion.exit,
              transitionBuilder: (Widget child, Animation<double> a) =>
                  FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, FxMotion.decorative ? 0.02 : 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              // 网页在前面时，原生层整个不建 —�?少一层被误压在上面的风险
              child: _webFront
                  ? const SizedBox.shrink(key: ValueKey<String>('noweb'))
                  : _buildNativePage(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNativePage() {
    switch (_tab) {
      case 'settings':
        return SettingsPage(
          key: const ValueKey<String>('settings'),
          settings: _s,
          loggedIn: _loggedIn,
          onLogin: () => _openWeb('/login'),
          onRegister: () => _openWeb('/register'),
          onLogout: _logout,
          onOpenSite: () => _openExternal(_base),
          onClearCache: _clearCache,
          onCheckUpdate: _checkUpdateManual,
          versionName: _version.versionName,
        );
      case 'mine':
        return MinePage(
          key: const ValueKey<String>('mine'),
          onOpen: _openWeb,
        );
      case 'other':
        return OtherPage(
          key: const ValueKey<String>('other'),
          onOpen: _openWeb,
        );
      default:
        return const SizedBox.shrink(key: ValueKey<String>('noweb'));
    }
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_homeUrl())),
      // ⚠️ initialUserScripts **只有移动端能�?*�?
      //
      // Windows �?zikzak_inappwebview_windows 没有实现它（该平台源码里
      // UserScript 出现 0 次）。传进去会让平台层初始化整体抛异常，而那�?
      // 异常�?platform 文件里的 `catch (e) { print(...) }` 吞掉 —�?
      // 表现出来就是「网页能显示，但 onLoadStart/onLoadStop 永远不触发�?
      // 注入完全没效果」，且一行日志都没有（这次踩的坑）�?
      //
      // 桌面端改�?injectAll �?evaluateJavascript 自行注入胶水
      // （见 FxBridge.injectAll 顶部�?$glue 的说明）�?
      initialUserScripts: _isDesktop
          ? null
          : UnmodifiableListView<UserScript>(<UserScript>[
              UserScript(
                source: FxBridge.glue,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        // 下面这几个是 Android 专属开关。桌面端传了没意义，而且
        // useShouldOverrideUrlLoading 会要求平台实�?
        // shouldOverrideUrlLoading —�?Windows 实现里根本没有这个方法，
        // 很可能就是它让平台层初始化抛异常的。所以只在移动端设置�?
        databaseEnabled: !_isDesktop,
        useShouldOverrideUrlLoading: !_isDesktop,
        mediaPlaybackRequiresUserGesture: !_isDesktop,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        transparentBackground: false,
        overScrollMode: _isDesktop ? null : OverScrollMode.NEVER,
      ),
      onWebViewCreated: (InAppWebViewController c) {
        _web = c;
        _fxlog('onWebViewCreated');
        c.addJavaScriptHandler(
          handlerName: FxBridge.handlerName,
          callback: (List<Object?> args) => _bridge.handleCall(args),
        );
        // ⚠️ 桌面端兜底：Windows 平台�?onLoadStart/onLoadStop **不会触发**
        // （实测日志里只有 onWebViewCreated）。而整套注入都挂在 onLoadStop 上，
        // 所以桌面上没有主题、没有图标化、没有分�?—�?就是用户看到�?
        // 「明明是软件风格，却还是原网页」�?
        //
        // 原因在平台实现里：它�?load 事件挂在 _controller.loadingState 上，
        // 而那段监听注册在 onWebViewCreated **之后**；两者之间只要抛一次异�?
        // （被同一�?try �?catch 吞掉、只�?print 输出，Windows 上根本看不到），
        // 监听就永远没装上�?
        //
        // 不去 depend 那个实现细节，改�?*主动轮询**：周期性地问页�?
        // 「文档好了没」，好了就注入，并记�?URL 变化来模拟导航事件�?
        if (_isDesktop) _startDesktopPoll();
      },
      onLoadStart: (InAppWebViewController c, WebUri? url) {
        _fxlog('onLoadStart url=$url');
        if (!mounted) return;
        // 需�?19：同页刷新（例如提交评论�?POST 回同一地址）要保留滚动位置�?
        // 判据是「新地址与当前地址完全一致」，且这次不是用户主动刷新�?
        // 也不是我们主动导�?—�?后两种情况按需�?10 必须回到顶部�?
        //
        // ⚠️ 需�?3 的「从详情返回首页」也会走到这里，那条路径的目标地址
        // （`/?q=&sort=latest`）和 _lastUrlKey（`/post/282`）不同，所以不会被
        // 覆盖；但为稳妥起见仍然显式让开：_pendingRestoreY 已经�?_handleBack
        // 设好时才不插手�?
        if (url != null && !_userRefresh && !_forceTopOnLoad
            && _pendingRestoreY == null) {
          final String key = '${url.path}${url.query}';
          if (key == _lastUrlKey && _lastY > 40) {
            _pendingRestoreY = _lastY;
          }
        }
        setState(() {
          _loading = true;
          _progress = 0;
          _failed = false;
        });
      },
      onLoadStop: (InAppWebViewController c, WebUri? url) async {
        _fxlog('onLoadStop url=$url mounted=$mounted');
        if (!mounted) return;
        setState(() => _loading = false);
        await _inject();
        await _refreshLogin();

        if (url != null) {
          _syncNav(url.path);
          _lastUrlKey = '${url.path}${url.query}';
          // 从「我的」点退出登录后，若回到其它页面则按需提交 logout
          if (url.path == '/my-posts' && _tab == 'mine' && !_webFront) {
            unawaited(_submitLogout());
          }
        }

        // 需�?10：用户主动导�?/ 刷新 �?回到最顶部
        // 需�?19：同页刷�?�?回到原来的位�?
        // 需�?3 ：从帖子详情返回 �?回到那条帖子的位置（�?_handleBack 设置�?
        final double? restore = _pendingRestoreY;
        _pendingRestoreY = null;
        if (restore != null && restore > 0) {
          // ⚠️ 还原必须**重试**，一次是还原不准的�?
          // 原因：onLoadStop 触发时，站点的卡�?图片往往还没完成布局�?
          // 此刻文档高度可能只有最终的一半，scrollTo(y) 会被夹到那个矮高度上�?
          // 等布局长回来后位置就“卡在中间”了 —�?用户反馈�?
          // 「从详情返回时停在网页正中间」正是这个�?
          // 所以分几步写回：立刻、下一帧、以及两次延时（覆盖图片撑高的情况）�?
          await _restoreScroll(c, restore);
        } else if (_forceTopOnLoad || _userRefresh) {
          // 回顶同理：内容变�?变高都会让一�?scrollTo(0) 失效，多写几次�?
          await _scrollTopAndKeep(c);
        }

        // ⚠️ 这里原本无条件把 _savedHomeY 清成 -1，于是「从首页进帖子详情再
        // 返回」永远回不到原位�?—�?详情页自己的 onLoadStop 就已经把位置抹掉了�?
        // 现在只在**确实回到了首页信息流**且刚用它还原过时才清（需�?1）�?
        if (url != null && url.path == '/' && restore != null && restore > 0) {
          _savedHomeY = -1;
        }

        _forceTopOnLoad = false;
        _userRefresh = false;
        _endCoverWhenReady();
      },
      onProgressChanged: (InAppWebViewController c, int p) {
        if (mounted) setState(() => _progress = p / 100);
      },
      onScrollChanged: (InAppWebViewController c, int x, int y) {
        _lastY = y.toDouble();
        final bool top = y <= 4;
        if (top != _atTop && mounted) setState(() => _atTop = top);
      },
      onReceivedError: (InAppWebViewController c, WebResourceRequest req,
          WebResourceError err) {
        if (req.isForMainFrame ?? false) {
          if (mounted) setState(() => _failed = true);
          // 出错也必须把遮罩收掉，不然用户只能看到一块纯�?
          _forceTopOnLoad = false;
          _userRefresh = false;
          _endCoverWhenReady();
        }
      },
      shouldOverrideUrlLoading:
          (InAppWebViewController c, NavigationAction action) async {
        final WebUri? uri = action.request.url;
        if (uri == null) return NavigationActionPolicy.ALLOW;
        final String h = uri.host;
        // 站内与背景图虚拟主机留在 WebView，其余交给系统浏览器
        if (h == _host || h == 'fxlovewall.me') {
          // 需�?3：离开首页信息流去看某条帖子时，把当前滚动位置记下来，
          // 这样用户点返回能回到原来那条帖子的位置上�?
          // 只记一�?—�?从详情再跳别的帖子不该把首页的基准位置覆盖掉�?
          if (_path == '/' && uri.path.startsWith('/post/') && _savedHomeY < 0) {
            _savedHomeY = _lastY;
          }
          return NavigationActionPolicy.ALLOW;
        }
        await _openExternal(uri.toString());
        return NavigationActionPolicy.CANCEL;
      },
    );
  }

  /// 过渡遮罩（需�?4 / 5 / 11 / 19）�?
  ///
  /// 两种模式�?
  ///   · 整页遮罩（[_coverOverlay] == false）：底色**不透明**，保证刷新过程中
  ///     绝不露出未注入样式的原始网页（需�?11 / 19）�?
  ///   · 薄膜遮罩（[_coverOverlay] == true）：网页自己在响应（点分页、提�?
  ///     表单等不换地址的操作）时用。这时不能把页面擦掉，所以只在最上层
  ///     叠一层和背景同透明度的薄膜（需�?4）�?
  ///
  /// 两种模式下都铺用户设的背景图，透明度与设置相同（需�?5）�?
  Widget _buildCover() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Uint8List? bg = _s.bgBytes;
    final double bgOpacity = _s.bgOpacity;

    // 薄膜模式：底色调成半透明（背景图自己带透明度，不再乘一次）
    final Widget base = ColoredBox(
      color: _coverOverlay
          ? cs.surface.withValues(alpha: 0.35)
          : cs.surface,
    );

    if (bg == null) {
      return base;
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        base,
        Opacity(
          opacity: bgOpacity.clamp(0.0, 1.0),
          child: Image.memory(
            bg,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildPullIndicator() {    final bool armed = _pull > 90;
    final double t = (_pull / 90).clamp(0.0, 1.0);
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: _pull > 0 ? (0.35 + 0.65 * t) : 0,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, _pull * 0.35),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedRotation(
                      turns: armed ? 0.5 : 0,
                      duration: FxMotion.fast,
                      curve: FxMotion.enter,
                      child: Icon(
                        Icons.arrow_downward,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: FxMotion.fast,
                      child: Text(
                        armed ? '松开刷新' : '下拉刷新',
                        key: ValueKey<bool>(armed),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 52, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('页面加载失败',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('请检查网络连接后重试。',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                setState(() => _failed = false);
                _refreshPage();
              },
              child: const Text('重试'),
            ),
            if (_pagerText != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_pagerText!,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
