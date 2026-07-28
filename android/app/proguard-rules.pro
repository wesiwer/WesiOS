# Правила R8 для release-сборки (minifyEnabled true в build.gradle).
# Файл указан в proguardFiles, но отсутствовал в репозитории.
#
# Держим его МИНИМАЛЬНЫМ: Flutter Gradle plugin сам подкладывает keep-правила
# для движка и плагинов. Широкие `-keep class io.flutter.**` только вредят —
# они удерживают io.flutter.app.FlutterPlayStoreSplitApplication, который
# ссылается на Play Core, а Play Core в зависимостях нет, и R8 падает с
# «Missing classes detected».

# Play Core не подключён (deferred components не используются).
-dontwarn com.google.android.play.core.**
