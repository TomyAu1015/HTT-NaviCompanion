package com.tomy.httnavicompanion.audio

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class VoiceInputLanguage(
    val localeTag: String,
    val shortLabel: String,
    val displayName: String
) {
    CANTONESE("yue-Hant-HK", "粤语", "粤语 / 广东话 (yue-HK)"),
    MANDARIN("zh-CN", "普通话", "普通话 (zh-CN)"),
    TRADITIONAL("zh-TW", "繁體", "繁體中文 (zh-TW)"),
    ENGLISH("en-US", "EN", "English (en-US)"),
    JAPANESE("ja-JP", "日本語", "日本語 (ja-JP)")
}

class VoiceInputManager(private val context: Context) {
    private val prefs = context.getSharedPreferences("htt_voice_input_prefs", Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording

    private val _statusMessage = MutableStateFlow("")
    val statusMessage: StateFlow<String> = _statusMessage

    private val _selectedLanguage = MutableStateFlow(
        VoiceInputLanguage.values().firstOrNull { it.localeTag == prefs.getString("lang", "yue-Hant-HK") }
            ?: VoiceInputLanguage.CANTONESE
    )
    val selectedLanguage: StateFlow<VoiceInputLanguage> = _selectedLanguage

    private var speechRecognizer: SpeechRecognizer? = null
    private var onTextCallback: ((String) -> Unit)? = null

    fun setLanguage(lang: VoiceInputLanguage) {
        _selectedLanguage.value = lang
        prefs.edit().putString("lang", lang.localeTag).apply()
    }

    fun startRecording(onUpdate: (String) -> Unit) {
        stopRecording()
        onTextCallback = onUpdate
        _statusMessage.value = ""

        mainHandler.post {
            if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                _statusMessage.value = "当前系统未启用语音识别服务，请在系统设置中开启语音识别或安装离线语言包"
                return@post
            }
            try {
                val sr = SpeechRecognizer.createSpeechRecognizer(context)
                speechRecognizer = sr
                sr.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        _isRecording.value = true
                    }
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}
                    override fun onError(error: Int) {
                        _statusMessage.value = when (error) {
                            SpeechRecognizer.ERROR_NO_MATCH -> "未听清内容，请再试一次"
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "未检测到说话"
                            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "网络超时，可在系统语音设置下载离线语言包"
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "请先授予麦克风权限"
                            else -> "语音识别结束 (代码 $error)"
                        }
                        stopRecording()
                    }
                    override fun onResults(results: Bundle?) {
                        val best = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                        if (best.isNotBlank()) onTextCallback?.invoke(best)
                        stopRecording()
                    }
                    override fun onPartialResults(partialResults: Bundle?) {
                        val partial = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                        if (partial.isNotBlank()) onTextCallback?.invoke(partial)
                    }
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val langTag = _selectedLanguage.value.localeTag
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, langTag)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, langTag)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                _isRecording.value = true
                sr.startListening(intent)
            } catch (e: Exception) {
                _statusMessage.value = "启动语音识别失败：${e.message}"
                stopRecording()
            }
        }
    }

    fun stopRecording() {
        mainHandler.post {
            try {
                speechRecognizer?.stopListening()
                speechRecognizer?.destroy()
            } catch (_: Exception) {}
            speechRecognizer = null
            _isRecording.value = false
        }
    }
}
