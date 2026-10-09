## 复兴表白墙 客户端 1.2.5-release

网页 `www.fxlovewall.me` 的配套客户端工具，把表白墙装进手机和电脑里。

---

### 下载

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Android（推荐） | `fxlovewall-1.2.5-arm.apk` | 18.9 MB，绝大多数手机选这个 |
| Android（通用） | `fxlovewall-1.2.5-universal.apk` | 26.5 MB，含 x86_64，模拟器 / 老旧设备用 |
| Windows | `fxlovewall-1.2.5-windows.zip` | 解压后双击 `fxwall.exe`，需要 WebView2 运行时 |
| iOS | 暂无附件 | 通过 TestFlight 分发，链接准备中 |

---

### 本版更新

**新增**

- **iOS 端完整支持**：底部导航栏、摇一摇抽签、相册选图上传、系统分享面板，与 Android 端功能对齐。
- **应用内更新检查**：
  - Android — 检测到新版本可下载 APK，走系统安装器直接升级。
  - Windows — 检测到新版本会提示并打开下载页（Windows 上运行中的 exe 无法自我覆盖，因此不做静默替换）。
  - iOS — 提示新版本，跳转 TestFlight 或 App Store。
- **侧边栏布局**：Windows 上使用可折叠侧栏，充分利用宽屏；Android / iOS 保持底部导航。

**修复**

- 修复分享功能在 Windows 和 iOS 上静默失效的问题 —— 根因是 WebView 桥接对象名在不同平台不一致（Windows 为 `window.zikzak_inappwebview`，Android / iOS 为 `window.flutter_inappwebview`），现在按平台依次回退探测。
- 修复 Windows 剪贴板中文乱码（改用 PowerShell `-EncodedCommand` 传递 GBK 十六进制字节）。
- 修复卡片背景色偏紫 —— 原先误用了 Material 3 基线紫灰配色，现统一由 `--fx-primary-rgb` 推导。
- 修复 Windows 字体渲染粗糙 —— 改为按平台选择字体族并补充中文回退链（微软雅黑 → 等线 → 苹方 → 思源黑体）。
- 修复 Windows 端网页事件不触发导致注入失效 —— 该平台 `onLoadStart` / `onLoadStop` 不触发，改用轮询 `document.readyState` 与 `location.pathname`。

**其他**

- 目标 SDK 升级至 36，`minSdk` 保持 24（Android 7.0+）。

---

### 校验

构建产物签名证书 SHA-256 指纹：

```
93093773964c5551d38e31e7905ec4cd387ccc910119e0a8620b02c2283478c1
```

Android 安装时若提示「未知来源」，在系统设置中允许对应浏览器 / 文件管理器安装应用即可。

---

### 说明

本软件是 `www.fxlovewall.me` 的配套客户端，内容与数据均来自该站点。使用中如遇问题，可在本仓库提交 Issue。

本项目由 **DeepSeek V4.1 Flash** 编写，以 MIT 协议开源。
