import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/fx_motion.dart';
import '../../theme/fx_theme.dart';
import '../../update/fx_update.dart';

/// 更新提示 / 下载进度 / 安装引导（需求 7）。
///
/// 一个弹层走完三态，而不是分三个弹层：`available` → `downloading` →
/// `ready`。这样用户点一次「下载」之后不会被反复打断，进度条也一直在
/// 视线里。
class FxUpdateDialog extends StatefulWidget {
  const FxUpdateDialog({super.key, required this.release});

  final FxRelease release;

  /// 打开并返回是否走完了流程。静默检查用它来判断要不要提示。
  static Future<void> show(BuildContext context, FxRelease release) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => FxUpdateDialog(release: release),
    );
  }

  @override
  State<FxUpdateDialog> createState() => _FxUpdateDialogState();
}

enum _Phase { prompt, downloading, ready, error }

class _FxUpdateDialogState extends State<FxUpdateDialog> {
  _Phase _phase = _Phase.prompt;
  double _progress = 0;
  int _got = 0;
  int _total = 0;
  String _err = '';
  String _apkPath = '';

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _startDownload() async {
    // 桌面端不做「程序内下载 + 自我替换」。
    //
    // 原因：Windows 上 exe 运行时文件被系统锁定，程序**无法覆盖自己**。
    // 要做到得额外写一个更新器进程（下载新版 → 退出主程序 → 替换 → 重启），
    // 那是个独立工程。所以桌面端走更诚实的路径：
    // 打开浏览器到 Release 页，用户自己下载替换。
    if (_isDesktop) {
      await _openReleasePage();
      return;
    }

    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _got = 0;
      _total = widget.release.apkSize;
    });
    try {
      final String path = await FxUpdate.download(
        widget.release,
        onProgress: (int got, int total) {
          if (!mounted) return;
          setState(() {
            _got = got;
            _total = total;
            _progress = total > 0 ? (got / total).clamp(0.0, 1.0) : 0;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _apkPath = path;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _phase = _Phase.error;
      });
    }
  }

  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// 打开 GitHub Release 页（桌面端用）。
  Future<void> _openReleasePage() async {
    final Uri url = Uri.parse(FxUpdateConfig.latestPage);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _err = '无法打开浏览器，请手动访问：\n${FxUpdateConfig.latestPage}';
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _install() async {
    // Android 8.0+ 要求用户先允许「安装未知应用」。没开就先把他送过去，
    // 回来后再点一次「安装」即可 —— 比直接失败友好得多。
    if (!await FxUpdate.canInstall()) {
      if (!mounted) return;
      await FxUpdate.openInstallSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请在本页允许「安装未知应用」，然后回来再点一次「安装」'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    final bool ok = await FxUpdate.install(_apkPath);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法调起安装器，请检查系统设置')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double r = fxRadius(context) * 1.5;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.system_update_alt, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _title(),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._body(cs),
          ],
        ),
      ),
    );
  }

  String _title() {
    switch (_phase) {
      case _Phase.prompt:
        return '发现新版本 ${widget.release.version}';
      case _Phase.downloading:
        return '正在下载…';
      case _Phase.ready:
        return '下载完成';
      case _Phase.error:
        return '下载失败';
    }
  }

  List<Widget> _body(ColorScheme cs) {
    switch (_phase) {
      case _Phase.prompt:
        return <Widget>[
          if (widget.release.notes.trim().isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: SingleChildScrollView(
                child: Text(
                  widget.release.notes.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (widget.release.apkSize > 0 && !_isDesktop)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '安装包 ${_fmtSize(widget.release.apkSize)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          if (_isDesktop)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '当前平台不支持应用内自动更新（程序无法替换正在运行的自身）。'
                '点击下方按钮会打开下载页，手动下载新版覆盖即可。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('稍后'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startDownload,
                child: Text(_isDesktop ? '打开下载页' : '下载更新'),
              ),
            ],
          ),
        ];

      case _Phase.downloading:
        return <Widget>[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text('${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(
                _total > 0
                    ? '${_fmtSize(_got)} / ${_fmtSize(_total)}'
                    : _fmtSize(_got),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('后台下载中…先关闭'),
            ),
          ),
        ];

      case _Phase.ready:
        return <Widget>[
          Text(
            '安装包已保存：「${widget.release.apkName}」\n'
            '点击「安装」后系统会弹出安装确认；'
            '若提示「禁止安装未知应用」，请允许后再点一次。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _install,
                icon: const Icon(Icons.download_done, size: 18),
                label: const Text('安装'),
              ),
            ],
          ),
        ];

      case _Phase.error:
        return <Widget>[
          Text(
            _err.isEmpty ? '未知错误' : _err,
            style: TextStyle(fontSize: 13, height: 1.5, color: cs.error),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startDownload,
                child: const Text('重试'),
              ),
            ],
          ),
        ];
    }
  }
}

/// 「已是最新」/「检查失败」的轻提示。用 SnackBar 而不是 Dialog ——
/// 用户主动点了「检查更新」，一个短提示就够，不该再弹一个要按确定的框。
void showUpdateToast(BuildContext context, FxUpdateResult r) {
  final String msg;
  switch (r.status) {
    case FxUpdateStatus.upToDate:
      msg = '已是最新版本';
    case FxUpdateStatus.available:
      msg = '发现新版本 ${r.release?.version ?? ''}';
    case FxUpdateStatus.failed:
      msg = r.message == '未配置更新仓库'
          ? '更新检查尚未配置'
          : '检查更新失败：${r.message ?? '未知原因'}';
  }
  final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: FxMotion.off
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 1900),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 22),
    ),
  );
}
