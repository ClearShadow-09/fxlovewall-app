import 'dart:convert';

import 'package:zikzak_inappwebview/zikzak_inappwebview.dart';

import '../state/fx_settings.dart';
import '../theme/fx_colors.dart';
import 'fx_web_assets.dart';

/// 网页回传上来的事件。
class FxWebEvent {
  const FxWebEvent({
    required this.type,
    this.path,
    this.search,
    this.text,
    this.subject,
    this.shown,
    this.total,
    this.ok,
  });

  /// ready | nav | pager | lucky | busy | idle | needLogin | share
  final String type;
  final String? path;
  final String? search;
  final String? text;

  /// 仅 share 事件使用：分享面板的标题。
  final String? subject;

  final int? shown;
  final int? total;

  /// 仅 lucky 事件使用：站点 /daily-lucky-item 返回的 {ok: ...}。
  final bool? ok;

  static FxWebEvent? parse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Map<dynamic, dynamic> m = raw;
    final Object? t = m['type'];
    if (t is! String) {
      return null;
    }
    return FxWebEvent(
      type: t,
      path: m['path'] as String?,
      search: m['search'] as String?,
      text: m['text'] as String?,
      subject: m['subject'] as String?,
      shown: (m['shown'] as num?)?.toInt(),
      total: (m['total'] as num?)?.toInt(),
      ok: m['ok'] is bool ? m['ok'] as bool : null,
    );
  }
}

/// Flutter 与网页之间的 JSBridge。
///
/// 双向：
///   · 下发（Flutter → 网页）：主题 CSS、分页、举报/删除布局修正、图标化、
///     圆角、字号、背景、动画档位
///   · 回传（网页 → Flutter）：ready / nav（history 变化）/ pager（分页状态）
///
/// 回传之所以走 bridge 而不是只靠插件的原生回调：插件能拿到 URL 和滚动位置，
/// 但拿不到 DOM 层面的信息（当前显示了几条、分页到第几页、举报按钮有没有搬成功），
/// 这些只有页面自己知道。
class FxBridge {
  FxBridge({required this.settings, required this.onEvent});

  static const String handlerName = 'fxEvent';

  final FxSettings settings;
  final void Function(FxWebEvent) onEvent;

