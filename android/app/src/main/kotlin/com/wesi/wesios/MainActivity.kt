package com.wesi.wesios

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Установка скачанного APK.
 *
 * Флаттер-плагином это не решается: начиная с Android 7 передавать `file://`
 * другому приложению запрещено (FileUriExposedException), поэтому путь нужно
 * завернуть в FileProvider, а начиная с Android 8 установку из стороннего
 * источника разрешает не глобальная галочка, а отдельное разрешение
 * REQUEST_INSTALL_PACKAGES у конкретного приложения — его состояние тоже
 * читается только нативно.
 */
class MainActivity : FlutterActivity() {
    private val channel = "wesios/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canRequestInstall())

                    "openInstallPermissionSettings" -> {
                        openInstallPermissionSettings()
                        result.success(null)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "APK path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** До Android 8 разрешение выдавалось глобально — считаем, что можно. */
    private fun canRequestInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun installApk(path: String) {
        val file = File(path)
        // authority обязан совпадать с android:authorities в манифесте.
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            // Без FLAG_GRANT_READ_URI_PERMISSION установщик не сможет прочитать
            // файл: доступ к content://-адресу выдаётся именно этим флагом.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
