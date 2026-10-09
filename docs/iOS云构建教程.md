> 📌 **iOS 云构建教程（零基础版）**
>
> 你的电脑是 Windows，**iOS 应用只能在 macOS 上编译**（苹果的硬性限制）。
> 这份教程用 **GitHub Actions 的免费 macOS 机器**替你编译，产出 IPA 安装包。
> 全程在网页上操作，不需要买 Mac。

---

# 目录

- [第 0 步：理解你要做的事](#第-0-步理解你要做的事)
- [第 1 步：把代码传到 GitHub](#第-1-步把代码传到-github)
- [第 2 步：触发一次构建](#第-2-步触发一次构建)
- [第 3 步：下载 IPA](#第-3-步下载-ipa)
- [第 4 步：装到 iPhone 上](#第-4-步装到-iphone-上)
- [常见问题](#常见问题)
- [附录：关于签名](#附录关于签名)

---

# 第 0 步：理解你要做的事

## 为什么不能在 Windows 上编 iOS

苹果的编译器（Xcode / clang 的 iOS 后端）**只有 macOS 版本**。这不是工具不够好，
是苹果故意的限制 —— 所有 iOS 应用必须经苹果的工具链签名才能装到设备上。

## 云构建怎么绕过去

GitHub 提供免费的 **macOS 虚拟机**（叫 runner）。你把代码传上去，
它在一台真正的 Mac 上跑 `flutter build ipa`，然后把产物给你下载。

| | 本地 Mac | GitHub Actions |
|---|---|---|
| 成本 | 一台 Mac（¥7000+） | **免费**（公开仓库不限量） |
| 速度 | 快 | 每次排队 1-3 分钟 |
| 需要你做什么 | 装 Xcode | 点一下按钮 |

**免费额度**：公开仓库完全免费；私有仓库每月 2000 分钟（macOS 按 10 倍计费，
即 200 分钟）。一次构建约 5-10 分钟。

---

# 第 1 步：把代码传到 GitHub

## 1.1 建仓库

1. 打开 <https://github.com/new>
2. Repository name 填 `fxlovewall-app`
3. 选 **Public**（公开仓库 Actions 免费不限量）
4. **不要**勾 "Add a README file"
5. 点 **Create repository**

## 1.2 拿一个访问令牌

1. 打开 <https://github.com/settings/tokens>
2. **Generate new token** → **Generate new token (classic)**
3. Note 随便填，Expiration 选 90 days 或 No expiration
4. Scopes **只勾 `repo`**
5. 点 Generate，**立刻复制**那串 `ghp_...`
   > 页面关掉就再也看不到了。

## 1.3 推送代码

在 PowerShell 里逐条执行（把 `你的用户名` 换掉）：

```powershell
cd D:\fxlovewall\flutter

# 如果之前没初始化过
git init
git config core.autocrlf false
git remote add origin https://github.com/你的用户名/fxlovewall-app.git

git add .
git commit -m "feat: 1.2.0-beta-debug"
git branch -M main
git push -u origin main
```

第一次推送会问用户名密码：
- Username：你的 GitHub 用户名
- Password：**粘贴那串 `ghp_...`**（不是账号密码）

如果 `git remote add` 报 `origin already exists`：

```powershell
git remote set-url origin https://github.com/你的用户名/fxlovewall-app.git
```

> ⚠️ **推送前确认 `.gitignore` 生效**。执行 `git status` 看列表里有没有
> `android/key.properties`、`*.keystore` —— 签名文件**绝对不能上传**。

---

# 第 2 步：触发一次构建

代码推上去之后，工作流已经躺在 `.github/workflows/ios-build.yml` 里了。

## 2.1 看它有没有自动跑

1. 打开你的仓库页面
2. 点上方的 **Actions** 标签
3. 应该能看到一条叫 **Build iOS (unsigned IPA)** 的记录在跑或已完成

## 2.2 手动触发（推荐第一次用这个）

1. Actions → 左侧点 **Build iOS (unsigned IPA)**
2. 右边点 **Run workflow** 按钮 → 再点绿色的 **Run workflow**
3. 刷新页面，等 3-8 分钟

---

# 第 3 步：下载 IPA

构建完成后：

1. Actions 里点进那次运行
2. 拉到底部 **Artifacts** 区域
3. 点 **fxlovewall-ios-ipa** 下载（一个 zip）
4. 解压得到 `Runner.ipa`

---

# 第 4 步：装到 iPhone 上

## 关键认知：未签名的 IPA 装不上

苹果要求**每个装到设备上的应用都必须签名**。云构建产出的 IPA 是
**未签名**的（因为我们没有你的 Apple 开发者证书），它能编译成功、
能证明代码没问题，但**不能直接双击安装**。

要装到设备上，你有三条路：

### 路线 A：免费个人签名（你有 Mac 时）

用 Xcode 或 AltStore / Sideloadly 这类工具，用你的 Apple ID 免费签名。
**限制**：证书 7 天过期，需要每 7 天重签一次；最多 3 个应用。

### 路线 B：付费开发者账号 → TestFlight（推荐）

这是唯一能让**别人也装得上**的路线。完整操作见
[TestFlight发布教程.md](TestFlight发布教程.md)。

要点：
- 需要 Apple 开发者账号（/年）
- 用 TestFlight 分发，用户点链接装 TestFlight App 即可安装
- **构建有效期 90 天**，到期前要上传新构建

### 路线 C：只验证代码（不需要设备）

如果你只想确认「代码能编译、能打包」，那第 3 步拿到 IPA 就够了。
这也正是本次的目标。

---

# 常见问题

## Q：Actions 页面什么都没有

推送后需要几秒到几十秒才出现。刷新页面。
如果一直没有，检查 `.github/workflows/ios-build.yml` 是否真的推上去了：

```powershell
git ls-files .github/
```

## Q：构建失败，报 `No profiles for 'com.example.fxwall' were found`

说明工作流在尝试签名。本项目的默认配置走 **`--no-codesign`**（不签名），
如果看到这个报错，检查工作流里那行：

```yaml
flutter build ios --release --no-codesign
```

## Q：构建失败，报 `CocoaPods not installed`

工作流里已经装了 CocoaPods。如果还是报，可能是 `ios/Podfile` 缺失 ——
首次构建时 `flutter build` 会自动生成它。确认仓库里有 `ios/` 目录。

## Q：想改 bundle identifier（应用的唯一标识）

编辑 `ios/Runner.xcodeproj/project.pbxproj`，把
`PRODUCT_BUNDLE_IDENTIFIER` 的值改掉。或者在 Xcode 里改（但你没有 Mac）。
用文本编辑器搜索替换即可，通常有 3 处。

## Q：能同时构建 Android 吗

可以。在同一份工作流里加一个 `android` job，用 `ubuntu-latest` runner。

---

# 附录：关于签名

如果你以后拿到了付费开发者账号，把下面这些加到仓库的
**Settings → Secrets and variables → Actions**：

| Secret 名 | 内容 |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `.p12` 证书的 base64 |
| `P12_PASSWORD` | .p12 的密码 |
| `BUILD_PROVISION_PROFILE_BASE64` | 描述文件的 base64 |
| `KEYCHAIN_PASSWORD` | 随便设一个临时密码 |

然后把工作流里的 `--no-codesign` 换成正式签名步骤。
GitHub 官方有完整的示例：<https://docs.github.com/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development>

> 生成 base64（PowerShell）：
> ```powershell
> [Convert]::ToBase64String([IO.File]::ReadAllBytes("证书.p12")) | Set-Clipboard
> ```

---

# 这个项目里 iOS 相关的改动

给想了解细节的人：

- `ios/` —— `flutter create --platforms=ios` 生成的标准 Xcode 工程
- `ios/Runner/Info.plist` —— 应用名改成「复兴表白墙」；补了相册/相机权限说明
  （iOS 上不声明会**直接闪退**）；声明了 `LSApplicationQueriesSchemes`
  供 url_launcher 使用
- `ios/Runner/AppDelegate.swift` —— 实现了和 Android 同名的方法通道
  `com.fxlovewall.app/device`，提供 `appVersion` / `share` / `cacheSize` /
  `clearWebStorage`。**Dart 侧不用为 iOS 写第二套代码**
- 未实现 `installApk` 等 —— iOS 不允许应用自安装，更新只能走 App Store。

## 插件在 iOS 上的限制

`zikzak_inappwebview` 在 iOS 上是完整实现（用 WKWebView），
所以 WebView 的核心功能（主题注入、JSBridge、分享拦截）都能用。

但 iOS 的 WKWebView **不支持** Android 那套 `shouldOverrideUrlLoading`，
行为上会有细微差别（比如外链拦截的时机）。这部分需要真机验证。