  /// 注入到页面里的桥接胶水。以 initialUserScripts 的形式在「文档开始」注入，
  /// 保证页面自身脚本运行前 window.FxWall 就已就绪，避免竞态。
  /// 用 raw string，避免 Dart 把 `$` 当插值。
  ///
  /// ⚠️ 「网页主题」下这段**依然会注入**，这是刻意的：它只做两件事 ——
  /// 上报 history 变化、以及给分页后的卡片加一个进场类。它不碰站点的任何
  /// 样式、布局或业务逻辑。真正被「零注入」禁掉的是 buildCss / 分页器 /
  /// layout_fix 这三样会改变页面外观与结构的东西。
  /// 如果连这段也想彻底去掉，说一声 —— 代价是 `history.pushState` 型的
  /// 站内跳转不再能实时通知 Flutter 底部导航。
  ///
  /// ⚠️ 各平台的 JS→Dart 桥对象**名字不一样**，必须都试一遍：
///
///   · Android / iOS / macOS：`window.flutter_inappwebview.callHandler`
///   · **Windows**：`window.zikzak_inappwebview.callHandler`
///     （插件内部用 WebView2 的 `window.chrome.webview.postMessage` 实现，
///      见 zikzak_inappwebview_windows 的 _ensureJavaScriptHandlerBridge）
///
/// 之前只试了第一个，而探针实测在桌面端：
///     fiw=undefined | call=THREW:Cannot read properties of undefined
/// 也就是桥压根不在 —— `send()` 每次都抛异常，外面又套着 `try/catch {}`
/// 把异常吞了，于是「分享/未登录拦截/分页上报」全部静默失效。
/// 这类「异常被吞 + 双平台差异」的组合极难从现象反推，所以这里显式列出。
static const String glue = r'''
(function(){
  var W = window;
  /* 依次尝试各平台的桥，谁在就用谁。全都不可用时退回 postMessage 直发。 */
  function send(p){
    try {
      if (W.flutter_inappwebview
          && typeof W.flutter_inappwebview.callHandler === 'function') {
        W.flutter_inappwebview.callHandler('fxEvent', p);
        return;
      }
    } catch(e) {}
    try {
      if (W.zikzak_inappwebview
          && typeof W.zikzak_inappwebview.callHandler === 'function') {
        W.zikzak_inappwebview.callHandler('fxEvent', p);
        return;
      }
    } catch(e) {}
    try {
      // Windows 的底层通道：直接按插件的消息协议发。
      // 正常情况下上面第二条已经命中；这条是它改名时的兜底。
      if (W.chrome && W.chrome.webview && W.chrome.webview.postMessage) {
        W.chrome.webview.postMessage(JSON.stringify({
          _zikzakHandlerCall: true,
          callId: 0,
          handlerName: 'fxEvent',
          args: [p]
        }));
      }
    } catch(e) {}
  }
  W.FxWall = W.FxWall || {};
  W.FxWall.send = send;
  W.FxWall.reportNav = function(){
    send({type:'nav', path: location.pathname, search: location.search});
  };
  if (!W.FxWall._histPatched) {
    W.FxWall._histPatched = 1;
    ['pushState','replaceState'].forEach(function(k){
      var orig = history[k];
      history[k] = function(){
        var r = orig.apply(this, arguments);
        W.FxWall.reportNav();
        return r;
      };
    });
    W.addEventListener('popstate', W.FxWall.reportNav);
    W.addEventListener('hashchange', W.FxWall.reportNav);
  }
  // 分页跑完后：上报分页状态，并给当前可见的卡片加进场动画（错峰 stagger）
  W.FxWall.afterPager = function(){
    var info = document.querySelector('.fx-pager .fx-info');
    var cards = document.querySelectorAll('article.card.post');
    var shown = 0, idx = 0;
    for (var i = 0; i < cards.length; i++){
      if (cards[i].style.display !== 'none'){
        shown++;
        cards[i].style.setProperty('--fx-i', idx++);
        cards[i].classList.add('fx-card-in');
      } else {
        cards[i].classList.remove('fx-card-in');
      }
    }
    send({
      type: 'pager',
      text: info ? info.textContent : '',
      shown: shown,
      total: cards.length
    });
  };

  /* ---- 「网页自己在响应」的信号（需求 4）----
     站点提交表单时不换地址（fetch/XHR 或 data-no-loading 的 POST），
     WebView 的 onLoadStart 不会触发，所以用户会直接看到原网页「卡」一下再变。
     这里把这类操作上报给 Flutter，由它放一层和背景同透明度的薄膜过渡 1 秒。

     刻意只上报，不做任何拦截：站点自己的 fetch / 表单逻辑必须照常跑。 */
  W.FxWall._busyT = 0;
  W.FxWall.busy = function(){
    send({type:'busy'});
    clearTimeout(W.FxWall._busyT);
    // 最长 1.2s 后自动收尾，避免站点某次请求悬着导致薄膜不消失
    W.FxWall._busyT = setTimeout(function(){ send({type:'idle'}); }, 1200);
  };
  W.FxWall.idle = function(){
    clearTimeout(W.FxWall._busyT);
    send({type:'idle'});
  };
  if (!W.FxWall._busyPatched) {
    W.FxWall._busyPatched = 1;
    // submit：站点大量表单靠 JS 拦截后 fetch，捕获阶段先报忙
    W.addEventListener('submit', function(e){
      var f = e.target;
      if (f && f.closest && f.closest('.fx-pager')) { return; }   // 分页器是纯前端
      W.FxWall.busy();
    }, true);
    // 站点的通用加载态：body.is-loading 由它自己的脚本加（遮罩已被我们隐藏）
    W.addEventListener('DOMContentLoaded', function(){
      try {
        new MutationObserver(function(){
          if (document.body.classList.contains('is-loading')) { W.FxWall.busy(); }
          else { W.FxWall.idle(); }
        }).observe(document.body, {attributes:true, attributeFilter:['class']});
      } catch(e){}
    });

    /* ---- 未登录时的操作拦截（需求 3）----
       未登录时站点的点赞只是一个 <span class="muted">点赞 N</span>，本来
       就不可点；收藏/评论/举报则可能可点但被服务端拒绝。这里统一在捕获
       阶段拦下「需要登录」的动作，上报给 Flutter，由它引导到 /login。

       为什么不直接 location.href='/login'：那会绕过 Flutter 的过渡遮罩，
       用户会看到一次生硬的整页刷新。上报之后由 Dart 侧走 _openWeb()，
       观感与其它跳转统一。

       ⚠️ 未登录的判据仍是「没有 logout 表单」，与 isLoggedIn 同一套，
       不依赖站点自己的类名（那些类名在已登录页面之外无法确认）。 */
    W.FxWall.needsLogin = function(el){
      if (document.querySelector('form[action*="logout"]')) { return false; }
      var t = (el && (el.textContent || el.value)) || '';
      t = t.replace(/\s+/g, '');
      if (t.indexOf('点赞') >= 0 || t.indexOf('收藏') >= 0) { return true; }
      if (t.indexOf('评论') >= 0 || t.indexOf('发表评论') >= 0) { return true; }
      if (t.indexOf('举报') >= 0 || t.indexOf('登录后') >= 0) { return true; }
      return false;
    };
    W.addEventListener('click', function(e){
      var el = e.target;
      if (!el || !el.closest) { return; }
      var hit = el.closest('.like-button, .favorite-button, .left-actions span,'
        + ' .right-actions > a, .text-danger-button, .comment-action-button,'
        + ' .left-actions, .post-actions a');
      if (!hit) { return; }
      if (!W.FxWall.needsLogin(hit)) { return; }
      e.preventDefault();
      e.stopPropagation();
      send({type:'needLogin'});
    }, true);

    /* ---- 分享改走系统面板（需求 5）----
       站点的分享是提交 .share-post-form（POST /post/N/share，服务端计数）。
       需求要的是呼出系统分享面板，所以这里拦下提交，把站点**自己写在
       data-share-text 里**的文案（已含帖子链接）交给原生 Intent。

       ⚠️ 两个监听都挂：
         · window 捕获阶段（先手，能挡住绝大多数情况）
         · 直接挂在每个 .share-post-form 上（兜底）
       只挂 window 是不够的 —— 站点自己的脚本可能在按钮上先
       stopPropagation，那样捕获阶段就轮不到我们（模拟器上实测过：
       点分享毫无反应）。直接绑到 form 上则不受冒泡链路影响。
       两者都做 `.fx-share-bound` 标记，保证不会重复上报。

       注意：这会跳过站点的分享计数。需求明确选了这个方案。 */
    function sharePayload(f){
      var text = f.getAttribute('data-share-text') || '';
      if (!text) {
        var m = (f.getAttribute('action') || '').match(/\/post\/(\d+)/);
        text = '来自表白墙的分享：https://' + location.host
             + (m ? '/post/' + m[1] : location.pathname);
      }
      return text;
    }
    function grabShare(e){
      var f = e.currentTarget || e.target;
      if (!f || !f.classList || !f.classList.contains('share-post-form')) { return; }
      e.preventDefault();
      e.stopPropagation();
      send({type:'share', text: sharePayload(f), subject: '复兴表白墙'});
    }
    function bindShareForms(){
      var forms = document.querySelectorAll('.share-post-form');
      for (var i = 0; i < forms.length; i++) {
        bindOneShareForm(forms[i]);
      }
    }
    /* 单独一个函数：闭包里的 f 必须是这一只 form（循环里直接用 f 会拿到最后一个）。 */
    function bindOneShareForm(f){
      if (!f || f.getAttribute('data-fx-share-bound')) { return; }
      f.setAttribute('data-fx-share-bound', '1');
      f.addEventListener('submit', function(e){
        e.preventDefault();
        e.stopPropagation();
        fireShare(f);
      }, true);
      // ⚠️ 光有 submit 不够：站点自己的脚本可能在**按钮的 click** 上就
      // preventDefault，那样浏览器根本不会生成 submit 事件，我们就永远
      // 等不到（模拟器上实测：点分享毫无反应，而 JS 单测全绿）。
      // 所以按钮的 click 也拦一次；两条路共用一个去重标记，保证只上报一次。
      var btns = f.querySelectorAll('button, input');
      for (var j = 0; j < btns.length; j++) {
        (function(b){
          if (b.getAttribute('data-fx-share-btn')) { return; }
          b.setAttribute('data-fx-share-btn', '1');
          b.addEventListener('click', function(e){
            e.preventDefault();
            e.stopPropagation();
            fireShare(f);
          }, true);
        })(btns[j]);
      }
    }
    /* 去重：click 和 submit 可能都来，只处理第一次。 */
    function fireShare(f){
      if (f.getAttribute('data-fx-shared')) { return; }
      f.setAttribute('data-fx-shared', '1');
      send({type:'share', text: sharePayload(f), subject: '复兴表白墙'});
      setTimeout(function(){ f.removeAttribute('data-fx-shared'); }, 800);
    }
    W.FxWall.bindShareForms = bindShareForms;
    // ⚠️ 这里是 document-start 注入，DOM 还不存在，直接调 querySelectorAll
    // 只会拿到空列表。真正的绑定必须等 DOM 就绪。
    if (document.readyState === 'loading') {
      W.addEventListener('DOMContentLoaded', bindShareForms);
    } else {
      bindShareForms();
    }
    // 站点是服务端渲染整页刷新，但分页/局部刷新可能插入新的分享表单，
    // 所以在 afterPager 之后再补绑定（injectAll 里已调）。
    // 这里只留一条兜底：万一上面那次绑定没赶上（例如表单是后来才插入的），
    // window 捕获阶段再兜一次。已绑定的 form 由它自己的监听处理，
    // 但兜底**仍然执行** —— 双重上报由 fireShare 的去重标记挡掉，
    // 而这比漏报（点了完全没反应）好得多。
    W.addEventListener('submit', function(e){
      var f = e.target;
      if (!f || !f.classList || !f.classList.contains('share-post-form')) { return; }
      e.preventDefault();
      e.stopPropagation();
      fireShare(f);
    }, true);
    W.addEventListener('click', function(e){
      var el = e.target;
      if (!el || !el.closest) { return; }
      var f = el.closest('.share-post-form');
      if (!f) { return; }
      e.preventDefault();
      e.stopPropagation();
      fireShare(f);
    }, true);
  }
})();
''';

