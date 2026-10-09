# 复兴表白墙 — 发布与自动更新配置教程（零基础版）

这份文档带你从零完成三件事：

1. 在 GitHub 建一个公开仓库 `fxlovewall-app`
2. 把代码推上去
3. 发布一个 Release，让 App 能检测到新版本并自动下载

全程大约 15 分钟。**不需要**懂 git 命令，我会给你现成的命令，复制粘贴即可。

---

## 目录

- [第 0 步：注册 GitHub 账号](#第-0-步注册-github-账号)
- [第 1 步：建仓库](#第-1-步建仓库)
- [第 2 步：创建访问令牌（PAT）](#第-2-步创建访问令牌pat)
- [第 3 步：把令牌和用户名填进代码](#第-3-步把令牌和用户名填进代码)
- [第 4 步：推送代码](#第-4-步推送代码)
- [第 5 步：发布 Release](#第-5-步发布-release)
- [第 6 步：验证自动更新](#第-6-步验证自动更新)
- [以后每次发新版怎么做](#以后每次发新版怎么做)
- [常见问题](#常见问题)

---

## 第 0 步：注册 GitHub 账号

如果你已经有账号，跳到第 1 步。

1. 打开 <https://github.com/signup>
2. 填邮箱 → 设密码 → 取用户名（**记住这个用户名，第 3 步要用**）
3. 去邮箱点验证链接

---

## 第 1 步：建仓库

1. 登录后，点右上角 **`+`** → **New repository**
2. 按下表填写：

   | 字段 | 填什么 |
   |---|---|
   | Repository name | `fxlovewall-app` |
   | Description | 随便，可留空 |
   | Public / Private | **选 Public（公开）** |
   | Add a README file | **勾上** |
   | .gitignore | None |
   | License | 可不选 |

3. 点绿色按钮 **Create repository**

> ⚠️ **为什么必须选 Public？**
> 私有仓库的 Release 下载需要带令牌才能访问。如果填私有，App 里就得内置你的令牌，
> 一旦有人反编译 APK 就能拿到它，进而读写你所有仓库。公开仓库没有这个问题，
> 而且这个项目本来也没什么需要保密的东西。

---

## 第 2 步：创建访问令牌（PAT）

这一步生成一串类似 `ghp_xxxxxxxx` 的密码，用来让 `git` 有权限推代码到你的仓库。

1. 打开 <https://github.com/settings/tokens>
2. 点 **Generate new token** → 选 **Generate new token (classic)**
   > 不要选 "Fine-grained token"，那个配置项更多，经典版够用且更简单。
3. 填写：
   - **Note**：随便写，例如 `fxlovewall-push`
   - **Expiration**：选 `90 days` 或 `No expiration`（不过期省事，但安全性略低）
   - **Select scopes**：**只勾 `repo`** 这一个就够了
     （`repo` 会连带勾选它下面的子项，这是正常的）
4. 拉到底，点 **Generate token**
5. **立刻复制那串 `ghp_...`**
   > ⚠️ 这个页面关掉之后就再也看不到它了，只能重新生成。先粘贴到记事本里。

---

## 第 3 步：把令牌和用户名填进代码

### 3.1 填用户名（App 靠它找你的仓库）

打开文件 `D:\fxlovewall\flutter\lib\update\fx_update.dart`，找到这一行：

```dart
static const String repoOwner = ''; // 例如 'yourname'
```

把 `yourname` 换成你第 0 步注册的用户名，例如：

```dart
static const String repoOwner = 'zhangsan';
```

> 💡 这里**不要**填令牌。令牌只给 git 用，绝不能写进 App 代码 ——
> 那等于把它公开发布出去。

### 3.2 让 git 记住令牌（避免每次输密码）

在 PowerShell 里执行（把两处 `你的用户名` 和 `你的令牌` 换掉）：

```powershell
git config --global credential.helper store
```

然后第一次推送时会问用户名和密码：
- Username：填你的 GitHub 用户名
- Password：**粘贴那串 `ghp_...`**（不是账号密码！）

输一次之后就会记住。

---

## 第 4 步：推送代码

在 PowerShell 里逐条执行（**逐条**，别一次全贴，方便看报错）：

```powershell
cd D:\fxlovewall\flutter

# 初始化仓库（如果之前没做过）
git init

# 关掉 Windows 换行符自动转换（否则每次都会显示文件被改过）
git config core.autocrlf false

# 关联到你的远程仓库：把 你的用户名 换掉
git remote add origin https://github.com/你的用户名/fxlovewall-app.git

# 把文件加入暂存区
git add .

# 提交
git commit -m "feat: 1.2.0-beta-debug"

# 重命名分支为 main（GitHub 的默认分支名）
git branch -M main

# 推送
git push -u origin main
```

如果 `git remote add` 报错说 `origin already exists`，改成：

```powershell
git remote set-url origin https://github.com/你的用户名/fxlovewall-app.git
```

推送成功后，刷新 GitHub 仓库页面，应该能看到你的代码。

> ⚠️ **推送前确认 `.gitignore` 生效**
> 这个项目的 `.gitignore` 应当排除 `build/`、`android/key.properties`、
> `*.keystore`。**签名文件绝对不能上传** —— 别人拿到它就能伪造你的 App 更新。
> 推送前执行 `git status` 检查一下列表里有没有这些文件。

---

## 第 5 步：发布 Release

App 的更新检查读的是 **latest release**（最新正式发布），不是代码提交。

1. 打开你的仓库页面
2. 右侧找到 **Releases** → 点 **Create a new release**
   （或直接访问 `https://github.com/你的用户名/fxlovewall-app/releases/new`）
3. 填写：

   | 字段 | 填什么 | 说明 |
   |---|---|---|
   | Choose a tag | 输入 `v1.2.0-beta-debug` 然后点 **Create new tag** | **版本号必须和 App 里的对得上** |
   | Release title | `1.2.0-beta-debug` | |
   | Describe this release | 更新说明，会显示在 App 的更新弹层里 | 支持 Markdown |

4. **上传 APK**：把 `app-release.apk` 拖到 "Attach binaries" 区域
   > 建议改名为 `fxlovewall-1.2.0-beta-debug.apk` 再上传，方便用户辨认。
   > App 会自动找附件里**第一个 `.apk` 结尾**的文件。

5. 点 **Publish release**

### 版本号规则（很重要）

App 比较版本时**只看数字部分**，忽略 `-beta`/`-debug` 这类后缀：

| Release tag | App 里的 versionName | 结果 |
|---|---|---|
| `v1.2.1` | `1.2.0-beta-debug` | ✅ 提示更新 |
| `v1.2.0-beta-debug` | `1.2.0-beta-debug` | ⬜ 已是最新 |
| `v1.1.9` | `1.2.0-beta-debug` | ⬜ 不提示（旧版本） |

这样设计的原因：后缀表达的是「构建渠道」，不是新旧顺序。
拿 `beta` 去比大小会得出反直觉的结果。

---

## 第 6 步：验证自动更新

1. 在手机上装一个**低版本**的 APK（比如 1.1.1）
2. 打开 App，等 3 秒 —— 会静默检查一次
3. 如果有新版，会弹出更新对话框，显示更新说明和「下载更新」按钮
4. 点「下载更新」→ 进度条走完 → 点「安装」
5. 首次安装会提示 **「禁止安装未知应用」**，点提示里的**「去设置」**，
   允许本应用安装，然后回来再点一次「安装」

也可以手动检查：**设置 → 其他 → 检查更新**。

---

## 以后每次发新版怎么做

假设要发 `1.2.1`：

1. **改版本号**：编辑 `D:\fxlovewall\flutter\pubspec.yaml`

   ```yaml
   version: 1.2.1+10201
   ```
   > `+` 后面的数字是 versionCode，**必须比上一版大**，否则系统不允许覆盖安装。
   > 规则：`major*10000 + minor*100 + patch`。

2. **构建**：

   ```powershell
   cd D:\fxlovewall\flutter
   powershell -ExecutionPolicy Bypass -File build_apk.ps1
   ```

3. **推送代码**：

   ```powershell
   git add .
   git commit -m "release: 1.2.1"
   git push
   ```

4. **发 Release**：重复[第 5 步](#第-5-步发布-release)，
   tag 填 `v1.2.1`，上传新的 APK

5. 老用户打开 App 就会收到更新提示

---

## 常见问题

### Q：App 里点「检查更新」提示「更新检查尚未配置」

`fx_update.dart` 里的 `repoOwner` 还是空的。回去做[第 3.1 步](#31-填用户名app-靠它找你的仓库)。

### Q：提示「检查更新失败：GitHub 返回 403」

GitHub 对未登录的 API 请求限流（每小时 60 次）。等一小时就好，或者给请求加令牌
（但公开仓库不建议在 App 里放令牌）。

### Q：提示「检查更新失败：GitHub 返回 404」

两种可能：
- 仓库名或用户名填错了
- **还没发布过 Release**（只有代码提交不算）

### Q：`git push` 报 `Authentication failed`

- 确认密码处填的是 **PAT（`ghp_...`）**，不是 GitHub 账号密码
- 确认 PAT 勾了 `repo` 权限
- 确认 PAT 没过期

### Q：`git push` 报 `rejected - non-fast-forward`

远程有本地没有的提交（比如你在网页上编辑过 README）。先拉下来：

```powershell
git pull --rebase origin main
git push
```

### Q：怎么撤销上一次提交？

```powershell
# 撤销提交但保留文件改动
git reset --soft HEAD~1
```

### Q：不小心把 key.properties 推上去了怎么办？

**立刻换签名密钥**，并把这个文件从历史里彻底删除。已经泄露的密钥即使删掉文件，
历史记录里仍然能翻出来。这个项目的 `key.properties` 和 `*.keystore` 必须
始终留在 `.gitignore` 里。

### Q：想用命令行直接发布 Release（不用网页）

需要装 GitHub CLI（`gh`）：

```powershell
gh auth login
gh release create v1.2.1 `
  "D:\fxlovewall\flutter\build\app\outputs\flutter-apk\app-release.apk" `
  --title "1.2.1" `
  --notes "更新说明写这里"
```

---

## 附：这个方案的技术细节

给想了解实现的人：

- **检查更新**：`GET https://api.github.com/repos/{owner}/{repo}/releases/latest`
  公开仓库无需认证。解析 `tag_name`（版本号）和 `assets[]`（找第一个 `.apk`）。
- **版本比较**：`FxVersion.parse` 用正则抽开头的 `数字.数字.数字`，逐段比较，
  缺失段按 0 处理。后缀不参与比较。
- **下载**：`dart:io` 的 `HttpClient`，按 `contentLength` 算进度，
  每 256KB 回调一次（避免频繁 setState 拖垮 UI）。落在
  `cacheDir/fxupdate/`，下载前清掉上一次的残留。
- **安装**：必须走 `FileProvider`（Android 7.0 起不允许 `file://` 跨进程传文件）。
  authority 是 `${applicationId}.fileprovider`，暴露的路径在
  `res/xml/fx_file_paths.xml` 里限定为 `cacheDir/fxupdate/` ——
  刻意**不**暴露整个缓存目录，否则 WebView 缓存也会变成可被外部读取的 URI。
- **权限**：`REQUEST_INSTALL_PACKAGES`（清单里已声明）。Android 8.0+ 还需要
  用户在系统设置里手动允许，App 无法绕过，只能引导。
