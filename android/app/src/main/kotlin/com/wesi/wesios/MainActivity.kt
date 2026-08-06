package com.wesi.wesios

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
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
 *  - wesios/haptics — точный тактильный отклик (см. ниже)
 *
 * Смена иконки откладывается до onPause: на многих лаунчерах
 * disable активного alias'а во время работы приложения выкидывает
 * процесс на рабочий стол даже при DONT_KILL_APP. Когда activity
 * уходит в фон — смена безопасна и происходит «на фоне».
 */
class MainActivity : FlutterFragmentActivity() {
    private val updaterChannel = "wesios/updater"
    private val iconChannel = "wesios/icon"
    private val hapticsChannel = "wesios/haptics"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hapticsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> result.success(hapticCapabilities())
                    "play" -> result.success(
                        playHaptic(call.argument<String>("effect") ?: "tap")
                    )
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

    // ─────────────────────────────────────────────────────── тактильный отклик
    //
    // Штатный HapticFeedback во Flutter — это четыре константы из
    // HapticFeedbackConstants: VIRTUAL_KEY, KEYBOARD_TAP, CONTEXT_CLICK,
    // CLOCK_TICK. Ни силы, ни длительности, ни возможности составить из них
    // рисунок. Отсюда и ощущение «дешёвого зуда» там, где на iPhone короткий
    // отчётливый щелчок: там UIImpactFeedbackGenerator с интенсивностью.
    //
    // С Android 12 есть прямой аналог — VibrationEffect.Composition:
    // примитивы (щелчок, тик, быстрый подъём) с интенсивностью 0…1 и
    // задержками между ними. Это и даёт «айфоновский» отклик на телефонах с
    // линейным актуатором.
    //
    // Три ступени, сверху вниз:
    //   1) композиция примитивов          — Android 12+ и мотор её умеет;
    //   2) заготовленные эффекты          — Android 10+, подобраны вендором;
    //   3) null                           — пусть Flutter отдаёт своё.

    private val vibrator: Vibrator?
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    /**
     * Выключил ли человек тактильный отклик в настройках системы.
     *
     * Проверяем сами: прямой вызов вибратора, в отличие от
     * performHapticFeedback, системную настройку не спрашивает. Жужжать
     * вопреки явному «не надо» — худший вид самодеятельности.
     */
    private fun systemHapticsEnabled(): Boolean = try {
        Settings.System.getInt(
            contentResolver,
            Settings.System.HAPTIC_FEEDBACK_ENABLED,
            1,
        ) == 1
    } catch (_: Exception) {
        true
    }

    private fun supportsComposition(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val v = vibrator ?: return false
        return v.hasVibrator() && v.areAllPrimitivesSupported(
            VibrationEffect.Composition.PRIMITIVE_CLICK,
            VibrationEffect.Composition.PRIMITIVE_TICK,
        )
    }

    private fun hapticCapabilities(): Map<String, Any> = mapOf(
        "hasVibrator" to (vibrator?.hasVibrator() ?: false),
        // «Точный» — тот, у которого есть интенсивность и из которого можно
        // собрать рисунок. На простом эксцентрике его не будет никогда, и
        // обещать человеку айфоновский отклик там нечестно.
        "precise" to supportsComposition(),
        "predefined" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
    )

    /**
     * Возвращает true, если отклик действительно проигран. false означает
     * «сделай сам» — Dart-сторона отдаст штатный HapticFeedback.
     */
    private fun playHaptic(effect: String): Boolean {
        val v = vibrator ?: return false
        if (!v.hasVibrator()) return false
        if (!systemHapticsEnabled()) return true

        if (supportsComposition() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val click = VibrationEffect.Composition.PRIMITIVE_CLICK
            val tick = VibrationEffect.Composition.PRIMITIVE_TICK
            val rise = VibrationEffect.Composition.PRIMITIVE_QUICK_RISE

            val composition = VibrationEffect.startComposition()
            when (effect) {
                // Лёгкое касание: один тик вполсилы. На iPhone это light impact.
                "tap" -> composition.addPrimitive(tick, 0.45f, 0)
                // Выбор — ещё тише: он повторяется чаще всего.
                "select" -> composition.addPrimitive(tick, 0.32f, 0)
                // Отправка: короткий разгон и щелчок — «ушло».
                "send" -> composition
                    .addPrimitive(rise, 0.35f, 0)
                    .addPrimitive(click, 0.5f, 0)
                // Пришло: два тихих тика по возрастанию.
                "receive" -> composition
                    .addPrimitive(tick, 0.35f, 0)
                    .addPrimitive(tick, 0.55f, 55)
                // Получилось: тише-громче, как success на iPhone.
                "success" -> composition
                    .addPrimitive(click, 0.5f, 0)
                    .addPrimitive(click, 0.85f, 80)
                // Внимание: наоборот, громче-тише.
                "warning" -> composition
                    .addPrimitive(click, 0.85f, 0)
                    .addPrimitive(click, 0.5f, 90)
                // Ошибка: три удара, средний слабее — её нельзя спутать.
                "error" -> composition
                    .addPrimitive(click, 0.9f, 0)
                    .addPrimitive(click, 0.6f, 70)
                    .addPrimitive(click, 0.9f, 70)
                // Уведомление: разгон и уверенный щелчок.
                "notify" -> composition
                    .addPrimitive(rise, 0.5f, 0)
                    .addPrimitive(click, 0.75f, 0)
                else -> composition.addPrimitive(tick, 0.45f, 0)
            }
            return try {
                v.vibrate(composition.compose())
                true
            } catch (_: Exception) {
                false
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val predefined = when (effect) {
                "tap", "select", "receive" -> VibrationEffect.EFFECT_TICK
                "success", "notify" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                "error" -> VibrationEffect.EFFECT_HEAVY_CLICK
                else -> VibrationEffect.EFFECT_CLICK
            }
            return try {
                v.vibrate(VibrationEffect.createPredefined(predefined))
                true
            } catch (_: Exception) {
                false
            }
        }

        return false
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