  // ------------------------------------------------------------- 指令下发

  /// 一次性把主题 / 圆角 / 背景 / 字号 / 分页 / 举报布局 / 图标全部刷进当前页面。
  ///
  /// 每次导航完成后都要调用：站点是服务端渲染整页刷新，注入的 <style> 会随页面
  /// 一起丢掉。
  Future<void> injectAll(InAppWebViewController controller, {required bool dark}) async {
    if (settings.webTheme) {
      await _injectWebTheme(controller, dark: dark);
      return;
    }

    final String css = await buildCss(dark: dark);
    final String pager = await FxWebAssets.pagerJsFor(settings.pageSize);
    final String layout = await FxWebAssets.layoutFixJs();

    // ⚠️ 这里**再注入一次胶水**（glue），不能只依赖 initialUserScripts。
    //
    // 原因：Windows 的 zikzak_inappwebview_windows 实现**不支持
    // initialUserScripts**（该平台目录里 UserScript 出现 0 次，只实现了
    // evaluateJavascript / addJavaScriptHandler）。于是 window.FxWall
    // 在桌面上根本不存在，所有依赖它的东西（history 上报、卡片进场、
    // 分享拦截、未登录拦截）全部静默失效 —— 表现就是「注入完全没效果」。
    //
    // glue 自身是幂等的（有 W.FxWall._histPatched / _busyPatched 守卫），
    // 重复注入安全，所以 Android 上注入两次也无副作用。
    final String js =
        '$glue\n'
        '(function(){try{\n'
        '  var d=document, h=d.documentElement;\n'
        '  var s=d.getElementById("fx-wall-theme");\n'
        '  if(!s){s=d.createElement("style");s.id="fx-wall-theme";'
        '(d.head||h).appendChild(s);}\n'
        '  s.textContent=${jsonEncode(css)};\n'
        '  h.classList.toggle("fx-dark", ${dark ? 'true' : 'false'});\n'
        '  h.classList.remove("fx-web-dark");\n'
        '  h.classList.remove("fx-motion-key");\n'
        '  h.classList.remove("fx-motion-none");\n'
        '  ${_motionClassJs()}\n'
        '  $pager\n'
        '  $layout\n'
        '  if(window.FxWall&&window.FxWall.afterPager){window.FxWall.afterPager();}\n'
        '  if(window.FxWall&&window.FxWall.bindShareForms){window.FxWall.bindShareForms();}\n'
        '}catch(e){}})();\n'
        'if(window.FxWall&&window.FxWall.send){window.FxWall.send('
        '{type:"ready",path:location.pathname,search:location.search});}';

    await controller.evaluateJavascript(source: js);
  }

