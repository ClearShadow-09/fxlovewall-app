# Flutter 官方推荐的 keep 规则。
#
# 目前 build.gradle.kts 里已经把 release 的压缩关掉了（isMinifyEnabled = false），
# 这份规则是给以后想开 R8 时兜底的 —— 一旦缺少它，AGP 9 的默认 R8 会把
# io.flutter.embedding.android.FlutterActivity 这类类重命名，
# 而 Flutter 引擎里有按类名/枚举名反射的地方，会直接崩。

-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 启动 Activity 由清单按名字加载，必须保留
-keep class com.fxlovewall.app.MainActivity { *; }

# 插件里被清单引用的组件
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }

# Flutter 的枚举常量名会被按字符串查找
-keepclassmembers enum io.flutter.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
