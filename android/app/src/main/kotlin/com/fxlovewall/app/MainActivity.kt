package com.fxlovewall.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.WebStorage
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 注意：包名必须与 android/app/build.gradle.kts 里的 `namespace` 一致。
///
/// AndroidManifest 里写的是 android:name=".MainActivity"，这个相对名是相对
/// **namespace**（com.fxlovewall.app）解析的，不是相对 applicationId。
/// 之前 flutter create 生成的是 com.fxlovewall.fxwall.MainActivity，
/// 与 namespace 不符，启动时直接 ClassNotFoundException 闪退。
///
/// 方法通道 `com.fxlovewall.app/device` 负责四件事：
///   1. appVersion    —— 读 packageManager 的 versionName/versionCode
///                        （避免为此引入 package_info_plus 依赖，省体积）
///   2. cacheSize / clearWebStorage —— 量/清网页缓存（需求 16）
///   3. share         —— 呼出系统分享面板（需求 5）
///   4. installApk    —— 调起系统安装器（需求 7）
///
/// ⚠️ 这里**绝不碰 Cookie**。清 Cookie 会把用户踢下线，而需求明确要求
/// 「清除缓存不能退出登录」。WebStorage.deleteAllData() 清的是
/// localStorage / IndexedDB / WebSQL，会话 Cookie 不受影响。
class MainActivity : FlutterActivity() {

    private val channelName = "com.fxlovewall.app/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appVersion" -> result.success(appVersionInfo())

                    // 需求 7：下载 APK 要落在 cacheDir/fxupdate/ 下 ——
                    // 那个目录必须与 res/xml/fx_file_paths.xml 里 FileProvider
                    // 声明的路径一致，否则安装时 getUriForFile 会抛
                    // IllegalArgumentException。
                    // 从原生拿路径，省掉 path_provider 依赖（省体积）。
                    "cacheDir" -> result.success(applicationContext.cacheDir?.absolutePath)

                    "cacheSize" -> result.success(cacheSize())
                    "clearWebStorage" -> {
                        clearWebStorage()
                        result.success(null)
                    }

                    "share" -> {
                        val text = call.argument<String>("text").orEmpty()
                        val subject = call.argument<String>("subject").orEmpty()
                        // 需求 2：原网页的分享是「把链接复制到剪贴板」，
                        // 软件在此基础上再弹出系统分享框。
                        // 复制走原生 ClipboardManager 而不是网页的
                        // navigator.clipboard —— 后者要求安全上下文 + 用户手势，
                        // 在 WebView 里经常静默失败。
                        val copy = call.argument<Boolean>("copy") ?: true
                        if (copy) { copyToClipboard(text) }
                        result.success(shareText(text, subject))
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path").orEmpty()
                        result.success(installApk(path))
                    }

                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> result.success(openInstallSettings())

                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------ 版本号

    private fun appVersionInfo(): Map<String, Any> {
        val pm = packageManager
        val info = pm.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to code,
            "packageName" to packageName,
        )
    }

    // ------------------------------------------------------------ 网页缓存

    /// WebView 的数据目录。Chromium 把 HTTP 缓存放在
    /// `<dataDir>/app_webview/Default/HTTP Cache`。
    ///
    /// ⚠️ 刻意**只量网页缓存**，不含 Context.cacheDir（那是 Flutter 引擎、
    /// 图片解码等 app 私有缓存）。原先把 cacheDir 也算进去，报出来的数字
    /// 又大又和「清除网页缓存」这个说法对不上。
    private fun webViewDataDirs(): List<File> {
        val ctx = applicationContext
        val out = ArrayList<File>(2)
        // /data/data/<pkg>/files/.. == /data/data/<pkg>
        ctx.filesDir?.parentFile?.let { out.add(File(it, "app_webview")) }
        try {
            out.add(ctx.getDir("webview", MODE_PRIVATE))
        } catch (_: Throwable) {
            // 某些设备没有这个目录，忽略
        }
        return out
    }

    private fun sizeOf(f: File?): Long {
        if (f == null || !f.exists()) return 0L
        if (f.isFile) return f.length()
        val kids = f.listFiles() ?: return 0L
        var sum = 0L
        for (k in kids) sum += sizeOf(k)
        return sum
    }

    private fun cacheSize(): Long {
        var total = 0L
        for (d in webViewDataDirs()) total += sizeOf(d)
        return total
    }

    private fun clearWebStorage() {
        try {
            WebStorage.getInstance().deleteAllData()
        } catch (_: Throwable) {
            // 老机型上偶尔抛，忽略：Dart 侧还会调插件的 clearAllCache()
        }
    }

    // ------------------------------------------------------------ 分享

    /// 复制纯文本到系统剪贴板。
    private fun copyToClipboard(text: String) {
        if (text.isBlank()) return
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("复兴表白墙", text))
        } catch (_: Throwable) {
            // 剪贴板被系统限制时忽略：分享框仍然会弹，用户还能手动复制
        }
    }

    /// 呼出系统分享面板（需求 5）。
    ///
    /// 用 createChooser 而不是裸 ACTION_SEND：保证用户看到的是一张选择表，
    /// 也保证在没有可分享目标时不会因 ActivityNotFoundException 崩掉。
    private fun shareText(text: String, subject: String): Boolean {
        if (text.isBlank()) return false
        return try {
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                if (subject.isNotBlank()) putExtra(Intent.EXTRA_SUBJECT, subject)
            }
            val chooser = Intent.createChooser(send, "分享到").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (e: Throwable) {
            false
        }
    }

    // ------------------------------------------------------------ 安装 APK

    /// 系统是否允许本应用安装未知来源的应用（Android 8.0+）。
    private fun canInstallPackages(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return try {
            packageManager.canRequestPackageInstalls()
        } catch (_: Throwable) {
            true
        }
    }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /// 调起系统安装器（需求 7）。
    ///
    /// 必须走 FileProvider：Android 7.0 起用 file:// 传 APK 会抛
    /// FileUriExposedException。authority 与 AndroidManifest 里声明的一致。
    private fun installApk(path: String): Boolean {
        val f = File(path)
        if (!f.exists() || !f.isFile) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(view)
            true
        } catch (e: Throwable) {
            false
        }
    }
}
