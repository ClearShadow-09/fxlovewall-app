import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 与原生通道（android/app/src/main/kotlin/.../MainActivity.kt）的约定。
///
/// 通道名与「清除缓存」「分享」「安装 APK」共用，所以集中在这里定义，
/// 别处不要再写字面量。
const MethodChannel kDeviceChannel = MethodChannel('com.fxlovewall.app/device');

/// 版本更新的配置。
///
/// 更新走 GitHub Releases：应用查 `releases/latest`，比对版本号，
/// 有新版本就按平台分流处理（见 [FxUpdate.check] 与更新对话框）。
class FxUpdateConfig {
  FxUpdateConfig._();

  static const String repoOwner = 'ClearShadow-09';
  static const String repoName = 'fxlovewall-app';

  static bool get configured => repoOwner.trim().isNotEmpty;

  /// GitHub 的 latest release 接口。公开仓库不需要 token。
  static String get latestApi =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// 仓库主页，用于「查看全部版本」。
  static String get releasesPage =>
      'https://github.com/$repoOwner/$repoName/releases';

  /// Release 页（用户手动下载入口）。
  static String get latestPage =>
      'https://github.com/$repoOwner/$repoName/releases/latest';

  /// 仓库地址。
  static String get repoUrl => 'https://github.com/$repoOwner/$repoName';
}

/// 版本号：把 "1.2.0-beta-debug" / "v1.2.0" 这类字符串拆成可比较的数字段。
///
/// 刻意只取开头的 `数字.数字.数字`，后缀（beta / debug / rc1）不参与比较 ——
/// 需求里的版本命名是「1.2.0-beta-debug」这种，后缀表达的是构建渠道而不是
/// 新旧顺序，拿它去比大小只会得出反直觉的结果。
class FxVersion implements Comparable<FxVersion> {
  const FxVersion(this.parts, this.raw);

  final List<int> parts;
  final String raw;

  static FxVersion parse(String s) {
    final Match? m = RegExp(r'\d+(?:\.\d+)*').firstMatch(s);
    if (m == null) return FxVersion(const <int>[], s);
    final List<int> p = m.group(0)!.split('.').map(int.parse).toList();
    return FxVersion(p, s);
  }

  bool get isUsable => parts.isNotEmpty;

