<div align="center">

<img src="assets/ic_launcher.png" width="120" alt="FxWall">

# 复兴表白墙 · FxWall

**www.fxlovewall.me 的配套客户端 —— 三端通用，原生体验**

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows-4A90D9)](#-下载)
[![Release](https://img.shields.io/github/v/release/ClearShadow-09/fxlovewall-app?color=4A90D9&label=release)](https://github.com/ClearShadow-09/fxlovewall-app/releases/latest)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

[下载](#-下载) · [功能](#-功能) · [技术栈](#-技术栈) · [自行构建](#-自行构建) · [常见问题](#-常见问题)

</div>

---

## 这是什么

[www.fxlovewall.me](https://www.fxlovewall.me) 是一个校园表白墙站点。这个项目是配套的
**客户端工具** —— 把网页上的内容用更顺手的方式呈现出来，让你在手机上、电脑上都能方便地用。

用 Flutter 写成，一份代码同时支持 **Android / iOS / Windows**。

它不只是把网页装进壳里 —— 在保留站点全部功能的前提下，重做了界面层：

- 把网页自带的顶栏、搜索框、排序标签收进原生控件
- 卡片、按钮、输入框全部重绘为 Material 3 风格
- 点赞 / 收藏 / 分享 / 评论改成图标 + 数字
- 加入页面过渡、下拉刷新、启动页、新手引导
- 桌面端把底部导航换成可折叠侧边栏

> 客户端只是网页的一个附属工具，不改变站点本身的任何内容与规则。
> 帖子、图片等所有内容的版权归站点及其作者所有。

---

## 📥 下载

前往 **[Releases](https://github.com/ClearShadow-09/fxlovewall-app/releases/latest)** 页面下载。

| 平台 | 文件 | 说明 |
|---|---|---|
| **Android** | `fxlovewall-1.2.5-arm.apk` | 推荐。只含 ARM，体积小（约 19 MB） |
| **Android** | `fxlovewall-1.2.5-universal.apk` | 含 x86_64，模拟器或特殊设备用（约 26 MB） |
| **Windows** | `fxlovewall-1.2.5-windows.zip` | 解压后双击 `fxwall.exe` |
| **iOS** | TestFlight | 见下方说明，链接准备中 |

### 各平台安装说明

<details>
<summary><b>Android</b></summary>

1. 下载 `.apk` 文件
2. 点击安装，系统可能提示「未知来源」—— 在设置里允许即可
3. 从 1.2.0 起支持应用内自动更新：设置 → 检查更新

**最低要求**：Android 7.0（API 24）
</details>

<details>
<summary><b>Windows</b></summary>

1. 下载 `.zip` 并解压到任意目录
2. 双击 `fxwall.exe`

**系统要求**：
- Windows 10 及以上（64 位）
- 需要 **WebView2 运行时**（Windows 11 已预装；Win10 若缺失可从
  [微软官网](https://developer.microsoft.com/microsoft-edge/webview2/) 免费安装）

> 桌面端不支持应用内自动更新 —— 程序无法替换正在运行的自身。
> 检测到新版本时会打开下载页，手动下载覆盖即可。
</details>

<details>
<summary><b>iOS</b></summary>

iOS 端通过 **TestFlight** 分发（苹果的官方测试渠道）。

> 📱 **正在准备中** —— 链接发布后会更新在这里。
>
> 到时候点链接 → 装 TestFlight App → 安装即可。
>
> ⏰ **注意**：TestFlight 的安装有效期是 **90 天**，到期后需要重新安装新版本。
> 我会在到期前更新构建，你只要再点一次链接就行。

</details>

---

## ✨ 功能

### 界面

- **两套主题** —— 「软件主题」重绘网页界面；「网页主题」原样显示站点
- **主题色** —— 8 种配色，全局联动（含网页内的链接、按钮、图标）
- **深浅色** —— 跟随系统 / 固定浅色 / 固定深色
- **字号** —— 四档，原生界面与网页文字同步缩放
- **圆角** —— 五档，默认更方（8px）
- **背景图** —— 从相册选图，可调透明度
- **动画** —— 全部 / 关键 / 无动画三档
- **桌面端侧边栏** —— 可折叠，展开 200px / 收起 64px

### 浏览

- 客户端分页（站点本身没有服务端分页，由客户端切片）
- 下拉刷新，带 1 秒过渡且保留背景图
- 搜索、最新 / 最热门切换、手气不错（随机帖）
- 今日幸运物品（原生直连站点接口）
- 返回键二级退出，避免误触

### 交互

- 点赞 / 收藏 / 分享 / 评论：图标 + 数字，空心 ↔ 实心切换
- 分享调起系统分享面板（桌面端为复制链接）
- 未登录时点需要登录的操作会引导到登录页
- 首次启动有新手引导，可跳过

### 更新

- Android / Windows：查 GitHub Releases，有新版本会提示
- Android 支持应用内下载 + 调系统安装器
- Windows 打开下载页手动更新

---

## 🛠 技术栈

| 用途 | 选型 |
|---|---|
| 框架 | Flutter 3.47（Dart 3.13） |
| WebView | [`zikzak_inappwebview`](https://pub.dev/packages/zikzak_inappwebview) 6.0.2 |
| 设置持久化 | `shared_preferences` |
| 图片选择 | `image_picker` |
| 打开外链 | `url_launcher` |
| CI/CD | GitHub Actions |

### 架构要点

```
lib/
├── main.dart               应用入口、主题装配、启动流程
├── state/
│   └── fx_settings.dart    全部设置项（SharedPreferences）
├── theme/
│   ├── fx_colors.dart      色板与主题色派生
│   ├── fx_theme.dart       Material 3 主题构建
│   └── fx_motion.dart      全局动效参数（时长 / 曲线）
├── web/
│   ├── fx_bridge.dart      JSBridge：CSS/JS 注入 + 事件回传
│   ├── fx_web_assets.dart  注入资源加载
│   └── fx_lucky.dart       今日幸运物品（原生直连）
├── update/
│   └── fx_update.dart      版本检查与下载
└── ui/
    ├── home_shell.dart     主壳（导航 + 网页层 + 原生页）
    ├── splash_page.dart    启动页
    ├── onboarding_page.dart 新手引导
    ├── settings_page.dart  设置页
    └── widgets/            通用组件
```

**网页与原生共用一套配置**：`app/res/raw/` 下的 `theme.css` / `pager.js` /
`layout_fix.js` 是唯一的样式与脚本事实来源，构建时复制进 Flutter 的 `assets/`。
改一次，三个平台同时生效。

---

## 🔨 自行构建

### 环境

```bash
flutter --version   # 需要 3.47 及以上
flutter doctor
```

### Android

```bash
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`。

> 想同时兼容模拟器，加上 `android-x64`：
> `--target-platform android-arm,android-arm64,android-x64`

### Windows

```bash
flutter build windows --release
```

产物在 `build/windows/x64/runner/Release/`，整个目录一起分发。

**前置要求**：Visual Studio 2022 的「使用 C++ 的桌面开发」工作负载。

### iOS

iOS **只能在 macOS 上编译**（苹果的限制）。两种方式：

**本地（有 Mac）**

```bash
flutter build ipa --release
```

**云端（没有 Mac）** —— 用本仓库配好的 GitHub Actions：

1. Fork 本仓库
2. 打开 **Actions** 标签 → **Build iOS (unsigned IPA)** → **Run workflow**
3. 等 5-10 分钟，在 Artifacts 里下载 IPA

工作流文件：`.github/workflows/ios-build.yml`

---

## ❓ 常见问题

<details>
<summary><b>为什么网页内容和站点不完全一样？</b></summary>

「软件主题」会注入一份 CSS 覆盖站点的默认样式。想看到原汁原味的站点，
在 **设置 → 主题 → 网页主题** 切换即可（该模式下零注入）。
</details>

<details>
<summary><b>点击分享没反应？</b></summary>

分享依赖 WebView 的 JSBridge。如果异常，先确认网络正常 ——
分享链接需要从页面读取。Android 上会调起系统分享面板，
Windows 上是复制链接到剪贴板。
</details>

<details>
<summary><b>Windows 上网页白屏？</b></summary>

缺少 WebView2 运行时。到
[微软官网](https://developer.microsoft.com/microsoft-edge/webview2/)
下载安装即可（Windows 11 一般已预装）。
</details>

<details>
<summary><b>Android 安装时提示「应用未安装」？</b></summary>

通常是签名冲突 —— 旧版本是用另一个证书签的。卸载旧版再装即可
（注意卸载会丢失登录状态）。
</details>

<details>
<summary><b>iOS 版在哪下载？</b></summary>

iOS 走 TestFlight 分发，链接准备中。装好后有效期 90 天，
到期前会更新构建，重新点链接安装即可。
</details>

---

## 🤝 贡献

欢迎 Issue 和 PR。

- 报告 Bug 请附上：平台、系统版本、复现步骤、日志
- 提交代码前请跑 `flutter analyze`，保持零警告

---

## 📄 许可

[MIT](LICENSE)

站点及其中所有内容（帖子、图片等）版权归原站点及作者所有，
本项目仅提供客户端实现。

---

<div align="center">

**本项目由 DeepSeek V4.1 Flash 编写**

如果对你有帮助，欢迎点个 ⭐

</div>
