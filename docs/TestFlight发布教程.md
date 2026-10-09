> 📌 **TestFlight 发布教程（维护者自用）**
>
> TestFlight 是苹果官方的测试分发平台：你把包传上去，邀请测试员（最多 10000 人），
> 他们用手机装 TestFlight App 就能安装你的应用，**不再受 7 天签名限制**。
>
> 需要 **Apple 开发者账号（$99/年）**。下面的每一步都写清楚了。
>
> ---
>
> **这份文档是维护者的操作手册，不是给用户看的。**
> 用户只需要拿到 TestFlight 链接 → 点开 → 安装。
>
> ⏰ **重要提醒**：TestFlight 构建有效期 **90 天**。
> 到期前必须上传新构建，否则测试员的版本会失效。
> 建议在本日历上设个 80 天的提醒。

---

# 目录

- [第 0 步：你需要准备什么](#第-0-步你需要准备什么)
- [第 1 步：注册开发者账号](#第-1-步注册开发者账号)
- [第 2 步：创建 App ID](#第-2-步创建-app-id)
- [第 3 步：生成证书和描述文件](#第-3-步生成证书和描述文件)
- [第 4 步：把证书传给 GitHub Actions](#第-4-步把证书传给-github-actions)
- [第 5 步：构建并上传](#第-5-步构建并上传)
- [第 6 步：在 App Store Connect 里发布测试](#第-6-步在-app-store-connect-里发布测试)
- [常见问题](#常见问题)

---

# 第 0 步：你需要准备什么

| 需要 | 说明 |
|---|---|
| Apple 开发者账号 | $99/年，个人或公司都可以 |
| 一台电脑 | Windows 就行 —— 证书可以在浏览器里生成 |
| 一个 iPhone | 用来收测试邀请、装 TestFlight |

**不需要 Mac。** 这是整个流程的关键：证书配置和上传都在网页 + CI 上完成。

---

# 第 1 步：注册开发者账号

1. 打开 <https://developer.apple.com/programs/enroll/>
2. 用你的 Apple ID 登录（没有就注册一个）
3. 选择 **Individual**（个人）或 **Organization**（公司）
   - 个人：审核快，1-2 天
   - 公司：需要 D-U-N-S 编号，审核慢一些
4. 付 $99，等苹果审核通过（个人一般 24-48 小时）

审核通过后你会收到邮件，并能访问 <https://developer.apple.com/account>。

---

# 第 2 步：创建 App ID

App ID 是应用的唯一标识，格式类似 `com.yourname.fxwall`。

1. 打开 <https://developer.apple.com/account/resources/identifiers/list>
2. 点右上角 **+**（加号）
3. 选 **App IDs** → **App** → 继续
4. 填写：
   - **Description**：`复兴表白墙`
   - **Bundle ID**：选 **Explicit**，填 `com.clearShadow09.fxwall`
     > ⚠️ 这个值必须和项目里的一致。本项目的默认值是
     > `com.example.fxwall`，你需要改（见下方第 3.4 步），
     > 或者在这里填成 `com.example.fxwall`。
5. **Capabilities** 保持默认即可
6. 点 **Continue** → **Register**

---

# 第 3 步：生成证书和描述文件

这一步在浏览器里完成，不需要 Mac。

## 3.1 生成证书签名请求（CSR）

**在 Windows 上也能做**，用 OpenSSL（Git for Windows 自带）：

```powershell
# 在任意目录执行
openssl req -new -newkey rsa:2048 -nodes `
  -keyout ios_key.pem `
  -out ios_csr.certSigningRequest `
  -subj "/emailAddress=你的邮箱@example.com/CN=你的名字/C=CN"
```

会生成两个文件：
- `ios_key.pem` —— **私钥，务必保管好**
- `ios_csr.certSigningRequest` —— 待会要上传给苹果

> 没有 OpenSSL？装一下 [Git for Windows](https://git-scm.com/download/win)，
> 然后在 Git Bash 里执行同样的命令。

## 3.2 申请发布证书

1. 打开 <https://developer.apple.com/account/resources/certificates/list>
2. 点 **+**
3. 选 **Apple Distribution**（用于 App Store / TestFlight 分发）
   > 注意不要选 "iOS Development" —— 那个只能本地调试用
4. 上传刚才生成的 `ios_csr.certSigningRequest`
5. 下载得到 `distribution.cer`

## 3.3 转成 .p12 格式

`.cer` 不能直接用，要转成 `.p12`（带私钥）：

```powershell
# 把 .cer 转成 PEM
openssl x509 -inform DER -in distribution.cer -out distribution.pem

# 打包成 .p12（会提示你设一个密码，记住它）
openssl pkcs12 -export `
  -inkey ios_key.pem `
  -in distribution.pem `
  -out distribution.p12 `
  -name "FxWall Distribution"
```

> 密码后面要填到 GitHub Secret 里，**记住它**。

## 3.4 修改项目的 Bundle ID

编辑 `ios/Runner.xcodeproj/project.pbxproj`，搜索 `PRODUCT_BUNDLE_IDENTIFIER`，
把 `com.example.fxwall` 改成你在第 2 步创建的 App ID（例如
`com.clearShadow09.fxwall`）。通常有 3 处，全部改掉。

```powershell
cd D:\fxlovewall\flutter
(Get-Content ios\Runner.xcodeproj\project.pbxproj -Raw) `
  -replace 'com\.example\.fxwall', 'com.clearShadow09.fxwall' |
  Set-Content ios\Runner.xcodeproj\project.pbxproj -NoNewline -Encoding UTF8
```

> ⚠️ 结尾必须加 `-Encoding UTF8`。不加会按系统 GBK 写入，
> 把中文注释写坏（这个坑踩过）。

## 3.5 创建描述文件（Provisioning Profile）

1. 打开 <https://developer.apple.com/account/resources/profiles/list>
2. 点 **+**
3. 选 **App Store**（分发用）
4. 选择第 2 步创建的 App ID
5. 选择第 3.2 步创建的证书
6. 填 Profile Name，比如 `FxWall AppStore`
7. 下载得到 `FxWall_AppStore.mobileprovision`

---

# 第 4 步：把证书传给 GitHub Actions

## 4.1 把文件转成 base64

在 PowerShell 里执行：

```powershell
# 证书
[Convert]::ToBase64String([IO.File]::ReadAllBytes("distribution.p12")) |
  Set-Clipboard
# 剪贴板里就是 base64，粘贴到记事本暂存

# 描述文件
[Convert]::ToBase64String([IO.File]::ReadAllBytes("FxWall_AppStore.mobileprovision")) |
  Set-Clipboard
```

## 4.2 添加 Secrets

1. 打开你的仓库 → **Settings** → 左侧 **Secrets and variables** → **Actions**
2. 点 **New repository secret**，逐个添加：

| Name | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | `distribution.p12` 的 base64 |
| `P12_PASSWORD` | 第 3.3 步设的密码 |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `KEYCHAIN_PASSWORD` | 随便设一个临时密码（如 `temp123`） |
| `APPLE_TEAM_ID` | 你的 Team ID（见下） |
| `APP_STORE_CONNECT_API_KEY_ID` | 见 4.3 |
| `APP_STORE_CONNECT_ISSUER_ID` | 见 4.3 |
| `APP_STORE_CONNECT_API_KEY_BASE64` | 见 4.3 |

**Team ID 在哪**：<https://developer.apple.com/account> 右上角，
或者 Membership 页面，是一个 10 位字符串（如 `A1B2C3D4E5`）。

## 4.3 创建 App Store Connect API Key（用于自动上传）

这一步让 CI 能自动把 IPA 传到 App Store Connect。

1. 打开 <https://appstoreconnect.apple.com/access/api>
   > 如果看不到这个页面，说明你的账号还没被授予 Admin 角色
2. 点 **+** 生成一个 Key
3. Name 填 `GitHub Actions`，Access 选 **App Manager**
4. 点 **Generate**
5. **立刻下载** `.p8` 文件（只能下载一次！）
6. 记下页面上的 **Key ID** 和 **Issuer ID**

然后：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8")) |
  Set-Clipboard
```

粘到 `APP_STORE_CONNECT_API_KEY_BASE64`。

---

# 第 5 步：构建并上传

如果 Secrets 都配好了，工作流会自动切换到**签名构建 + 上传**模式。

1. 打开仓库的 **Actions** 标签
2. 选 **Build iOS (signed IPA + TestFlight)**
3. 点 **Run workflow**
4. 等 10-15 分钟

构建完成后，IPA 会自动上传到 App Store Connect。
你也可以在 Artifacts 里下载签好名的 IPA。

---

# 第 6 步：在 App Store Connect 里发布测试

## 6.1 创建应用记录

1. 打开 <https://appstoreconnect.apple.com/apps>
2. 点 **+** → **New App**
3. 填写：
   - **Platform**：iOS
   - **Name**：复兴表白墙
   - **Primary Language**：Chinese (Simplified)
   - **Bundle ID**：选你在第 2 步创建的那个
   - **SKU**：随便填个唯一字符串，如 `fxwall001`
4. 点 **Create**

## 6.2 等待构建处理

上传后需要等苹果处理（一般 10-30 分钟）。在 App Store Connect 的
**TestFlight** 标签下能看到构建版本，状态从 "Processing" 变成 "Ready to Submit"。

## 6.3 添加测试信息

**TestFlight → 测试信息**：
- **Beta App Description**：写一句介绍
- **Feedback Email**：你的邮箱
- **What to Test**：告诉测试员重点测什么

> ⚠️ 首次提交会要求填 **Export Compliance**（出口合规）。
> 一般选「不使用加密」或「仅使用标准加密（HTTPS）」即可。

## 6.4 邀请测试员

**内部测试**（最多 100 人，无需审核）：
1. **TestFlight → 内部测试** → 点 **+**
2. 添加测试员的 Apple ID（他们必须在你的 App Store Connect 团队里）

**外部测试**（最多 10000 人，首次需苹果审核 1-2 天）：
1. **TestFlight → 外部测试** → 创建测试组
2. 添加测试员邮箱，或生成**公开链接**
3. 点 **Submit for Review**

## 6.5 测试员怎么装

1. 收到邮件邀请，或点公开链接
2. 在 iPhone 上装 **TestFlight** App（App Store 免费下载）
3. 在 TestFlight 里接受邀请 → 点安装

**装好后有效期 90 天**，到期前你上传新版本就能续。

---

# 常见问题

## Q：必须要付费账号吗？

是的。TestFlight 只对开发者账号开放。免费 Apple ID 只能用
AltStore / Sideloadly 自签，证书 7 天过期。

## Q：没有 Mac 真的可以吗？

可以。这份教程全程在 Windows + 浏览器 + GitHub Actions 上完成。
证书生成用 OpenSSL（Git 自带），上传由 CI 的 `xcrun altool` 完成。

## Q：`openssl` 命令找不到

装 [Git for Windows](https://git-scm.com/download/win) 后用 Git Bash，
或者用 WSL。Windows 10+ 也自带 `openssl`（在某些版本里需要手动启用）。

## Q：构建失败，报 "No signing certificate"

检查：
1. `BUILD_CERTIFICATE_BASE64` 是不是完整的 base64（不能有换行）
2. `P12_PASSWORD` 对不对
3. 证书类型是不是 **Apple Distribution**（不是 Development）

## Q：构建失败，报 "Provisioning profile doesn't match"

描述文件里的 Bundle ID 必须和第 3.4 步改的一致。
回 App Store Connect 检查 App ID，重新生成描述文件。

## Q：上传成功但 TestFlight 里看不到

苹果需要处理 10-30 分钟。如果超过 1 小时还没出现，
去 **App Store Connect → 我的 App → 活动** 看有没有报错。

## Q：应用名显示成英文 "fxwall"

`ios/Runner/Info.plist` 里的 `CFBundleDisplayName` 控制显示名。
本项目已设为「复兴表白墙」，如果你 Fork 后没同步这份改动，
自己改一下即可。

## Q：想同时测 Android 的 TestFlight 等价物

Google Play 内部测试轨道。或者直接用本项目的 APK 内测。

---

# 参考

- [苹果官方：上传构建版本](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [GitHub 官方：在 macOS runner 上安装 Apple 证书](https://docs.github.com/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development)
- [TestFlight 使用指南](https://developer.apple.com/testflight/)