  @override
  int compareTo(FxVersion other) {
    final int n = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (int i = 0; i < n; i++) {
      final int a = i < parts.length ? parts[i] : 0;
      final int b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  @override
  String toString() => raw;
}

/// 一次「发现的新版本」。
class FxRelease {
  const FxRelease({
    required this.tag,
    required this.title,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
  });

  final String tag;
  final String title;
  final String notes;
  final String apkUrl;
  final String apkName;
  final int apkSize;

  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');
}

/// 当前安装的版本信息。
class FxAppVersion {
  const FxAppVersion({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;

  /// 编译期常量：桌面端（Windows/macOS/Linux）没有那个原生方法通道，
  /// 读不到 packageManager，所以直接用构建时注入的版本号。
  ///
  /// ⚠️ 必须与 pubspec.yaml 的 `version:` 保持一致。
  /// 改版本号时两处都要改（build_apk.ps1 会校验，不一致就报错）。
  static const String kBuildVersionName = '1.2.5-release';
  static const int kBuildVersionCode = 10205;

  static FxAppVersion unknown = const FxAppVersion(
    versionName: '未知',
    versionCode: 0,
  );

  /// 读当前版本。
  ///
  /// 安卓：走原生通道读 packageManager（能反映真实安装的版本）。
  /// 桌面：没有该通道，用编译期常量 [kBuildVersionName]。
  ///
  /// 之前桌面端直接退化成「未知」—— 因为通道调用抛异常被 catch 掉了。
  /// 现在按平台分流，桌面端至少能显示正确的版本号，更新检查也能比对。
  static Future<FxAppVersion> read() async {
    if (_isDesktopPlatform) {
      return const FxAppVersion(
        versionName: kBuildVersionName,
        versionCode: kBuildVersionCode,
      );
    }
    try {
      final Map<Object?, Object?>? r =
          await kDeviceChannel.invokeMethod<Map<Object?, Object?>>('appVersion');
      if (r == null) {
        return const FxAppVersion(
          versionName: kBuildVersionName,
          versionCode: kBuildVersionCode,
        );
      }
      return FxAppVersion(
        versionName: (r['versionName'] as String?) ?? kBuildVersionName,
        versionCode: (r['versionCode'] as num?)?.toInt() ?? kBuildVersionCode,
      );
    } catch (_) {
      // 通道不可用（含桌面端、非 Android）→ 退回编译期常量，不再显示「未知」
      return const FxAppVersion(
        versionName: kBuildVersionName,
        versionCode: kBuildVersionCode,
      );
    }
  }
}

/// 当前是否桌面平台。与 home_shell 的判据保持一致。
bool get _isDesktopPlatform {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

/// 检查更新 + 下载新版 APK（需求 7）。
class FxUpdate {
  FxUpdate._();

  /// 查 GitHub 的最新 release。
  ///
  /// 返回值语义：
  ///   · [FxUpdateResult.upToDate]  已是最新
  ///   · [FxUpdateResult.available] 有新版本（[release] 非空）
  ///   · [FxUpdateResult.failed]    查不到（没网 / 未配置仓库 / 限流）
  ///
  /// 刻意不抛异常：调用方（启动时的静默检查）需要区分「没有新版」和
  /// 「查不了」，但都不该打断用户。
  static Future<FxUpdateResult> check() async {
    if (!FxUpdateConfig.configured) {
      return const FxUpdateResult(FxUpdateStatus.failed,
          message: '未配置更新仓库');
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(FxUpdateConfig.latestApi));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'fxlovewall-app');
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != 200) {
        return FxUpdateResult(FxUpdateStatus.failed,
            message: 'GitHub 返回 ${resp.statusCode}');
      }
      final String body = await resp.transform(utf8.decoder).join();
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const FxUpdateResult(FxUpdateStatus.failed, message: '响应格式异常');
      }
      final FxRelease? rel = _parseRelease(decoded);
      if (rel == null) {
        return const FxUpdateResult(FxUpdateStatus.failed,
            message: '该版本没有附带 APK');
      }
      final FxAppVersion cur = await FxAppVersion.read();
      final FxVersion mine = FxVersion.parse(cur.versionName);
      final FxVersion theirs = FxVersion.parse(rel.tag);
      if (!mine.isUsable || !theirs.isUsable) {
        return const FxUpdateResult(FxUpdateStatus.failed, message: '版本号无法解析');
      }
      if (theirs.compareTo(mine) > 0) {
        return FxUpdateResult(FxUpdateStatus.available, release: rel);
      }
      return FxUpdateResult(FxUpdateStatus.upToDate, release: rel);
    } catch (e) {
      return FxUpdateResult(FxUpdateStatus.failed, message: '$e');
    } finally {
      client.close(force: true);
    }
  }

  static FxRelease? _parseRelease(Map<Object?, Object?> m) {
    final String tag = (m['tag_name'] as String?) ?? '';
    final String name = (m['name'] as String?) ?? tag;
    final String notes = (m['body'] as String?) ?? '';
    final Object? assets = m['assets'];
    if (assets is! List) return null;

    // 按平台挑合适的产物：
    //   安卓 → .apk（应用内下载 + 调系统安装器）
    //   Windows → .zip（打开浏览器手动下载覆盖）
    //   iOS   → 不做自动更新（苹果不允许应用自更新），所以随便一个即可，
    //            只为让「有新版本」的提示能弹出来。
    final List<String> prefer;
    if (Platform.isWindows) {
      prefer = <String>['.zip'];
    } else if (Platform.isAndroid) {
      prefer = <String>['.apk'];
    } else {
      // iOS / macOS / Linux：apk 与 zip 都认，只要能提示版本
      prefer = <String>['.apk', '.zip'];
    }

    for (final String ext in prefer) {
      for (final Object? a in assets) {
        if (a is! Map) continue;
        final String an = (a['name'] as String?) ?? '';
        final String url = (a['browser_download_url'] as String?) ?? '';
        if (an.toLowerCase().endsWith(ext) && url.isNotEmpty) {
          return FxRelease(
            tag: tag,
            title: name,
            notes: notes,
            apkUrl: url,
            apkName: an,
            apkSize: (a['size'] as num?)?.toInt() ?? 0,
          );
        }
      }
    }
    // 一个都没匹配上：仍然返回版本信息，让「有新版本」能提示，
    // 只是没有可直接下载的产物（用户点按钮会走 Release 页）。
    return FxRelease(
      tag: tag,
      title: name,
      notes: notes,
      apkUrl: '',
      apkName: '',
      apkSize: 0,
    );
  }

  /// 下载 APK 到 `cacheDir/fxupdate/`，返回文件绝对路径。
  ///
  /// 目录必须与 res/xml/fx_file_paths.xml 里 FileProvider 暴露的路径一致，
  /// 否则安装时抛 IllegalArgumentException。
  static Future<String> download(
    FxRelease release, {
    required void Function(int received, int total) onProgress,
  }) async {
    final String? cache = await kDeviceChannel.invokeMethod<String>('cacheDir');
    if (cache == null || cache.isEmpty) {
      throw const FileSystemException('拿不到缓存目录');
    }
    final Directory dir = Directory('$cache/fxupdate');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // 先清掉上一次的残留，免得攒一堆几十兆的旧包
    try {
      for (final FileSystemEntity e in dir.listSync()) {
        if (e is File && e.path.endsWith('.apk')) e.deleteSync();
      }
    } catch (_) {}

    final String outPath = '${dir.path}/${release.apkName}';
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(release.apkUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'fxlovewall-app');
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('下载失败 HTTP ${resp.statusCode}');
      }
      final int total = resp.contentLength > 0
          ? resp.contentLength
          : release.apkSize;
      final File f = File(outPath);
      sink = f.openWrite();
      int got = 0;
      int lastTick = 0;
      await for (final List<int> chunk in resp) {
        sink.add(chunk);
        got += chunk.length;
        // 每 256KB 报一次，避免每几十字节就 setState 一次把 UI 拖垮
        if (got - lastTick >= 256 * 1024) {
          lastTick = got;
          onProgress(got, total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress(got, total);
      return outPath;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client.close(force: true);
    }
  }

  /// 把下载好的 APK 交给系统安装器。返回是否成功调起。
  static Future<bool> install(String path) async {
    try {
      final bool? ok = await kDeviceChannel
          .invokeMethod<bool>('installApk', <String, Object?>{'path': path});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 系统是否允许安装未知来源应用（Android 8.0+）。
  static Future<bool> canInstall() async {
    try {
      return await kDeviceChannel.invokeMethod<bool>('canInstallPackages') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// 跳到「安装未知应用」的系统设置页。
  static Future<void> openInstallSettings() async {
    try {
      await kDeviceChannel.invokeMethod<bool>('openInstallSettings');
    } catch (_) {}
  }

  /// 呼出系统分享面板（需求 5）。
  ///
  /// [copy] = true 时先把文案复制到剪贴板 —— 原网页的分享行为就是「复制链接」，
  /// 软件在复制的基础上再弹分享框（用户明确要求的行为）。
  /// 复制走原生 ClipboardManager，不依赖网页的 navigator.clipboard
  /// （后者要求安全上下文 + 用户手势，在 WebView 里经常静默失败）。
  ///
  /// ⚠️ 桌面端没有那个 Android 方法通道，必须走另一条路：
  /// Windows 没有系统级「分享面板」这个统一 API（那是移动端概念），
  /// 所以对桌面端的合理等价物是：**复制到剪贴板 + 用系统默认程序打开分享页**。
  /// 这里用 `start` 打开系统自带的分享 UI 不可行，改为复制并给出提示，
  /// 由调用方决定提示文案。
  static Future<bool> share(
    String text, {
    String subject = '',
    bool copy = true,
  }) async {
    if (_isDesktopPlatform) {
      return _shareDesktop(text);
    }
    try {
      final bool? ok = await kDeviceChannel.invokeMethod<bool>(
        'share',
        <String, Object?>{
          'text': text,
          'subject': subject,
          'copy': copy,
        },
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 把字符串编码成 Windows 系统 ANSI 代码页（中文系统 = GBK）的字节。
  ///
  /// 为什么需要：`clip.exe` 按系统 ANSI 代码页解释 stdin，喂 UTF-8 会乱码
  /// （实测 `来自表白墙…` → `鏉ヨ嚜琛ㄧ櫧澧欑殑…`，正是 UTF-8 被当 GBK 读）。
  ///
  /// **实现注意**：不能让 PowerShell 把字节写到 stdout 再读回来 ——
  /// `Process.runSync` 在拿到非 UTF-8 字节时会解码失败，于是我们只能退回
  /// UTF-8，乱码照旧（这是第一次尝试失败的原因）。
  ///
  /// 改为：让 PowerShell 把 ANSI 字节**写成十六进制字符串**（纯 ASCII，
  /// 怎么传都不会坏），Dart 侧再解析回字节。
  static List<int> _encodeForAnsi(String s) {
    final String b64 = base64Encode(utf8.encode(s));
    final String script = r'''
$ErrorActionPreference = 'Stop'
$bytes = [Convert]::FromBase64String('__B64__')
$text = [Text.Encoding]::UTF8.GetString($bytes)
$ansi = [Text.Encoding]::Default
$out = $ansi.GetBytes($text)
# 输出为十六进制字符串：纯 ASCII，跨编码传输绝对安全
($out | ForEach-Object { $_.ToString('x2') }) -join ''
'''
        .replaceFirst('__B64__', b64);
    // PowerShell 的 -EncodedCommand 接收 UTF-16LE 的 Base64
    final List<int> enc = <int>[];
    for (final int u in script.codeUnits) {
      enc.add(u & 0xFF);
      enc.add((u >> 8) & 0xFF);
    }
    final String encoded = base64Encode(enc);

    final ProcessResult r = Process.runSync(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
    );
    if (r.exitCode != 0) {
      throw StateError('ansi encode failed: ${r.stderr}');
    }
    final String hex = (r.stdout as String).trim();
    if (hex.isEmpty || hex.length.isOdd) {
      throw StateError('ansi encode produced bad hex: [$hex]');
    }
    final List<int> out = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// 桌面端的「分享」。
  ///
  /// Windows / macOS / Linux 都没有移动端那种系统分享面板，所以这里做
  /// 两件实际有意义的事：
  ///   1. 把文本写进系统剪贴板（与原网页的行为一致 —— 站点本来也是复制链接）
  ///   2. 返回 true 让 UI 提示「已复制」
  ///
  /// 为什么不硬凑一个分享框：在桌面上伪造一个「仿移动端」的分享面板反而
  /// 更差 —— 用户真正想要的是把链接发给别人，复制走人是最直接的路径。
  static Future<bool> _shareDesktop(String text) async {
    final String t = text.trim();
    if (t.isEmpty) return false;
    try {
      if (Platform.isWindows) {
        // ⚠️ Windows 写中文剪贴板踩过的坑（按顺序）：
        //   1. `clip.exe` + UTF-8 stdin → 中文乱码（它按 ANSI/GBK 解释 stdin）
        //   2. `powershell Set-Clipboard -Value $args[0]` → 命令行转义问题，返回非 0
        //   3. `powershell Set-Clipboard` 从文件读 → 本机实测
        //      "Requested Clipboard operation did not succeed"
        //      （PowerShell 默认不是 STA 线程，剪贴板 API 会失败）
        //
        // 所以回到最稳的 clip.exe，但**先把文本转成系统 ANSI 代码页的字节**
        // 再喂给它 —— 这样它按 GBK 解出来的就是正确的中文。
        // 代码页 936 = GBK（简体中文 Windows 的默认）。
        final List<int> bytes;
        try {
          bytes = _encodeForAnsi(t);
        } catch (_) {
          // 取不到系统代码页就退回 UTF-8（英文/数字仍然正确）
          final Process p = await Process.start('clip.exe', const <String>[]);
          p.stdin.add(utf8.encode(t));
          await p.stdin.close();
          return (await p.exitCode) == 0;
        }
        final Process p = await Process.start('clip.exe', const <String>[]);
        p.stdin.add(bytes);
        await p.stdin.close();
        return (await p.exitCode) == 0;
      }
      if (Platform.isMacOS) {
        final Process p = await Process.start('pbcopy', const <String>[]);
        p.stdin.add(utf8.encode(t));
        await p.stdin.close();
        return (await p.exitCode) == 0;
      }
      // Linux：优先 xclip，退回 xsel
      for (final String cmd in <String>['xclip', 'xsel']) {
        try {
          final List<String> args = cmd == 'xclip'
              ? <String>['-selection', 'clipboard']
              : <String>['--clipboard', '--input'];
          final Process p = await Process.start(cmd, args);
          p.stdin.add(utf8.encode(t));
          await p.stdin.close();
          if ((await p.exitCode) == 0) return true;
        } catch (_) {
          continue;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

enum FxUpdateStatus { upToDate, available, failed }

class FxUpdateResult {
  const FxUpdateResult(this.status, {this.release, this.message});

  final FxUpdateStatus status;
  final FxRelease? release;
  final String? message;
}
