# Правила R8/ProGuard для release-сборки (minifyEnabled true в build.gradle).
# Файл был указан в proguardFiles, но отсутствовал в репозитории.

# Flutter engine и плагины подхватываются рефлексией через GeneratedPluginRegistrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase (в проекте подключены firebase-bom + analytics)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Плагины опираются на аннотации и generic-сигнатуры
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
