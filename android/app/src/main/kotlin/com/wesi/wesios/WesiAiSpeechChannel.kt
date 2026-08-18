package com.wesi.wesios

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
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
 *
 * Important contract: `speak` completes only when the utterance actually
 * finishes (or is stopped/failed). The hands-free voice session waits for
 * this Future before reopening the microphone; returning immediately after
 * TextToSpeech.speak() would let speech recognition hear the phone's own
 * speaker and could create a self-conversation loop.
 */
object WesiAiSpeechChannel {
    private const val CHANNEL = "wesios/ai_speech"
    private const val MAX_TEXT_LENGTH = 12000

    private var tts: TextToSpeech? = null
    private var ready = false
    private var registered = false
    private var pendingResult: MethodChannel.Result? = null
    private var pendingUtteranceId: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun finishPending(success: Boolean, utteranceId: String? = null) {
        if (utteranceId != null && pendingUtteranceId != utteranceId) return
        val result = pendingResult ?: return
        pendingResult = null
        pendingUtteranceId = null
        mainHandler.post { result.success(success) }
    }

    fun register(context: Context, messenger: BinaryMessenger) {
        if (registered) return
        registered = true

        tts = TextToSpeech(context.applicationContext) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                tts?.language = Locale.getDefault()
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        finishPending(true, utteranceId)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        finishPending(false, utteranceId)
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        finishPending(false, utteranceId)
                    }

                    override fun onStop(utteranceId: String?, interrupted: Boolean) {
                        finishPending(false, utteranceId)
                    }
                })
            }
        }

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(ready)
                "stop" -> {
                    tts?.stop()
                    finishPending(false)
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

                    // QUEUE_FLUSH interrupts a previous utterance. Complete its
                    // pending Dart Future before replacing it with the new one.
                    tts?.stop()
                    finishPending(false)

                    val utteranceId = "wesi_ai_${System.currentTimeMillis()}"
                    pendingResult = result
                    pendingUtteranceId = utteranceId
                    val status = tts?.speak(
                        text,
                        TextToSpeech.QUEUE_FLUSH,
                        null,
                        utteranceId,
                    ) ?: TextToSpeech.ERROR
                    if (status != TextToSpeech.SUCCESS) {
                        finishPending(false, utteranceId)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun shutdown() {
        tts?.stop()
        finishPending(false)
        tts?.shutdown()
        tts = null
        ready = false
        registered = false
    }
}
