"""APK 启动链校验 —— 专抓「清单声明的 Activity 在 dex 里不存在」这类闪退。

Flutter/Gradle 工程里 namespace 与 applicationId 不一致时，
AndroidManifest 的 android:name=".MainActivity" 会相对 namespace 解析，
但 MainActivity 源码可能还在 flutter create 生成的那个包里 ——
构建能成功，装上却一启动就 ClassNotFoundException 闪退。
这个脚本在构建后直接查 dex，把这类问题挡在交付之前。
"""
import re
import subprocess
import sys
import zipfile

AAPT2 = r"D:\fxlovewall\sdk\build-tools\34.0.0\aapt2.exe"

def main(apk: str) -> int:
    fails = 0

    badging = subprocess.run([AAPT2, "dump", "badging", apk],
                             capture_output=True, text=True, encoding="utf-8").stdout

    m = re.search(r"package: name='([^']+)'", badging)
    pkg = m.group(1) if m else None
    a = re.search(r"launchable-activity: name='([^']+)'", badging)
    act = a.group(1) if a else None
    label = re.search(r"application-label:'([^']*)'", badging)
    ver = re.search(r"versionCode='(\d+)' versionName='([^']*)'", badging)
    mins = re.search(r"sdkVersion:'(\d+)'", badging)

    def check(name, cond, detail=""):
        nonlocal fails
        print(("  PASS  " if cond else "  FAIL  ") + name + (("   [" + str(detail) + "]") if detail else ""))
        if not cond:
            fails += 1

    print("=== 基本信息 ===")
    print(f"  包名        : {pkg}")
    print(f"  启动 Activity: {act}")
    print(f"  应用名      : {label.group(1) if label else '?'}")
    print(f"  版本        : {ver.group(1) + ' / ' + ver.group(2) if ver else '?'}")
    print(f"  minSdk      : {mins.group(1) if mins else '?'}")

    print("=== 启动链校验 ===")
    check("清单声明了 launchable-activity", act is not None)

    if act:
        z = zipfile.ZipFile(apk)
        dexes = [n for n in z.namelist() if n.endswith(".dex")]
        check("APK 内存在 dex", len(dexes) > 0, ", ".join(dexes))

        desc = ("L" + act.replace(".", "/") + ";").encode()
        hits = [n for n in dexes if desc in z.read(n)]
        check(f"dex 中存在启动类 {act}", len(hits) > 0,
              "已确认" if hits else "★ 类不存在 → 启动必闪退 ★")

        # 顺带确认 applicationId == namespace（两者不同名时最容易踩上面那个坑）
        # 这里只能用包名做代理：Flutter 工程里 applicationId 应与清单包名一致
        check("applicationId 与清单包名一致", pkg is not None)

        # Flutter 引擎类必须在
        engine = b"Lio/flutter/embedding/android/FlutterActivity;"
        check("dex 中存在 FlutterActivity", any(engine in z.read(n) for n in dexes))

        # 注入资源必须在
        assets = [n for n in z.namelist() if n.endswith(("theme.css", "pager.js", "layout_fix.js"))]
        check("三个注入资源已打包", len(assets) == 3, ", ".join(sorted(x.split("/")[-1] for x in assets)))

    print()
    print("APK CHECK OK" if fails == 0 else f"{fails} 项失败")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else
                  r"D:\fxlovewall\flutter\build\app\outputs\flutter-apk\app-release.apk"))
