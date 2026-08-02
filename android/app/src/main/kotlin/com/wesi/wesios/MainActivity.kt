package com.wesi.wesios

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Нативные мосты:
 *  - wesios/updater — установка скачанного APK
 *  - wesios/icon    — переключение activity-alias'ов (тёмная / светлая иконка)
 *
 * Смена иконки откладывается до onPause: на многих лаунчерах
 * disable активного alias'а во время работы приложения выкидывает
 * процесс на рабочий стол даже при DONT_KILL_APP. Когда activity
 * уходит в фон — смена безопасна и происходит «на фоне».
 */
class MainActivity : FlutterFragmentActivity() {
    private val updaterChannel = "wesios/updater"
    private val iconChannel = "wesios/icon"

    /** Pending light/dark icon; applied in onPause. */
    private var pendingLightIcon: Boolean? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val variant = call.argument<String>("variant") ?: "dark"
                        // Не применяем сразу — откладываем до ухода в фон.
                        pendingLightIcon = (variant == "light")
                        result.success(true)
                    }
                    "isSupported" -> result.success(true)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        super.onPause()
        pendingLightIcon?.let { light ->
            try {
                setLauncherIcon(light)
            } catch (_: Exception) {
                // ignore — лаунчер может быть недоступен
            }
            pendingLightIcon = null
        }
    }

    /**
     * Переключает activity-alias'ы IconDark / IconLight.
     * На части лаунчеров иконка обновляется не мгновенно — это ограничение ОС.
     */
    private fun setLauncherIcon(light: Boolean) {
        val pm = packageManager
        val dark = ComponentName(this, "com.wesi.wesios.IconDark")
        val lightComp = ComponentName(this, "com.wesi.wesios.IconLight")

        val enable = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val disable = PackageManager.COMPONENT_ENABLED_STATE_DISABLED

        // DONT_KILL_APP — не убивать процесс при смене компонента.
        pm.setComponentEnabledSetting(
            dark,
            if (light) disable else enable,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            lightComp,
            if (light) enable else disable,
            PackageManager.DONT_KILL_APP,
        )
    }

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
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
