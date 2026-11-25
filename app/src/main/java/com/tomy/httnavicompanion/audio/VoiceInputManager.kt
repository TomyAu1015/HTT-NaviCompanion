package com.tomy.httnavicompanion.audio

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionService
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

    private val _rmsLevel = MutableStateFlow(0f)
    val rmsLevel: StateFlow<Float> = _rmsLevel

    private val _statusMessage = MutableStateFlow("")
    val statusMessage: StateFlow<String> = _statusMessage

    private val _selectedLanguage = MutableStateFlow(
        VoiceInputLanguage.values().firstOrNull { it.localeTag == prefs.getString("lang", "yue-Hant-HK") }
            ?: VoiceInputLanguage.CANTONESE
    )
    val selectedLanguage: StateFlow<VoiceInputLanguage> = _selectedLanguage

    private var speechRecognizer: SpeechRecognizer? = null
    private var onTextCallback: ((String) -> Unit)? = null
    private var onFallbackDialog: ((Intent) -> Unit)? = null
    private var sessionStartMs: Long = 0L

    fun setLanguage(lang: VoiceInputLanguage) {
        _selectedLanguage.value = lang
        prefs.edit().putString("lang", lang.localeTag).apply()
    }

    fun buildRecognizerIntent(): Intent {
        val langTag = _selectedLanguage.value.localeTag
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, langTag)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, langTag)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "请说话（${_selectedLanguage.value.shortLabel}）...")
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 3000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 4000L)
        }
    }

    private fun resolveBestRecognitionServices(): List<ComponentName?> {
        val candidates = mutableListOf<ComponentName?>()
        try {
            val services = context.packageManager.queryIntentServices(
                Intent(RecognitionService.SERVICE_INTERFACE),
                0
            )
            // Prefer Google / standard RecognitionService first if present, then any non-default, then default (null)
            val google = services.firstOrNull { it.serviceInfo.packageName.contains("google") }
            if (google != null) {
                candidates.add(ComponentName(google.serviceInfo.packageName, google.serviceInfo.name))
            }
            services.forEach { ri ->
                val cn = ComponentName(ri.serviceInfo.packageName, ri.serviceInfo.name)
                if (cn !in candidates) candidates.add(cn)
            }
        } catch (_: Exception) {}
        candidates.add(null)
        return candidates
    }

    fun startRecording(
        onUpdate: (String) -> Unit,
        onFallbackToDialog: ((Intent) -> Unit)? = null
    ) {
        onTextCallback = onUpdate
        onFallbackDialog = onFallbackToDialog
        _statusMessage.value = ""

        mainHandler.post {
            val queue = resolveBestRecognitionServices().toMutableList()
            tryStartWithQueue(queue)
        }
    }

    private fun tryStartWithQueue(queue: MutableList<ComponentName?>) {
        destroyRecognizerSync()
        val intent = buildRecognizerIntent()

        if (queue.isEmpty()) {
            if (onFallbackDialog != null) {
                _statusMessage.value = "已调用系统语音录入（支持粤语/多语言）"
                onFallbackDialog?.invoke(intent)
            } else {
                _statusMessage.value = "当前设备暂不支持后台语音识别服务"
            }
            return
        }

        val serviceComp = queue.removeAt(0)
        try {
            val sr = if (serviceComp != null) {
                SpeechRecognizer.createSpeechRecognizer(context, serviceComp)
            } else {
                SpeechRecognizer.createSpeechRecognizer(context)
            }
            speechRecognizer = sr
            sessionStartMs = System.currentTimeMillis()
            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    _isRecording.value = true
                    _statusMessage.value = ""
                }
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {
                    _rmsLevel.value = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
                }
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) {
                    val elapsed = System.currentTimeMillis() - sessionStartMs
                    destroyRecognizerSync()
                    if ((error == SpeechRecognizer.ERROR_CLIENT ||
                            error == SpeechRecognizer.ERROR_AUDIO ||
                            error == SpeechRecognizer.ERROR_SERVER ||
                            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) && elapsed < 1500L
                    ) {
                        if (queue.isNotEmpty()) {
                            tryStartWithQueue(queue)
                            return
                        }
                        if (onFallbackDialog != null) {
                            _statusMessage.value = "已调用系统语音录入（支持粤语/多语言）"
                            onFallbackDialog?.invoke(buildRecognizerIntent())
                            return
                        }
                    }
                    _statusMessage.value = when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH -> "未听清内容，请靠近麦克风重试"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "未检测到说话"
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "网络超时，可在系统语音设置下载离线语言包"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "请先授予麦克风权限"
                        else -> "语音识别结束 (代码 $error)"
                    }
                }
                override fun onResults(results: Bundle?) {
                    val best = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    if (best.isNotBlank()) onTextCallback?.invoke(best)
                    destroyRecognizerSync()
                }
                override fun onPartialResults(partialResults: Bundle?) {
                    val partial = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    if (partial.isNotBlank()) onTextCallback?.invoke(partial)
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            _isRecording.value = true
            sr.startListening(intent)
        } catch (_: Exception) {
            tryStartWithQueue(queue)
        }
    }

    fun finishListeningGracefully() {
        mainHandler.post {
            try {
                speechRecognizer?.stopListening()
            } catch (_: Exception) {
                destroyRecognizerSync()
            }
        }
    }

    fun stopRecording() {
        mainHandler.post {
            destroyRecognizerSync()
        }
    }

    private fun destroyRecognizerSync() {
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
        _isRecording.value = false
        _rmsLevel.value = 0f
    }
}