  /// 「网页主题」：一个字节的样式都不注入。
  ///
  /// 站点自己的头部、搜索框、最新/最热标签、卡片配色全部原样显示，
  /// 只有原生底部导航是我们加的。
  ///
  /// 两个例外：
  ///   1. 用户明确要求的「深浅色跟随系统」—— 那是叠给整页的深色滤镜，
  ///      不是改站点配色；
  ///   2. 清理上一轮可能注入过的东西（`#fx-wall-theme` / `#fx-pager` /
  ///      被分页器隐藏的卡片），这样从「软件主题」切过来时不用手动清缓存。
  Future<void> _injectWebTheme(InAppWebViewController controller,
      {required bool dark}) async {
    final String js =
        '(function(){try{\n'
        '  var d=document, h=d.documentElement;\n'
        '  var s=d.getElementById("fx-wall-theme");'
        'if(s&&s.parentNode){s.parentNode.removeChild(s);}\n'
        '  var p=d.getElementById("fx-pager");'
        'if(p&&p.parentNode){p.parentNode.removeChild(p);}\n'
        '  var cards=d.querySelectorAll("article.card.post");\n'
        '  for(var i=0;i<cards.length;i++){cards[i].style.display="";'
        'cards[i].classList.remove("fx-card-in");}\n'
        '  h.classList.remove("fx-dark");\n'
        '  h.classList.toggle("fx-web-dark", ${dark ? 'true' : 'false'});\n'
        '  h.classList.remove("fx-motion-key");\n'
        '  h.classList.add("fx-motion-none");\n'
        '  var f=d.getElementById("fx-web-filter");\n'
        '  if(!f){f=d.createElement("style");f.id="fx-web-filter";'
        '(d.head||h).appendChild(f);}\n'
        '  f.textContent=${jsonEncode(settings.webDarkFilterCss)};\n'
        '}catch(e){}})();\n'
        'if(window.FxWall&&window.FxWall.send){window.FxWall.send('
        '{type:"ready",path:location.pathname,search:location.search});}';
    await controller.evaluateJavascript(source: js);
  }

