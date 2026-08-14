package com.wesi.wesios

import android.content.Context
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Low-latency local speech output for Wesi AI.
 *
 * This channel uses the Android system TTS engine only. It does not send the
 * assistant message to another network service and does not contain provider
 * credentials. Natural persona voices remain a separate server-side media
 * pipeline.
 */
object WesiAiSpeechChannel {
    private const val CHANNEL = "wesios/ai_speech"
    private const val MAX_TEXT_LENGTH = 12000

    private var tts: TextToSpeech? = null
    private var ready = false
    private var registered = false

    fun register(context: Context, messenger: BinaryMessenger) {
        if (registered) return
        registered = true

        tts = TextToSpeech(context.applicationContext) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                tts?.language = Locale.getDefault()
            }
        }

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(ready)
                "stop" -> {
                    tts?.stop()
                    result.success(true)
                }
                "speak" -> {
                    if (!ready) {
                        result.error("tts_not_ready", "Android TextToSpeech is not ready", null)
                        return@setMethodCallHandler
                    }
                    val raw = call.argument<String>("text")?.trim().orEmpty()
                    if (raw.isEmpty()) {
                        result.error("empty_text", "Text is required", null)
                        return@setMethodCallHandler
                    }
                    val text = if (raw.length <= MAX_TEXT_LENGTH) raw else raw.substring(0, MAX_TEXT_LENGTH)
                    val languageTag = call.argument<String>("languageTag")?.trim().orEmpty()
                    if (languageTag.isNotEmpty()) {
                        val locale = Locale.forLanguageTag(languageTag)
                        if (locale.language.isNotEmpty()) tts?.language = locale
                    }
                    val rate = (call.argument<Number>("rate")?.toFloat() ?: 1.0f)
                        .coerceIn(0.65f, 1.35f)
                    val pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1.0f)
                        .coerceIn(0.75f, 1.25f)
                    tts?.setSpeechRate(rate)
                    tts?.setPitch(pitch)
                    val status = tts?.speak(
                        text,
                        TextToSpeech.QUEUE_FLUSH,
                        null,
                        "wesi_ai_${System.currentTimeMillis()}",
                    ) ?: TextToSpeech.ERROR
                    result.success(status == TextToSpeech.SUCCESS)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ready = false
        registered = false
    }
}
