# =============================================================================
#  复兴表白墙 Flutter 版 — 构建脚本
#
#  用法:  powershell -ExecutionPolicy Bypass -File build_apk.ps1
#
#  做三件事：
#    1. 把 app\res\raw\ 里那三个注入资源同步到 flutter\assets\
#       —— 保持「全平台单一事实来源」，node 测试测的就是这里打进去的内容
#    2. 生成 android\key.properties，让构建用旧版同一个 debug keystore，
#       这样能直接覆盖升级旧 Kotlin 版（签名不一致会装不上）
#    3. flutter build apk --release
# =============================================================================
param(
    [string]$FlutterRoot = "D:\flutter",
    [switch]$SkipClean
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$ROOT = "D:\fxlovewall"
$APP = "$ROOT\app\res\raw"
$FLU = "$ROOT\flutter"
$SDK = "$ROOT\sdk"
$DIST = "D:\deepseek harness\fxlovewall"

$env:JAVA_HOME = "D:\.minecraft\java\openjdk21"
$env:ANDROID_HOME = $SDK
$env:ANDROID_SDK_ROOT = $SDK
# 优先国内镜像源：pub 包与 Flutter 引擎产物都走 flutter-io.cn，
# 否则 pub.dev / storage.googleapis.com 在部分网络下会很慢。
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PATH = "$FlutterRoot\bin;$env:JAVA_HOME\bin;" + $env:PATH

Write-Host ""
Write-Host "===== 复兴表白墙 Flutter 版 构建 =====" -ForegroundColor Magenta

# ---------------------------------------------------------------- 1. 同步资源
Write-Host "[1/4] 同步注入资源 app\res\raw -> flutter\assets ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "$FLU\assets" | Out-Null
foreach ($f in @("theme.css", "pager.js", "layout_fix.js")) {
    $src = Join-Path $APP $f
    if (-not (Test-Path $src)) { throw "缺少源文件: $src" }
    Copy-Item $src "$FLU\assets\$f" -Force
    $h = (Get-FileHash $src -Algorithm SHA256).Hash.Substring(0, 12)
    Write-Host ("       {0,-16} {1}" -f $f, $h)
}

# 启动页 logo：直接用 Android 的启动图标，保证桌面图标与启动页一致。
# 取 xxxhdpi 那份（192x192，启动页显示 92dp 足够清晰）。
$iconSrc = "$FLU\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc "$FLU\assets\ic_launcher.png" -Force
    $h = (Get-FileHash $iconSrc -Algorithm SHA256).Hash.Substring(0, 12)
    Write-Host ("       {0,-16} {1}" -f "ic_launcher.png", $h)
} else {
    Write-Host "       !! 找不到 ic_launcher.png，启动页会退回占位图标" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 2. 签名配置
Write-Host "[2/4] 生成 android\key.properties ..." -ForegroundColor Cyan
$ks = "$ROOT\debug.keystore"
if (-not (Test-Path $ks)) { throw "缺少 keystore: $ks" }
$kp = @"
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=$($ks -replace '\\','/')
"@
Set-Content -Path "$FLU\android\key.properties" -Value $kp -Encoding ASCII

# ---------------------------------------------------------------- 3. 依赖
Write-Host "[3/4] flutter pub get ..." -ForegroundColor Cyan
Push-Location $FLU
& "$FlutterRoot\bin\flutter.bat" pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "flutter pub get 失败" }

# ---------------------------------------------------------------- 4. 构建
Write-Host "[4/4] flutter build apk --release ..." -ForegroundColor Cyan
if (-not $SkipClean) {
    & "$FlutterRoot\bin\flutter.bat" clean 2>&1 | Out-Null
}
# --target-platform 只打 ARM 两个 ABI（需求 6：体积 52.4MB -> 18.9MB）。
# ⚠️ android/app/build.gradle.kts 里的 splits.abi.include 只作用于**拆分包**，
# 通用包（app-release.apk）必须靠这个开关排除 x86_64 —— 两者缺一不可，
# 否则通用包里仍会塞进一份 x86_64 的 libflutter.so（多 7.5MB）。
& "$FlutterRoot\bin\flutter.bat" build apk --release --target-platform android-arm,android-arm64
$buildExit = $LASTEXITCODE
Pop-Location

if ($buildExit -ne 0) { throw "flutter build 失败" }

$apk = "$FLU\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) { throw "找不到产物: $apk" }

# ---------------------------------------------------------------- 交付
$ver = (Select-String -Path "$FLU\pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches.Groups[1].Value
$verName = $ver.Split('+')[0]
$outDir = Join-Path $DIST "flutter-$verName"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item $apk "$outDir\fxlovewall-$verName.apk" -Force

$size = [math]::Round((Get-Item $apk).Length / 1MB, 2)
Write-Host ""
Write-Host "===== BUILD OK =====" -ForegroundColor Green
Write-Host "  APK      : $apk"
Write-Host "  copied to: $outDir"
Write-Host "  size     : $size MB"
Write-Host "  version  : $ver"
Write-Host ""
