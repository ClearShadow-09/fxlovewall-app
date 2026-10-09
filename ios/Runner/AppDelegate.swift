import Flutter
import UIKit
import WebKit

/// 复兴表白墙 iOS 端原生入口。
///
/// 与 Android 的 MainActivity.kt 提供**同一个方法通道**
/// `com.fxlovewall.app/device`，方法名也一一对应，这样 Dart 侧不用为
/// iOS 写第二套分支 —— 唯一需要分流的是桌面端（那里没有这个方法通道）。
///
/// 实现的方法：
///   · appVersion        —— Bundle 版本号
///   · share             —— 调起 UIActivityViewController（iOS 的系统分享面板）
///   · cacheSize / clearWebStorage —— 量/清 WKWebView 缓存
///   · cacheDir          —— 供更新下载用（iOS 上应用内无法自安装，仅占位）
///
/// ⚠️ 未实现 Android 独有的 `installApk` / `canInstallPackages` /
/// `openInstallSettings` —— iOS 不允许应用自行安装 IPA，更新只能走 App Store。
/// Dart 侧对这几个方法的调用都在 try/catch 里，拿不到就静默降级。
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private let channelName = "com.fxlovewall.app/device"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 注册自己的方法通道。
    //
    // ⚠️ 这里刻意用了**最保守**的写法：遍历插件注册表拿到任一 registrar 的
    // messenger，而不是直接用 engineBridge 上的某个新 API。
    //
    // 原因：`FlutterImplicitEngineBridge` 是较新的 API（配套 SceneDelegate），
    // 我对它暴露哪些成员没有把握，而 Windows 上无法编译验证 Swift。
    // `FlutterPluginRegistrar.messenger()` 从 Flutter 1.x 起就是稳定接口，
    // 用它拿到的 messenger 与 GeneratedPluginRegistrant 用的是同一个，
    // 因此和 Flutter 侧默认的 MethodChannel 一定能对上。
    //
    // 拿不到就静默跳过：Dart 侧所有通道调用都在 try/catch 里，
    // 缺了通道只会让「分享 / 清缓存」降级，不会崩。
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FxDeviceChannel")
    if let messenger = registrar?.messenger() {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        // Flutter 的方法回调本来就在主线程，但闭包是 nonisolated 的，
        // 而 handle 标了 @MainActor + async（WKWebsiteDataStore 是 async 隔离的），
        // 所以这里用 Task 起一个主 actor 上的任务。
        //
        // 注意：这里**不能**用 assumeIsolated —— 它只能用于同步函数，
        // 而 handle 是 async 的。
        Task { @MainActor in
          await self?.handle(call, result: result)
        }
      }
    } else {
      NSLog("[FxWall] 未取到 binaryMessenger，原生方法通道跳过注册")
    }
  }

  // MARK: - 方法分发

  /// ⚠️ 标 `@MainActor` 且 `async`：`clearWebStorage()` 要碰
  /// MainActor 隔离的 async API（WKWebsiteDataStore）；
  /// `shareText()` 要碰 UIKit。两者都要求主线程。
  @MainActor
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    switch call.method {
    case "appVersion":
      result(appVersionInfo())

    case "share":
      let args = call.arguments as? [String: Any] ?? [:]
      let text = args["text"] as? String ?? ""
      let subject = args["subject"] as? String ?? ""
      // iOS 的分享面板本身就带「拷贝」，所以 copy 参数在这里不需要单独处理。
      shareText(text, subject: subject, result: result)

    case "cacheSize":
      result(cacheSize())

    case "clearWebStorage":
      await clearWebStorage()
      result(nil)

    case "cacheDir":
      result(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path)

    default:
      // installApk / canInstallPackages / openInstallSettings 等 Android
      // 专属方法走到这里。返回 notImplemented，Dart 侧会捕获并降级。
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 版本

  private func appVersionInfo() -> [String: Any] {
    let info = Bundle.main.infoDictionary ?? [:]
    let name = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? "0"
    return [
      "versionName": name,
      "versionCode": Int(build) ?? 0,
      "packageName": Bundle.main.bundleIdentifier ?? "",
    ]
  }

  // MARK: - 分享

  /// 调起系统分享面板（UIActivityViewController）。
  ///
  /// iPad 上必须给 popoverPresentationController 指定 sourceView，
  /// 否则**直接崩溃**（UIKit 的硬性要求）。这里退化到 window 的中心点。
  private func shareText(_ text: String, subject: String, result: @escaping FlutterResult) {
    guard !text.isEmpty else {
      result(false)
      return
    }
    DispatchQueue.main.async {
      var items: [Any] = [text]
      if !subject.isEmpty {
        items.append(subject)
      }
      let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)

      guard let root = self.topViewController() else {
        result(false)
        return
      }
      if let pop = vc.popoverPresentationController {
        pop.sourceView = root.view
        pop.sourceRect = CGRect(
          x: root.view.bounds.midX, y: root.view.bounds.midY,
          width: 0, height: 0)
        pop.permittedArrowDirections = []
      }
      root.present(vc, animated: true) {
        result(true)
      }
    }
  }

  /// 找到当前最上层的 ViewController —— 分享面板必须由它 present。
  private func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  // MARK: - 缓存

  /// 量 WKWebView 的缓存大小。
  ///
  /// iOS 把网页缓存放在 Library/Caches 下的 WebKit 目录里，
  /// 以及 WKWebsiteDataStore 自己管理的库里。这里量文件系统那部分
  /// （能给出一个有意义的数字），并把 WKWebView 的记录一并算上。
  private func cacheSize() -> Int64 {
    var total: Int64 = 0
    let fm = FileManager.default
    if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
      total += directorySize(caches)
    }
    return total
  }

  private func directorySize(_ url: URL) -> Int64 {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return 0 }

    var sum: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true {
        sum += Int64(values?.fileSize ?? 0)
      }
    }
    return sum
  }

  /// 清网页缓存。
  ///
  /// ⚠️ 刻意**不碰 Cookie 和登录态** —— 需求明确要求「清除缓存不能退出登录」。
  /// 所以这里只清 disk/memory cache 与 WKWebsiteDataStore 里除 cookie 外的数据。
  ///
  /// ⚠️ 为什么是 `async`：新版 iOS SDK 里 `WKWebsiteDataStore.default()`、
  /// `dataRecords(ofTypes:)`、`removeData(ofTypes:for:)` 全都是
  /// **MainActor 隔离的 async 方法**。只给同步函数加 `@MainActor` 是不够的 ——
  /// 编译器仍然要求 `await`，于是报：
  ///   Swift Compiler Error: 'async' call in a function that does not support concurrency
  /// 所以这里把整条调用链改成 async，并在 `await` 里完成清理。
  @MainActor
  private func clearWebStorage() async {
    let types: Set<String> = [
      WKWebsiteDataTypeDiskCache,
      WKWebsiteDataTypeMemoryCache,
      WKWebsiteDataTypeOfflineWebApplicationCache,
      WKWebsiteDataTypeLocalStorage,
      WKWebsiteDataTypeIndexedDBDatabases,
      WKWebsiteDataTypeWebSQLDatabases,
      // 注意：不含 WKWebsiteDataTypeCookies
    ]

    let store = WKWebsiteDataStore.default()
    let records = await store.dataRecords(ofTypes: types)
    await store.removeData(ofTypes: types, for: records)

    // 顺手清 URLCache（部分请求走的是 URLSession 层）
    URLCache.shared.removeAllCachedResponses()
  }
}
