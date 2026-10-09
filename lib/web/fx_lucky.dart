import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 「今日幸运物品」的原生实现。
///
/// ## 为什么从网页 fetch 改成原生
///
/// 原来是在 WebView 里 `evaluateJavascript` 跑一段 fetch，靠 `window.FxWall`
/// 回传结果。实测点了没反应，而且有两个结构性缺点：
///
///   1. **依赖注入成功**。`window.FxWall` 是 document-start 注入的胶水，
///      页面一旦被替换（bfcache、站点自己 pushState），那段 JS 就不在了，
///      点了静默失败 —— 用户看到的就是「没反应」。
///   2. **依赖页面上那个表单还在**。csrf_token 要从
///      `#daily-lucky-item-form` 读，而它在首页的 .lucky-post-entry 里、
///      被我们的 CSS 隐藏了；首页以外的页面根本没有它。
///
/// ## ⚠️ 关键：必须复用 WebView 的 Cookie
///
/// `dart:io` 的 `HttpClient` 有**自己独立的 cookie jar**，和 WebView 完全不通。
/// 如果直接用它发请求，拿到的是一份全新的匿名会话 —— 用户明明登录了，
/// 接口也会把他当未登录（实测未登录时服务端返回 400 + 一整页 HTML）。
///
/// 所以必须先通过插件读 WebView 的 cookie，再把它们塞进请求头
/// （见 [cookiesProvider]）。同时要把新拿到的 `Set-Cookie` 写回 WebView，
/// 否则站点轮换 session 之后两边就不一致了。
class FxLucky {
  FxLucky._();

  static const String _host = 'www.fxlovewall.me';
  static const String _base = 'https://$_host';

  /// 抽取。
  ///
  /// [cookiesProvider] 返回当前 WebView 里本站的 cookie（形如 `a=1; b=2`）。
  /// [onSetCookie] 在服务端下发新 cookie 时回调，由调用方写回 WebView。
  static Future<FxLuckyResult> draw({
    required Future<String> Function() cookiesProvider,
    required Future<void> Function(Uri url, String setCookie) onSetCookie,
  }) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      // 1) 取 token（带上 WebView 的 cookie，保证和用户当前会话一致）
      final String cookie = await cookiesProvider();
      final String? token = await _fetchToken(client, cookie);
      if (token == null) {
        return const FxLuckyResult(false, '拿不到会话令牌，请检查网络后重试。');
      }

      // 2) 提交抽取
      final Uri url = Uri.parse('$_base/daily-lucky-item');
      final HttpClientRequest req = await client.postUrl(url);
      req.headers.set(HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded');
      req.headers.set('X-Requested-With', 'XMLHttpRequest');
      req.headers.set(HttpHeaders.userAgentHeader, 'fxlovewall-app');
      if (cookie.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      req.write('csrf_token=${Uri.encodeQueryComponent(token)}');

      final HttpClientResponse resp = await req.close();
      await _persistCookies(resp, url, onSetCookie);
      final String body = await resp.transform(utf8.decoder).join();

      // 3) 未登录时服务端不返回 JSON（实测 400 + 一整页 HTML）。
      //    所以判据用「响应体像不像 JSON」，比看状态码稳。
      if (!_looksLikeJson(resp, body)) {
        return const FxLuckyResult(false, '请先登录后再抽今日幸运物品。');
      }

      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const FxLuckyResult(false, '服务端返回了无法识别的结果。');
      }
      final bool ok = decoded['ok'] == true;
      final String msg = (decoded['message'] as String?)?.trim() ?? '';
      if (ok && msg.isNotEmpty) {
        return FxLuckyResult(true, msg);
      }
      return FxLuckyResult(
        false,
        msg.isNotEmpty ? msg : '暂时无法抽取，请稍后再试。',
      );
    } catch (e) {
      return const FxLuckyResult(false, '网络好像开小差了，再点一次。');
    } finally {
      client.close(force: true);
    }
  }

  /// 从首页 HTML 里抠 csrf_token。
  ///
  /// 站点每个表单都带同一个 token（隐藏 input），任意取一个即可。
  /// 匿名访客也有 —— 站点会给所有访客下发只含 csrf_token 的 session cookie，
  /// 所以这一步未登录时同样能成功；区分登录与否的是第 2 步的响应。
  static Future<String?> _fetchToken(HttpClient client, String cookie) async {
    final HttpClientRequest req = await client.getUrl(Uri.parse('$_base/'));
    req.headers.set(HttpHeaders.userAgentHeader, 'fxlovewall-app');
    if (cookie.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, cookie);
    }
    final HttpClientResponse resp = await req.close();
    if (resp.statusCode != 200) return null;
    final String html = await resp.transform(utf8.decoder).join();
    final RegExpMatch? m = RegExp(
      r'name="csrf_token"\s+value="([^"]+)"',
    ).firstMatch(html);
    return m?.group(1);
  }

  /// 把响应的 Set-Cookie 交回给 WebView，保持两边会话一致。
  static Future<void> _persistCookies(
    HttpClientResponse resp,
    Uri url,
    Future<void> Function(Uri, String) onSetCookie,
  ) async {
    try {
      final List<String> raw = resp.headers[HttpHeaders.setCookieHeader] ??
          const <String>[];
      for (final String c in raw) {
        await onSetCookie(url, c);
      }
    } catch (_) {
      // cookie 写回失败不该让整次抽取失败
    }
  }

  static bool _looksLikeJson(HttpClientResponse resp, String body) {
    final String ct = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
    if (ct.contains('json')) return true;
    final String t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }
}

/// 抽取结果。[message] 成功时就是那句「今日请注意……」。
class FxLuckyResult {
  const FxLuckyResult(this.ok, this.message);

  final bool ok;
  final String message;
}