  String _motionClassJs() {
    switch (settings.motionLevel) {
      case 1:
        return 'h.classList.add("fx-motion-key");';
      case 2:
        return 'h.classList.add("fx-motion-none");';
      default:
        return '';
    }
  }

  /// 「网页主题」下不注入任何 CSS，所以直接返回空串。
  Future<String> buildCss({required bool dark}) async {
    if (settings.webTheme) {
      return '';
    }
    final String theme = await FxWebAssets.themeCss();
    return '$theme\n'
        '${FxColors.accentCss(settings.accentIndex)}\n'
        '${settings.radiusCss}\n'
        '${settings.bgCss}\n'
        '${settings.fontCss}';
  }

  // ------------------------------------------------------------- 事件解析

  Object? handleCall(List<Object?> args) {
    if (args.isNotEmpty) {
      final FxWebEvent? e = FxWebEvent.parse(args.first);
      if (e != null) {
        onEvent(e);
      }
    }
    return null;
  }

  /// 判断当前是否真的登录。
  ///
  /// ⚠️ 不要用「cookie 里存在 session」做判据 —— 站点给**每个匿名访客**都会下发
  /// 一个只含 csrf_token 的 session cookie（`curl -I https://www.fxlovewall.me/`
  /// 就能看到），那样判据永远为真，设置页会对未登录用户显示「退出登录」。
  ///
  /// 可靠判据是 DOM 里有没有 logout 表单：站点退出是 POST /logout，
  /// 那个 form 只在登录后渲染。顶栏虽然被 CSS 隐藏，但节点仍在 DOM 里。
  /// （网页主题下顶栏不再被隐藏，但判据本身不变，一样成立。）
  Future<bool> isLoggedIn(InAppWebViewController controller) async {
    try {
      final Object? r = await controller.evaluateJavascript(
        source: "(function(){try{return !!document.querySelector("
            "'form[action*=\"logout\"]');}catch(e){return false;}})()",
      );
      return r.toString().contains('true');
    } catch (_) {
      return false;
    }
  }
}
