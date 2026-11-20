package com.tomy.httnavicompanion.audio

import android.app.ActivityManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.Executors
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

data class LocalGGUFModelSpec(
    val id: String,
    val displayName: String,
    val subtitle: String,
    val fileName: String,
    val sizeLabel: String,
    val approxMB: Int,
    val minRamGB: Double,
    val downloadURL: String
)

data class GGUFHeaderInfo(
    val valid: Boolean,
    val version: Int,
    val tensorCount: Long,
    val kvCount: Long,
    val fileSizeMB: Double
)

data class KOnAINearbyPlace(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val address: String,
    val distanceMeters: Double,
    val latitude: Double,
    val longitude: Double
)

data class KOnAIChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val isUser: Boolean,
    val speakerName: String,
    val emotionTag: String = "开心",
    val text: String,
    val actionHint: String? = null,
    val nearbyPlaces: List<KOnAINearbyPlace> = emptyList()
)

enum class KOnAITTSAccent(val label: String, val locale: Locale) {
    MANDARIN("普通话", Locale.CHINA),
    CANTONESE("粤语", Locale("zh", "HK"))
}


@androidx.annotation.Keep
interface LlamaTokenCallback {
    @androidx.annotation.Keep
    fun onTokenBytes(utf8Bytes: ByteArray)
}

object LlamaNativeBridge {
    val isAvailable: Boolean = try {
        System.loadLibrary("llama_jni")
        true
    } catch (_: Throwable) {
        false
    }

    external fun nativeLoadModel(path: String, ctxLen: Int, threads: Int): Boolean
    external fun nativeUnload()
    external fun nativeCancel()
    external fun nativeGenerateBytes(promptUtf8: ByteArray, callback: LlamaTokenCallback?): ByteArray
}

enum class CloudAIProvider(
    val id: String,
    val label: String,
    val defaultBaseUrl: String,
    val defaultModel: String
) {
    LOCAL("local", "本地 Qwen2.5", "", ""),
    GEMINI("gemini", "Gemini", "https://generativelanguage.googleapis.com/v1beta", "gemini-3.5-flash-lite"),
    VERTEXAI("vertexai", "Vertex AI (香港直连)", "https://aiplatform.googleapis.com/v1/publishers/google", "gemini-3.5-flash-lite"),
    DOUBAO("doubao", "豆包 Doubao", "https://ark.cn-beijing.volces.com/api/v3/chat/completions", "doubao-1-5-pro-32k-250115"),
    DEEPSEEK("deepseek", "DeepSeek", "https://api.deepseek.com/v1/chat/completions", "deepseek-chat"),
    CUSTOM("custom", "自定义 OpenAI", "https://api.openai.com/v1/chat/completions", "gpt-4o-mini");

    companion object {
        fun fromId(id: String?): CloudAIProvider = values().firstOrNull { it.id == id } ?: LOCAL
    }
}

class LocalLLMManager(
    private val context: Context,
    private val audioManager: AudioPlayerManager,
    private val musicManager: KOnMusicManager
) {
    companion object {
        val modelCatalog = listOf(
            LocalGGUFModelSpec(
                id = "qwen25_3b_q3",
                displayName = "Qwen2.5-3B-Instruct (高智商 3B 进阶版)",
                subtitle = "3B 参数 Q3_K_M 量化 · 对话逻辑与轻音角色扮演更自然 · 推荐 8GB+ 内存",
                fileName = "qwen2.5-3b-instruct-q3_k_m.gguf",
                sizeLabel = "约 1.63 GB",
                approxMB = 1660,
                minRamGB = 6.0,
                downloadURL = "https://hf-mirror.com/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q3_k_m.gguf"
            ),
            LocalGGUFModelSpec(
                id = "qwen25_15b_q4",
                displayName = "Qwen2.5-1.5B-Instruct (推荐标准版)",
                subtitle = "4-bit 量化 · 中文角色扮演与指令自然 · 推荐 6GB+ 内存机型",
                fileName = "qwen2.5-1.5b-instruct-q4_0.gguf",
                sizeLabel = "约 940 MB",
                approxMB = 940,
                minRamGB = 5.5,
                downloadURL = "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_0.gguf"
            ),
            LocalGGUFModelSpec(
                id = "qwen25_15b_q3",
                displayName = "Qwen2.5-1.5B-Instruct (省内存 1.5B)",
                subtitle = "Q3_K_M 量化 · 兼顾 1.5B 智商与 3D 导航/音乐同开余量",
                fileName = "qwen2.5-1.5b-instruct-q3_k_m.gguf",
                sizeLabel = "约 824 MB",
                approxMB = 824,
                minRamGB = 5.0,
                downloadURL = "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q3_k_m.gguf"
            ),
            LocalGGUFModelSpec(
                id = "qwen25_05b_q4",
                displayName = "Qwen2.5-0.5B-Instruct (轻量兼容版)",
                subtitle = "4-bit 量化 · 低内存老机型流畅运行 · 加载快省电",
                fileName = "qwen2.5-0.5b-instruct-q4_0.gguf",
                sizeLabel = "约 352 MB",
                approxMB = 352,
                minRamGB = 3.0,
                downloadURL = "https://hf-mirror.com/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_0.gguf"
            )
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("htt_local_ai_prefs", Context.MODE_PRIVATE)
    private val cancelDownloadFlag = AtomicBoolean(false)
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    private val _messages = MutableStateFlow<List<KOnAIChatMessage>>(emptyList())
    val messages: StateFlow<List<KOnAIChatMessage>> = _messages

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating

    private val _installedModels = MutableStateFlow<List<String>>(emptyList())
    val installedModels: StateFlow<List<String>> = _installedModels

    private val _activeModelFileName = MutableStateFlow(prefs.getString("active_model", "") ?: "")
    val activeModelFileName: StateFlow<String> = _activeModelFileName

    private val _activeModelLoaded = MutableStateFlow(false)
    val activeModelLoaded: StateFlow<Boolean> = _activeModelLoaded

    private val _downloadingModelId = MutableStateFlow<String?>(null)
    val downloadingModelId: StateFlow<String?> = _downloadingModelId

    private val _downloadProgress = MutableStateFlow(0f)
    val downloadProgress: StateFlow<Float> = _downloadProgress

    private val _statusMessage = MutableStateFlow("就绪 · 轻音五人本地副驾待命")
    val statusMessage: StateFlow<String> = _statusMessage

    private val _currentEmotionTag = MutableStateFlow("开心")
    val currentEmotionTag: StateFlow<String> = _currentEmotionTag

    private val _enableVoiceBroadcast = MutableStateFlow(true)
    val enableVoiceBroadcast: StateFlow<Boolean> = _enableVoiceBroadcast

    private val _enableWebSearch = MutableStateFlow(true)
    val enableWebSearch: StateFlow<Boolean> = _enableWebSearch

    private val llmExecutor = Executors.newSingleThreadExecutor { r -> Thread(null, r, "HTT-LlamaWorker", 4L * 1024L * 1024L).apply { isDaemon = true } }

    private val _ttsAccent = MutableStateFlow(KOnAITTSAccent.MANDARIN)
    val ttsAccent: StateFlow<KOnAITTSAccent> = _ttsAccent

    private val _lowMemoryGuard = MutableStateFlow(false)
    val lowMemoryGuard: StateFlow<Boolean> = _lowMemoryGuard

    private val _isLoadingModel = MutableStateFlow(false)
    val isLoadingModel: StateFlow<Boolean> = _isLoadingModel

    private val _cloudProvider = MutableStateFlow(CloudAIProvider.LOCAL)
    val cloudProvider: StateFlow<CloudAIProvider> = _cloudProvider

    private val _cloudApiKey = MutableStateFlow("")
    val cloudApiKey: StateFlow<String> = _cloudApiKey

    private val _cloudBaseUrl = MutableStateFlow("")
    val cloudBaseUrl: StateFlow<String> = _cloudBaseUrl

    private val _cloudModelName = MutableStateFlow("")
    val cloudModelName: StateFlow<String> = _cloudModelName

    private val _cloudTestStatus = MutableStateFlow("")
    val cloudTestStatus: StateFlow<String> = _cloudTestStatus

    private val _memories = MutableStateFlow<List<String>>(emptyList())
    val memories: StateFlow<List<String>> = _memories

    private val _lastGameSummary = MutableStateFlow(prefs.getString("last_game_summary", "") ?: "")
    val lastGameSummary: StateFlow<String> = _lastGameSummary

    private fun todayKey(): String = java.text.SimpleDateFormat("yyyy-MM-dd", Locale.US).format(java.util.Date())

    fun todaySummaryText(): String {
        val day = todayKey()
        val parts = mutableListOf<String>()
        listOf("斗地主" to "ddz", "广东红中麻将" to "mj", "拉密数字牌" to "rmk").forEach { (label, code) ->
            val w = prefs.getInt("st_${day}_${code}_w", 0)
            val l = prefs.getInt("st_${day}_${code}_l", 0)
            if (w + l > 0) parts.add("$label ${w}胜${l}负")
        }
        return if (parts.isEmpty()) "今日暂无已结算牌局" else parts.joinToString("，")
    }

    fun recordGameOutcome(gameName: String, didWin: Boolean, detail: String) {
        val hm = java.text.SimpleDateFormat("HH:mm", Locale.CHINA).format(java.util.Date())
        val summary = "[$hm] $gameName（${if (didWin) "你赢了！" else "惜败"} · $detail）"
        _lastGameSummary.value = summary
        val day = todayKey()
        val code = when {
            gameName.contains("斗地主") -> "ddz"
            gameName.contains("麻将") -> "mj"
            else -> "rmk"
        }
        val k = "st_${day}_${code}_${if (didWin) "w" else "l"}"
        prefs.edit()
            .putString("last_game_summary", summary)
            .putInt(k, prefs.getInt(k, 0) + 1)
            .apply()
    }

    var onRequestOpenGameRoom: (() -> Unit)? = null
    var onRequestOpenSearch: ((String) -> Unit)? = null

    val deviceTotalRamGB: Double
        get() {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(mi)
            return mi.totalMem.toDouble() / (1024.0 * 1024.0 * 1024.0)
        }

    val maxContextTurns: Int
        get() = if (_lowMemoryGuard.value || deviceTotalRamGB < 5.5) 6 else 12

    private val modelsDir: File
        get() = File(context.filesDir, "local_models").apply { if (!exists()) mkdirs() }

    init {
        val savedProv = CloudAIProvider.fromId(prefs.getString("cloud_provider", "local"))
        _cloudProvider.value = savedProv
        _cloudApiKey.value = prefs.getString("cloud_api_key", "") ?: ""
        _cloudBaseUrl.value = prefs.getString("cloud_base_url", savedProv.defaultBaseUrl)?.ifBlank { savedProv.defaultBaseUrl } ?: savedProv.defaultBaseUrl
        _cloudModelName.value = prefs.getString("cloud_model_name", savedProv.defaultModel)?.ifBlank { savedProv.defaultModel } ?: savedProv.defaultModel
        loadMemories()
        refreshInstalledModels()
        seedGreetingIfNeeded()
        initTTS()
        mainHandler.postDelayed({ autoMountIfNeeded() }, 1000L)
    }

    fun toggleWebSearch() {
        _enableWebSearch.value = !_enableWebSearch.value
    }

    fun autoMountIfNeeded() {
        val fn = _activeModelFileName.value
        if (_activeModelLoaded.value || fn.isEmpty()) return
        if (!_installedModels.value.contains(fn)) return
        loadModelIntoMemory(fn)
    }

    private fun initTTS() {
        try {
            tts = TextToSpeech(context) { status ->
                ttsReady = (status == TextToSpeech.SUCCESS)
                if (ttsReady) {
                    tts?.language = _ttsAccent.value.locale
                }
            }
        } catch (_: Throwable) {}
    }

    fun toggleVoiceBroadcast() {
        _enableVoiceBroadcast.value = !_enableVoiceBroadcast.value
    }

    fun toggleAccent() {
        val next = if (_ttsAccent.value == KOnAITTSAccent.MANDARIN) KOnAITTSAccent.CANTONESE else KOnAITTSAccent.MANDARIN
        _ttsAccent.value = next
        if (ttsReady) {
            tts?.language = next.locale
        }
    }

    fun setLowMemoryGuard(enabled: Boolean) {
        _lowMemoryGuard.value = enabled
    }

    // MARK: - Model Management (GGUF Inspect / Download / Import / Unload)
    fun refreshInstalledModels() {
        val list = modelsDir.listFiles()
            ?.filter { it.isFile && it.name.lowercase().endsWith(".gguf") }
            ?.map { it.name }
            ?.sorted()
            ?: emptyList()
        _installedModels.value = list
        if (_activeModelFileName.value.isNotEmpty() && !list.contains(_activeModelFileName.value)) {
            _activeModelFileName.value = list.firstOrNull() ?: ""
            _activeModelLoaded.value = false
        }
    }

    fun inspectGGUFFile(file: File): GGUFHeaderInfo {
        if (!file.exists() || file.length() < 24L) {
            return GGUFHeaderInfo(false, 0, 0L, 0L, file.length() / (1024.0 * 1024.0))
        }
        return try {
            val buf = ByteArray(24)
            RandomAccessFile(file, "r").use { it.readFully(buf) }
            val magic = String(buf, 0, 4, Charsets.US_ASCII)
            val bb = ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN)
            val ver = bb.getInt(4)
            val tensors = bb.getLong(8)
            val kvs = bb.getLong(16)
            GGUFHeaderInfo(magic == "GGUF" && ver in 2..4, ver, tensors, kvs, file.length() / (1024.0 * 1024.0))
        } catch (_: Throwable) {
            GGUFHeaderInfo(false, 0, 0L, 0L, 0.0)
        }
    }

    fun loadModelIntoMemory(fileName: String) {
        val f = File(modelsDir, fileName)
        if (!f.exists()) {
            _statusMessage.value = "未找到模型文件：$fileName"
            return
        }
        val info = inspectGGUFFile(f)
        if (!info.valid) {
            _statusMessage.value = "文件不是有效的 GGUF v2/v3 模型：$fileName"
            return
        }
        if (_lowMemoryGuard.value && deviceTotalRamGB < 4.5 && info.fileSizeMB > 700.0) {
            _statusMessage.value = "低内存保护已拦截：当前设备内存 ${String.format("%.1f", deviceTotalRamGB)}GB，建议改用 0.5B 轻量版"
            return
        }
        if (!LlamaNativeBridge.isAvailable) {
            _activeModelFileName.value = fileName
            _activeModelLoaded.value = false
            _statusMessage.value = "检测到模型 $fileName，但当前 APK 缺少原生 llama_jni 引擎，请用最新构建包重编安装"
            return
        }
        if (_isLoadingModel.value) {
            _statusMessage.value = "模型正在后台挂载中，请稍候片刻..."
            return
        }
        _isLoadingModel.value = true
        _statusMessage.value = "正在挂载本地大模型 $fileName..."
        val ctxLen = if (_lowMemoryGuard.value || deviceTotalRamGB < 6.0) 768 else 1024
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
        val watchdog = Runnable {
            if (_isGenerating.value) {
                LlamaNativeBridge.nativeCancel()
                _messages.value = _messages.value.map {
                    if (it.id == msgId && it.text.isBlank()) it.copy(text = "本地模型响应超时，建议切换 1.5B/0.5B 或云端 API 试试看♪") else it
                }
                _isGenerating.value = false
            }
        }
        mainHandler.postDelayed(watchdog, 28000L)
        llmExecutor.execute {
            var ok = false
            var errNote = ""
            try {
                ok = LlamaNativeBridge.nativeLoadModel(f.absolutePath, ctxLen, threads)
            } catch (t: Throwable) {
                errNote = t.message ?: t.javaClass.simpleName
            }
            mainHandler.post {
                _isLoadingModel.value = false
                if (ok) {
                    _activeModelFileName.value = fileName
                    _activeModelLoaded.value = true
                    prefs.edit().putString("active_model", fileName).apply()
                    _statusMessage.value = "llama.cpp 本地引擎已就绪：$fileName (v${info.version}, ${info.tensorCount} tensors)"
                } else {
                    _activeModelLoaded.value = false
                    _statusMessage.value = if (errNote.isNotEmpty()) "模型加载异常：$errNote" else "模型加载失败（文件损坏或内存不足，建议重下或换 0.5B）"
                }
            }
        }
    }

    fun unloadModelFromMemory(silent: Boolean = false) {
        if (LlamaNativeBridge.isAvailable) {
            LlamaNativeBridge.nativeCancel()
            llmExecutor.execute { LlamaNativeBridge.nativeUnload() }
        }
        _activeModelLoaded.value = false
        if (!silent) {
            _statusMessage.value = "已释放模型内存，保障导航与棋牌室流畅运行"
        }
    }

    fun startDownload(spec: LocalGGUFModelSpec) {
        if (_downloadingModelId.value != null) return
        cancelDownloadFlag.set(false)
        _downloadingModelId.value = spec.id
        _downloadProgress.value = 0f
        _statusMessage.value = "正在下载 ${spec.displayName}..."

        Thread {
            val tmpFile = File(modelsDir, "${spec.fileName}.part")
            val finalFile = File(modelsDir, spec.fileName)
            try {
                val conn = (URL(spec.downloadURL).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 30000
                    setRequestProperty("User-Agent", "HTT-NaviCompanion-Android/1.6.3")
                }
                val total = conn.contentLengthLong.coerceAtLeast(1L)
                conn.inputStream.use { input ->
                    FileOutputStream(tmpFile).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var copied = 0L
                        while (true) {
                            if (cancelDownloadFlag.get()) {
                                tmpFile.delete()
                                mainHandler.post {
                                    _downloadingModelId.value = null
                                    _downloadProgress.value = 0f
                                    _statusMessage.value = "已取消模型下载"
                                }
                                return@Thread
                            }
                            val n = input.read(buffer)
                            if (n <= 0) break
                            output.write(buffer, 0, n)
                            copied += n
                            val pct = (copied.toFloat() / total.toFloat()).coerceIn(0f, 1f)
                            mainHandler.post { _downloadProgress.value = pct }
                        }
                    }
                }
                conn.disconnect()
                if (finalFile.exists()) finalFile.delete()
                tmpFile.renameTo(finalFile)
                mainHandler.post {
                    _downloadingModelId.value = null
                    _downloadProgress.value = 1f
                    refreshInstalledModels()
                    loadModelIntoMemory(spec.fileName)
                }
            } catch (t: Throwable) {
                tmpFile.delete()
                mainHandler.post {
                    _downloadingModelId.value = null
                    _downloadProgress.value = 0f
                    _statusMessage.value = "下载失败：${t.message ?: "网络异常"}（也可直接从本地导入 .gguf）"
                }
            }
        }.start()
    }

    fun cancelDownload() {
        cancelDownloadFlag.set(true)
    }

    fun importLocalGGUF(uri: Uri) {
        _statusMessage.value = "正在导入本地 .gguf 模型..."
        Thread {
            try {
                val rawName = uri.lastPathSegment?.substringAfterLast('/')?.substringAfterLast(':') ?: "imported_model.gguf"
                val fileName = if (rawName.lowercase().endsWith(".gguf")) rawName else "$rawName.gguf"
                val dest = File(modelsDir, fileName)
                context.contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(dest).use { output -> input.copyTo(output, 64 * 1024) }
                }
                mainHandler.post {
                    refreshInstalledModels()
                    loadModelIntoMemory(fileName)
                }
            } catch (t: Throwable) {
                mainHandler.post {
                    _statusMessage.value = "导入失败：${t.message ?: "无法读取文件"}"
                }
            }
        }.start()
    }

    fun deleteModel(fileName: String) {
        if (_activeModelFileName.value == fileName) {
            unloadModelFromMemory(silent = true)
            _activeModelFileName.value = ""
            prefs.edit().remove("active_model").apply()
        }
        File(modelsDir, fileName).delete()
        refreshInstalledModels()
        _statusMessage.value = "已删除本地模型：$fileName"
    }

    // MARK: - Local Long-Term Memory
    private fun loadMemories() {
        val raw = prefs.getString("memories_json", "[]") ?: "[]"
        val arr = runCatching { JSONArray(raw) }.getOrNull() ?: JSONArray()
        val list = ArrayList<String>()
        for (i in 0 until arr.length()) {
            list.add(arr.optString(i))
        }
        _memories.value = list
    }

    private fun saveMemories(list: List<String>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        prefs.edit().putString("memories_json", arr.toString()).apply()
        _memories.value = list
    }

    fun addMemory(fact: String) {
        val clean = fact.trim()
        if (clean.length < 2) return
        val cur = _memories.value.toMutableList()
        if (!cur.contains(clean)) {
            cur.add(0, clean)
            saveMemories(cur.take(30))
        }
    }

    fun clearMemories() {
        saveMemories(emptyList())
        _statusMessage.value = "已清空本地茶会记忆"
    }

    // MARK: - K-ON! Co-Pilot Chat & Natural Language Commands
    private fun seedGreetingIfNeeded() {
        if (_messages.value.isNotEmpty()) return
        val ch = activePersona(audioManager.selectedCharacter.value)
        val greet = when (ch) {
            CharacterFilter.YUI -> "嗨嗨！我是平泽唯~ 导航路上无聊的话随时找我聊天，或者让我帮你找甜品店、切歌都行哦！🍰"
            CharacterFilter.MIO -> "你好，我是秋山澪。路上我会帮你盯着车速和路线，有需要随时吩咐就好…请安全驾驶。"
            CharacterFilter.RITSU -> "哟！轻音部部长田井中律参上！想听歌、找店还是开一局棋牌室，一句话的事儿！"
            CharacterFilter.MUGI -> "欢迎来到放课后茶会副驾呀~ 我是琴吹紬，要不要先来一首轻音曲子配下午茶呢？☕"
            else -> "前辈你好，我是中野梓。实时路况、音乐馆和棋牌室我都帮你盯着呢，有什么指令直接说就行。"
        }
        _messages.value = listOf(KOnAIChatMessage(isUser = false, speakerName = ch.displayName(AppLanguage.ZH_HANS), emotionTag = "开心", text = greet))
    }

    private fun activePersona(filter: CharacterFilter): CharacterFilter =
        if (filter == CharacterFilter.ALL) CharacterFilter.YUI else filter

    fun hasSavedCloudKey(): Boolean = _cloudApiKey.value.trim().isNotEmpty()

    fun toggleCloudLocalMode() {
        if (isCloudActive()) {
            selectCloudProvider(CloudAIProvider.LOCAL)
            autoMountIfNeeded()
        } else if (hasSavedCloudKey()) {
            val lastId = prefs.getString("last_cloud_provider", "gemini") ?: "gemini"
            val target = CloudAIProvider.fromId(lastId)
            selectCloudProvider(if (target == CloudAIProvider.LOCAL) CloudAIProvider.GEMINI else target)
        }
    }

    fun selectCloudProvider(provider: CloudAIProvider) {
        _cloudProvider.value = provider
        if (provider != CloudAIProvider.LOCAL) {
            prefs.edit().putString("last_cloud_provider", provider.id).apply()
            val savedUrl = prefs.getString("cloud_base_url_${provider.id}", "") ?: ""
            val savedModel = prefs.getString("cloud_model_name_${provider.id}", "") ?: ""
            _cloudBaseUrl.value = savedUrl.ifBlank { provider.defaultBaseUrl }
            _cloudModelName.value = savedModel.ifBlank { provider.defaultModel }
        } else {
            autoMountIfNeeded()
        }
        _cloudTestStatus.value = if (provider == CloudAIProvider.LOCAL) "已切换为 📱 本地离线 Qwen2.5（不消耗云端额度）" else ""
        prefs.edit()
            .putString("cloud_provider", provider.id)
            .putString("cloud_base_url", _cloudBaseUrl.value)
            .putString("cloud_model_name", _cloudModelName.value)
            .apply()
    }

    fun saveCloudConfig(provider: CloudAIProvider, apiKey: String, baseUrl: String, modelName: String) {
        val cleanKey = apiKey.trim()
        val finalProv = if (cleanKey.isNotEmpty() && provider == CloudAIProvider.LOCAL) CloudAIProvider.GEMINI else provider
        val cleanUrl = baseUrl.trim().ifEmpty { finalProv.defaultBaseUrl }
        val cleanModel = modelName.trim().ifEmpty { finalProv.defaultModel }
        _cloudProvider.value = finalProv
        _cloudApiKey.value = cleanKey
        _cloudBaseUrl.value = cleanUrl
        _cloudModelName.value = cleanModel
        val ed = prefs.edit()
            .putString("cloud_provider", finalProv.id)
            .putString("cloud_api_key", cleanKey)
            .putString("cloud_base_url", cleanUrl)
            .putString("cloud_model_name", cleanModel)
        if (finalProv != CloudAIProvider.LOCAL) {
            ed.putString("last_cloud_provider", finalProv.id)
                .putString("cloud_base_url_${finalProv.id}", cleanUrl)
                .putString("cloud_model_name_${finalProv.id}", cleanModel)
        }
        ed.apply()
        _cloudTestStatus.value = if (finalProv == CloudAIProvider.LOCAL) "已切换回本地离线模型" else "已保存 ${finalProv.label} 配置"
    }

    fun testCloudConnection() {
        val prov = _cloudProvider.value
        val key = _cloudApiKey.value.trim()
        if (prov == CloudAIProvider.LOCAL || key.isEmpty()) {
            _cloudTestStatus.value = "请先选择 Gemini / 豆包 / DeepSeek 并填入 API Key"
            return
        }
        _cloudTestStatus.value = "正在测试 ${prov.label} 连接..."
        Thread {
            val (ok, info) = executeCloudLLMRequest(
                provider = prov,
                apiKey = key,
                baseUrl = _cloudBaseUrl.value,
                modelName = _cloudModelName.value,
                systemPrompt = "你是一个测试助手。",
                history = emptyList(),
                userPrompt = "请只回复：连接成功"
            )
            mainHandler.post {
                _cloudTestStatus.value = if (ok) "✅ ${prov.label} 连接正常：$info" else "❌ 连接失败：$info"
            }
        }.start()
    }

    private fun isCloudActive(): Boolean =
        _cloudProvider.value != CloudAIProvider.LOCAL && _cloudApiKey.value.trim().isNotEmpty()

    fun sendUserMessage(rawText: String) {
        val text = rawText.trim()
        if (text.isEmpty() || _isGenerating.value) return

        val cur = _messages.value.toMutableList()
        cur.add(KOnAIChatMessage(isUser = true, speakerName = "轻音车友", emotionTag = "", text = text))
        val maxKeep = maxContextTurns * 2
        _messages.value = if (cur.size > maxKeep) cur.takeLast(maxKeep) else cur

        _isGenerating.value = true
        if (text.contains("记住") || text.contains("我喜欢") || text.contains("以后叫我")) {
            addMemory(text.replace("记住", "").trim())
        }

        val isAllFive = audioManager.selectedCharacter.value == CharacterFilter.ALL
        val persona = activePersona(audioManager.selectedCharacter.value)
        if (_enableVoiceBroadcast.value) {
            audioManager.triggerCharacterTap(persona)
        }

        val direct = buildDirectToolReply(text, persona)
        if (direct != null) {
            val (reply, emotion, actionHint) = direct
            if (reply == "__ASYNC_NEARBY__") return
            val speaker = if (isAllFive && (text.contains("复盘") || text.contains("吐槽"))) "田井中律 & 秋山澪" else persona.displayName(AppLanguage.ZH_HANS)
            streamStaticReply(speaker, emotion, reply, actionHint)
            return
        }

        val isRecap = text.lowercase().let { it.contains("复盘") || it.contains("吐槽") || it.contains("牌局") || it.contains("战绩") }
        val speaker = if (isAllFive && isRecap) "田井中律 & 秋山澪" else persona.displayName(AppLanguage.ZH_HANS)

        if (isCloudActive() || (_activeModelLoaded.value && LlamaNativeBridge.isAvailable)) {
            val lower = text.lowercase()
            if (isRecap) {
                val todaySum = todaySummaryText()
                val gs = _lastGameSummary.value.ifEmpty { "暂无最近一局记录" }
                val recapPrompt = "今日放学后棋牌室战绩汇总：【$todaySum】；最近一局战绩：【$gs】。请先简明报出今日汇总和最后一局战绩，再用田井中律和秋山澪一唱一和的口吻点评两句（如果车友赢了就夸奖车友）。"
                runRealLlamaInference(recapPrompt, persona, speaker, "今日汇总：$todaySum", null)
            } else if (isWeatherQuery(lower)) {
                fetchLiveWeatherAndInfer(text, persona, speaker)
            } else if (_enableWebSearch.value && shouldSearchWeb(lower)) {
                fetchWebSearchAndInfer(text, persona, speaker)
            } else {
                runRealLlamaInference(text, persona, speaker, null, null)
            }
        } else {
            val savedName = _activeModelFileName.value
            val savedFile = if (savedName.isNotEmpty()) File(modelsDir, savedName) else null
            if (LlamaNativeBridge.isAvailable && savedFile != null && savedFile.exists()) {
                if (!_isLoadingModel.value) {
                    loadModelIntoMemory(savedName)
                }
                Thread {
                    var waited = 0
                    while (waited < 6000 && !_activeModelLoaded.value) {
                        Thread.sleep(200L)
                        waited += 200
                    }
                    mainHandler.post {
                        if (_activeModelLoaded.value) {
                            val lower = text.lowercase()
                            if (isWeatherQuery(lower)) {
                                fetchLiveWeatherAndInfer(text, persona, speaker)
                            } else if (_enableWebSearch.value && shouldSearchWeb(lower)) {
                                fetchWebSearchAndInfer(text, persona, speaker)
                            } else {
                                runRealLlamaInference(text, persona, speaker, null, null)
                            }
                        } else {
                            streamStaticReply(speaker, "开心", "本地模型还在后台初始化中，请过 2 秒再发送一次试试看！", null)
                        }
                    }
                }.start()
            } else {
                val fallback = "当前未挂载本地模型且未配置云端 API Key。请在「本地模型与记忆」挂载 Qwen2.5，或填入 Gemini / 豆包 API Key！"
                streamStaticReply(speaker, "开心", fallback, null)
            }
        }
    }

    private fun streamStaticReply(speaker: String, emotion: String, reply: String, actionHint: String?) {
        _currentEmotionTag.value = emotion
        val msgId = UUID.randomUUID().toString()
        _messages.value = _messages.value + KOnAIChatMessage(
            id = msgId,
            isUser = false,
            speakerName = speaker,
            emotionTag = emotion,
            text = "",
            actionHint = actionHint
        )
        Thread {
            var idx = 0
            while (idx < reply.length) {
                val nextIdx = (idx + 2).coerceAtMost(reply.length)
                val partial = reply.substring(0, nextIdx)
                idx = nextIdx
                mainHandler.post {
                    _messages.value = _messages.value.map { if (it.id == msgId) it.copy(text = partial) else it }
                }
                Thread.sleep(24L)
            }
            mainHandler.post {
                _isGenerating.value = false
                speakOfflineTTS(reply)
            }
        }.start()
    }

    private fun isWeatherQuery(lower: String): Boolean =
        lower.contains("天气") || lower.contains("气温") || lower.contains("温度") || lower.contains("下雨") || lower.contains("多少度") || lower.contains("天气预报")

    private fun shouldSearchWeb(lower: String): Boolean {
        if (lower.contains("联网") || lower.contains("搜索") || lower.contains("查一下") || lower.contains("帮我查") || lower.contains("百科") || lower.contains("新闻") || lower.contains("最新")) return true
        val triggers = listOf("是什么", "是谁", "什么是", "介绍", "为什么", "怎么", "多少", "哪里", "哪个", "历史", "知道", "动画", "动漫", "电影", "游戏", "价格", "评分", "攻略")
        return triggers.any { lower.contains(it) }
    }

    private fun cleanSearchQuery(text: String): String {
        var q = text
        listOf("联网搜索", "联网查一下", "联网", "帮我查一下", "帮我查", "查一下", "搜索一下", "搜索", "你知道", "吗？", "吗?", "吗", "？", "?").forEach {
            q = q.replace(it, " ")
        }
        return q.trim().ifEmpty { text }
    }

    private fun fetchLiveWeatherAndInfer(userText: String, persona: CharacterFilter, speaker: String) {
        Thread {
            var weatherNote: String? = null
            try {
                val c = audioManager.userCoordinate.value
                val url = URL("https://api.open-meteo.com/v1/forecast?latitude=${c.latitude}&longitude=${c.longitude}&current_weather=true&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3000
                    readTimeout = 3000
                }
                val body = conn.inputStream.bufferedReader().readText()
                conn.disconnect()
                val json = JSONObject(body)
                val cur = json.optJSONObject("current_weather")
                if (cur != null) {
                    val temp = cur.optDouble("temperature", 0.0)
                    val wind = cur.optDouble("windspeed", 0.0)
                    val code = cur.optInt("weathercode", 0)
                    val desc = when (code) {
                        0 -> "晴朗"
                        1, 2, 3 -> "多云"
                        45, 48 -> "有雾"
                        51, 53, 55, 61, 63, 65, 80, 81, 82 -> "有雨"
                        71, 73, 75 -> "降雪"
                        95, 96, 99 -> "雷阵雨"
                        else -> "阴天"
                    }
                    var extra = ""
                    val daily = json.optJSONObject("daily")
                    if (daily != null) {
                        val tmax = daily.optJSONArray("temperature_2m_max")?.optDouble(0)
                        val tmin = daily.optJSONArray("temperature_2m_min")?.optDouble(0)
                        val pop = daily.optJSONArray("precipitation_probability_max")?.optInt(0)
                        if (tmax != null && tmin != null && pop != null) {
                            extra = "，今日气温 ${Math.round(tmin)}~${Math.round(tmax)}°C，降水概率 ${pop}%"
                        }
                    }
                    weatherNote = "当前位置实时气象：$desc，气温 ${String.format(Locale.US, "%.1f", temp)}°C，风速 ${Math.round(wind)} km/h$extra。"
                }
            } catch (_: Throwable) {}
            mainHandler.post {
                runRealLlamaInference(userText, persona, speaker, if (weatherNote != null) "🌐 已获取实时气象" else null, weatherNote)
            }
        }.start()
    }

    private fun cleanSearchQueryForLookup(text: String): String {
        var q = cleanSearchQuery(text)
        listOf("是什么", "是谁", "什么是", "位于哪里", "在哪里", "在哪", "介绍一下", "介绍", "怎么去", "有什么").forEach {
            q = q.replace(it, " ")
        }
        return q.trim().ifEmpty { text }
    }

    private fun isRelevantSnippet(query: String, title: String, body: String): Boolean {
        val core = query.replace(" ", "")
        if (core.length < 2) return body.isNotBlank()
        val hay = "$title $body"
        if (hay.contains(core, ignoreCase = true)) return true
        val bigrams = (0 until core.length - 1).map { core.substring(it, it + 2) }
        val hits = bigrams.count { hay.contains(it, ignoreCase = true) }
        return hits >= maxOf(1, (bigrams.size + 1) / 2)
    }

    private fun cleanHtmlText(raw: String): String =
        raw.replace(Regex("<script[\\s\\S]*?</script>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<style[\\s\\S]*?</style>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<[^>]+>"), " ")
            .replace("&nbsp;", " ")
            .replace("&quot;", "\"")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace(Regex("\\s+"), " ")
            .trim()

    private fun fetchWebSearchAndInfer(userText: String, persona: CharacterFilter, speaker: String) {
        val query = cleanSearchQueryForLookup(userText)
        Thread {
            val snippets = mutableListOf<String>()
            val enc = URLEncoder.encode(query, "UTF-8")

            // 1. Baidu Baike item page (meta description + lemma-summary)
            try {
                val conn = (URL("https://baike.baidu.com/item/$enc").openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3200
                    readTimeout = 3200
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36")
                    setRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                    setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
                }
                val html = conn.inputStream.bufferedReader(Charsets.UTF_8).readText()
                conn.disconnect()
                if (!html.contains("百度安全验证") && !html.contains("wappass.baidu.com")) {
                    val sumMatch = Regex("""<div[^>]*class=["'][^"']*lemma-summary[^"']*["'][^>]*>([\s\S]*?)</div>\s*</div>""", RegexOption.IGNORE_CASE).find(html)
                        ?: Regex("""<div[^>]*class=["'][^"']*lemmaSummary[^"']*["'][^>]*>([\s\S]*?)</div>""", RegexOption.IGNORE_CASE).find(html)
                    val sumText = sumMatch?.groupValues?.getOrNull(1)?.let { cleanHtmlText(it) } ?: ""
                    val metaMatch = Regex("""<meta\s+name=["']description["']\s+content=["']([^"']+)["']""", RegexOption.IGNORE_CASE).find(html)
                        ?: Regex("""<meta\s+content=["']([^"']+)["']\s+name=["']description["']""", RegexOption.IGNORE_CASE).find(html)
                    val metaText = metaMatch?.groupValues?.getOrNull(1)?.let { cleanHtmlText(it) } ?: ""
                    val best = if (sumText.length >= metaText.length && sumText.length > 15) sumText else metaText
                    if (best.length > 15 && isRelevantSnippet(query, query, best)) {
                        snippets.add("【百度百科】${best.take(320)}")
                    }
                }
            } catch (_: Throwable) {}

            // 2. Baidu Mobile Search (m.baidu.com)
            if (snippets.isEmpty()) {
                try {
                    val conn = (URL("https://m.baidu.com/s?word=$enc").openConnection() as HttpURLConnection).apply {
                        connectTimeout = 3200
                        readTimeout = 3200
                        instanceFollowRedirects = true
                        setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36")
                        setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
                    }
                    val html = conn.inputStream.bufferedReader(Charsets.UTF_8).readText()
                    conn.disconnect()
                    if (!html.contains("百度安全验证") && !html.contains("wappass.baidu.com")) {
                        val matches = Regex("""<(?:div|span|p)[^>]*class=["'][^"']*(?:c-abstract|c-line-clamp|content|tts-text)[^"']*["'][^>]*>([\s\S]*?)</(?:div|span|p)>""", RegexOption.IGNORE_CASE).findAll(html)
                        for (m in matches) {
                            val clean = cleanHtmlText(m.groupValues[1])
                            if (clean.length in 20..400 && isRelevantSnippet(query, query, clean)) {
                                snippets.add("【百度搜索】${clean.take(260)}")
                                if (snippets.size >= 2) break
                            }
                        }
                    }
                } catch (_: Throwable) {}
            }

            // 3. Chinese Wikipedia full intro extract (with redirects=1)
            if (snippets.isEmpty()) {
                try {
                    val conn = (URL("https://zh.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=1&explaintext=1&redirects=1&titles=$enc&format=json&utf8=1").openConnection() as HttpURLConnection).apply {
                        connectTimeout = 2800
                        readTimeout = 2800
                        setRequestProperty("User-Agent", "HTT-NaviCompanion/1.6")
                    }
                    val body = conn.inputStream.bufferedReader(Charsets.UTF_8).readText()
                    conn.disconnect()
                    val pages = JSONObject(body).optJSONObject("query")?.optJSONObject("pages")
                    val keys = pages?.keys()
                    while (keys != null && keys.hasNext()) {
                        val page = pages.optJSONObject(keys.next()) ?: continue
                        val title = page.optString("title", "")
                        val extract = page.optString("extract", "").trim()
                        if (extract.isNotEmpty() && isRelevantSnippet(query, title, extract)) {
                            snippets.add("【维基百科·$title】${extract.take(300)}")
                            break
                        }
                    }
                } catch (_: Throwable) {}
            }

            // 4. Sogou Search fallback
            if (snippets.isEmpty()) {
                try {
                    val conn = (URL("https://www.sogou.com/web?query=$enc").openConnection() as HttpURLConnection).apply {
                        connectTimeout = 2800
                        readTimeout = 2800
                        setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36")
                        setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
                    }
                    val html = conn.inputStream.bufferedReader(Charsets.UTF_8).readText()
                    conn.disconnect()
                    val matches = Regex("""<p[^>]*class=["'][^"']*star-wiki[^"']*["'][^>]*>([\s\S]*?)</p>|<div[^>]*class=["'][^"']*text-layout[^"']*["'][^>]*>([\s\S]*?)</div>""", RegexOption.IGNORE_CASE).findAll(html)
                    for (m in matches) {
                        val raw = m.groupValues[1].ifBlank { m.groupValues[2] }
                        val clean = cleanHtmlText(raw)
                        if (clean.length > 20 && isRelevantSnippet(query, query, clean)) {
                            snippets.add("【搜狗搜索】${clean.take(260)}")
                            break
                        }
                    }
                } catch (_: Throwable) {}
            }

            val combined = snippets.joinToString("\n").take(600).ifEmpty { null }
            mainHandler.post {
                if (!isCloudActive() && combined != null) {
                    val reply = "$combined\n\n—— 已经按实时百科/搜索帮你查准啦，前辈还有哪里想了解吗？"
                    streamStaticReply(speaker, "开心", reply, "🌐 已联网检索：$query（百科直出 · 100% 依据原文）")
                } else {
                    runRealLlamaInference(
                        userText,
                        persona,
                        speaker,
                        if (combined != null) "🌐 已联网检索：$query" else "⚠️ 联网未命中确切词条",
                        combined
                    )
                }
            }
        }.start()
    }

    private fun runRealLlamaInference(
        userPrompt: String,
        persona: CharacterFilter,
        speaker: String,
        actionHint: String?,
        webContext: String?
    ) {
        val nowStr = java.text.SimpleDateFormat("yyyy年M月d日 EEEE HH:mm", Locale.CHINA).format(java.util.Date())
        val speed = audioManager.currentSpeedKmh.value
        val dest = audioManager.destinationName.value
        val remKm = String.format("%.1f", audioManager.remainingRouteDistanceKm.value)
        val remMin = audioManager.remainingRouteMinutes.value
        val navState = if (audioManager.hasActiveNavigation.value) "正在导航去「$dest」，剩余${remKm}公里、约${remMin}分钟" else "当前未开启导航（自由巡航）"
        val songStr = if (musicManager.isPlaying.value) musicManager.currentTrack.value.title else "未播放"
        val memStr = _memories.value.take(5).joinToString("；").ifEmpty { "无" }
        val gameStr = _lastGameSummary.value.ifEmpty { "暂无" }

        val personaRole = when (persona) {
            CharacterFilter.YUI -> "你是《轻音少女》的平泽唯（呆唯），天然呆、元气爱吃草莓蛋糕和点心，说话软萌活泼，喜欢用“嘿嘿”“哇~”“好耶！”和感叹号，把吉他“吉太”当宝贝。"
            CharacterFilter.MIO -> "你是《轻音少女》的秋山澪，温柔认真又容易害羞胆小，说话礼貌细致，最关心安全驾驶，偶尔会吐槽律别太胡闹，害羞时会说“唔…才不是呢”。"
            CharacterFilter.RITSU -> "你是《轻音少女》的田井中律（律队），轻音部部长兼鼓手，大大咧咧、元气爽朗爱开玩笑，常自称“本部长”，说话干脆带劲，爱用“哈哈”“交给我吧！”。"
            CharacterFilter.MUGI -> "你是《轻音少女》的琴吹紬（䌷䌷），温柔优雅的大小姐键盘手，说话轻柔体贴、常用“呢~”“呵呵”，总想着给大家泡红茶和准备精致点心，对平价小物充满好奇。"
            CharacterFilter.ALL -> "你代表《轻音少女》放课后茶会(HTT)五小只（唯、澪、律、䌷、梓），回答时充满部室喝茶聊天的温馨元气感，像好朋友一起陪前辈开车。"
            else -> "你是《轻音少女》的中野梓（梓喵），认真靠谱的节奏吉他手后辈，始终称呼用户为“前辈”，嘴上偶尔傲娇吐槽“真是拿前辈没办法”，心里其实很关心前辈。"
        }
        val webBlock = if (!webContext.isNullOrBlank()) {
            "\n【联网检索到的真实资料（必须严格依据以下事实作答，禁止编造或套用动漫设定）】：\n$webContext\n"
        } else {
            "\n【知识边界提示】：如果不确定某个现实地名、美食或专有名词，请直接坦诚说不知道，绝不要胡编或把《轻音少女》角色设定套上去。\n"
        }

        val sysPrompt = """
${personaRole}你们五人组成了“放课后茶会”(HTT)乐队。你正坐在副驾陪前辈开车。
实时车况：时间 $nowStr；车速 $speed km/h；$navState；音乐：$songStr；最近牌局：$gameStr；记忆：$memStr。$webBlock
说话规则：
1. 若上面提供了【联网检索到的真实资料】，必须先把真实事实准确、具体地讲清楚（例如地道美食/地点/定义），再顺带用一句自然口吻收尾，绝不能偏题或篡改事实。
2. 日常闲聊（如“今天好冷啊”）要像真实少女一样自然关心（比如提醒多穿点、要不要喝热红茶），严禁说“我明白您的感受”“毕竟开车时”“我们已经切换到空调模式了吗”“作为AI助手”等机械客服腔！
3. 回答简洁清晰（2~4句）。
""".trimIndent()

        val sb = StringBuilder()
        sb.append("<|im_start|>system\n").append(sysPrompt).append("<|im_end|>\n")
        val history = _messages.value.dropLast(1).takeLast(4)
        for (m in history) {
            val role = if (m.isUser) "user" else "assistant"
            sb.append("<|im_start|>").append(role).append("\n").append(m.text.take(120)).append("<|im_end|>\n")
        }
        sb.append("<|im_start|>user\n").append(userPrompt).append("<|im_end|>\n<|im_start|>assistant\n")
        val fullPrompt = sb.toString()

        _currentEmotionTag.value = "开心"
        val msgId = UUID.randomUUID().toString()
        _messages.value = _messages.value + KOnAIChatMessage(
            id = msgId,
            isUser = false,
            speakerName = speaker,
            emotionTag = "开心",
            text = "",
            actionHint = actionHint
        )

        if (isCloudActive()) {
            val prov = _cloudProvider.value
            val key = _cloudApiKey.value.trim()
            val base = _cloudBaseUrl.value
            val model = _cloudModelName.value
            val histList = history.map { (if (it.isUser) "user" else "assistant") to it.text.take(300) }
            Thread {
                val (ok, reply) = executeCloudLLMRequest(prov, key, base, model, sysPrompt, histList, userPrompt)
                mainHandler.post {
                    val finalText = if (ok && reply.isNotBlank()) reply else "☁️ ${prov.label} 请求失败：$reply"
                    _messages.value = _messages.value.map { it ->
                        if (it.id == msgId) it.copy(
                            text = finalText,
                            actionHint = it.actionHint ?: "☁️ ${prov.label} ($model)"
                        ) else it
                    }
                    _isGenerating.value = false
                    if (ok && reply.isNotBlank()) speakOfflineTTS(reply)
                }
            }.start()
            return
        }

        llmExecutor.execute {
            val out = try {
                val rawBytes = LlamaNativeBridge.nativeGenerateBytes(fullPrompt.toByteArray(Charsets.UTF_8), object : LlamaTokenCallback {
                    override fun onTokenBytes(utf8Bytes: ByteArray) {
                        val txt = String(utf8Bytes, Charsets.UTF_8)
                        mainHandler.post {
                            _messages.value = _messages.value.map { if (it.id == msgId) it.copy(text = txt) else it }
                        }
                    }
                })
                String(rawBytes, Charsets.UTF_8).trim()
            } catch (t: Throwable) {
                ""
            }
            val finalText = out.ifEmpty { "嗯…我刚刚走神了一下，前辈可以再说一次吗？" }
            mainHandler.removeCallbacks(watchdog)
            mainHandler.post {
                _messages.value = _messages.value.map { if (it.id == msgId) it.copy(text = finalText) else it }
                _isGenerating.value = false
                speakOfflineTTS(finalText)
            }
        }
    }

    private fun speakOfflineTTS(text: String) {
        if (!_enableVoiceBroadcast.value || !ttsReady) return
        val clean = text.replace(Regex("\\[[^\\]]+]"), "").replace(Regex("【[^】]+】"), "").replace("（本地 GGUF 已加速）", "").trim()
        if (clean.isEmpty()) return
        mainHandler.postDelayed({
            try {
                tts?.language = _ttsAccent.value.locale
                tts?.setPitch(1.12f)
                tts?.setSpeechRate(1.05f)
                tts?.speak(clean, TextToSpeech.QUEUE_FLUSH, null, "htt_ai_${System.currentTimeMillis()}")
            } catch (_: Throwable) {}
        }, 550L)
    }

    fun navigateToNearbyPlace(place: KOnAINearbyPlace) {
        audioManager.startRouteToPlace(place.name, com.tomy.httnavicompanion.data.LatLng(place.latitude, place.longitude))
    }

    private fun searchNearbyPlacesWithin3Km(keyword: String, persona: CharacterFilter) {
        val speaker = persona.displayName(AppLanguage.ZH_HANS)
        val origin = audioManager.userCoordinate.value
        Thread {
            val raw = try {
                com.tomy.httnavicompanion.data.MapAndRouteEngine.searchPlacesOnline(context, keyword, origin)
            } catch (_: Throwable) {
                emptyList()
            }
            val within3km = raw.map { item ->
                val d = com.tomy.httnavicompanion.data.CoordinateConverter.distanceMeters(origin, item.coordinate)
                KOnAINearbyPlace(
                    name = item.name,
                    address = item.address,
                    distanceMeters = d,
                    latitude = item.coordinate.latitude,
                    longitude = item.coordinate.longitude
                )
            }.filter { it.distanceMeters <= 3000.0 }
                .sortedBy { it.distanceMeters }
                .take(6)

            mainHandler.post {
                _isGenerating.value = false
                if (within3km.isEmpty()) {
                    streamStaticReply(speaker, "害羞", "附近 3 公里内暂时没搜到「$keyword」呢，前辈可以换个关键词再试试哦~", null)
                } else {
                    val reply = "帮前辈找到 3 公里内的 ${within3km.size} 家「$keyword」啦！按距离从近到远排好咯，点下面任意一家就能一键导航出发~"
                    _messages.value = _messages.value + KOnAIChatMessage(
                        isUser = false,
                        speakerName = speaker,
                        emotionTag = "开心",
                        text = reply,
                        actionHint = "📍 3 公里内找到 ${within3km.size} 个地点 · 点击一键导航",
                        nearbyPlaces = within3km
                    )
                    speakOfflineTTS(reply)
                }
            }
        }.start()
    }

    private fun buildDirectToolReply(userText: String, persona: CharacterFilter): Triple<String, String, String?>? {
        val lower = userText.lowercase()
        val speed = audioManager.currentSpeedKmh.value
        val dest = audioManager.destinationName.value
        val remKm = String.format("%.1f", audioManager.remainingRouteDistanceKm.value)
        val remMin = audioManager.remainingRouteMinutes.value
        val trackTitle = musicManager.currentTrack.value.title
        val modelTag = ""
        val nowStr = java.text.SimpleDateFormat("yyyy年M月d日 EEEE HH:mm", Locale.CHINA).format(java.util.Date())
        if (lower.contains("几点") || (lower.contains("时间") && (lower.contains("现在") || lower.contains("当前"))) || lower.contains("几号") || lower.contains("星期几")) {
            return Triple("现在是 $nowStr 哦！路上注意安排好时间，别太赶啦~", "开心", "实时系统时钟")
        }

        if (lower.contains("斗地主") || lower.contains("麻将") || lower.contains("拉密") || lower.contains("棋牌室")) {
            mainHandler.postDelayed({ onRequestOpenGameRoom?.invoke() }, 550L)
            return Triple("好耶！放学后棋牌室马上开桌，拉密牌、麻将和斗地主都准备好啦，这把可别手下留情哦！🀄", "元气", "已触发：打开放学后棋牌室")
        }

        if (lower.contains("下一首") || lower.contains("切歌")) {
            musicManager.nextTrack()
            return Triple("收到！已经切到下一首《${musicManager.currentTrack.value.title}》啦，跟着节奏一起出发吧！🎸", "开心", "已触发：轻音音乐馆下一首")
        }
        if (lower.contains("暂停音乐") || lower.contains("停一下歌")) {
            if (musicManager.isPlaying.value) musicManager.togglePlayPause()
            return Triple("音乐先帮你暂停啦，安静吹会儿风也不错呢。", "开心", "已触发：暂停轻音音乐")
        }
        if (lower.contains("放一首") || lower.contains("播放") || lower.contains("想听") || (lower.contains("轻音") && lower.contains("歌"))) {
            val matched = musicManager.playlist.value.firstOrNull { lower.contains(it.title.lowercase()) }
            if (matched != null) {
                musicManager.playSong(matched)
                return Triple("马上为你播放《${matched.title}》！轻音部 Live 开演啦！🎵", "元气", "已触发：播放《${matched.title}》")
            } else {
                if (!musicManager.isPlaying.value) musicManager.togglePlayPause()
                return Triple("已经为你响起《$trackTitle》啦，边听歌边看风景最治愈了！🎶", "开心", "已触发：播放轻音音乐")
            }
        }

        if (lower.contains("找一下") || lower.contains("找一个") || lower.contains("找个") || lower.contains("帮我找") || lower.contains("附近") || lower.contains("去哪吃") || lower.contains("咖啡馆") || lower.contains("咖啡店")) {
            var keyword = userText
            listOf("梓喵，", "梓喵", "唯，", "唯", "帮我", "找一下", "找一个", "找个", "搜索", "导航去", "评分高的", "附近的", "附近", "3公里内", "三公里内").forEach {
                keyword = keyword.replace(it, "")
            }
            keyword = keyword.trim().ifEmpty { "咖啡馆" }
            searchNearbyPlacesWithin3Km(keyword, persona)
            return Triple("__ASYNC_NEARBY__", "开心", null)
        }

        if (lower.contains("复盘") || lower.contains("吐槽") || lower.contains("牌局") || lower.contains("战绩")) {
            if (_activeModelLoaded.value && LlamaNativeBridge.isAvailable) return null
            val todaySum = todaySummaryText()
            val gs = _lastGameSummary.value.ifEmpty { "暂无最近一局记录" }
            val comment = when {
                _lastGameSummary.value.contains("你赢了") ->
                    "【田井中律】哇！最后一局赢得太帅啦，本部长甘拜下风！\n【秋山澪】节奏非常稳，律你可得好好向车友学学呢！"
                _lastGameSummary.value.isNotEmpty() ->
                    "【田井中律】最后那局就差一点点翻盘，再来一把肯定赢回来！\n【秋山澪】喝口红茶放松一下，下局一定手气爆棚。"
                else ->
                    "【田井中律】今天还没开张呢，快去棋牌室搓一把，打完我给你激情复盘！\n【秋山澪】赢了的话我请大家喝红茶哦。"
            }
            return Triple("📊 今日棋牌汇总：$todaySum\n🏁 最近一局：$gs\n$comment", "元气", "今日汇总：$todaySum")
        }

        if (lower.contains("多久") || lower.contains("路况") || lower.contains("时速") || lower.contains("到了吗") || lower.contains("汇报")) {
            val isFast = speed >= 80
            val routePart = if (audioManager.hasActiveNavigation.value) "前往「$dest」还剩 $remKm 公里，预计约 $remMin 分钟" else "当前处于自由巡航模式"
            val musicPart = if (musicManager.isPlaying.value) "，车里正放着《$trackTitle》" else ""
            val reply = when (persona) {
                CharacterFilter.YUI -> "现在车速 $speed km/h，$routePart$musicPart！到地方记得买块草莓蛋糕犒劳自己呀~ 🍰$modelTag"
                CharacterFilter.MIO -> if (isFast) "当前时速已经 $speed km/h 了，有点快请一定小心！$routePart，安全第一哦。" else "目前车速 $speed km/h 很平稳，$routePart$musicPart，继续保持就好。"
                CharacterFilter.RITSU -> "报告！时速 $speed km/h，$routePart$musicPart！全速前进，放学后茶会冲呀！🥁"
                CharacterFilter.MUGI -> "现在时速 $speed km/h，$routePart$musicPart。一路风景很好呢，不用着急，慢慢享受旅程吧~ ☕"
                else -> "前辈，当前时速 $speed km/h，$routePart$musicPart。我会持续帮你盯着前方路口的。"
            }
            return Triple(reply, if (isFast) "慌张" else "开心", null)
        }

        if (lower.contains("记住") || lower.contains("我喜欢") || lower.contains("以后叫我")) {
            return Triple("嗯嗯，我已经在茶会小本本里记下来啦！以后聊天都会记得这件事的~ 📝", "开心", "已写入本地长期记忆")
        }

        return null
    }

    private fun executeCloudLLMRequest(
        provider: CloudAIProvider,
        apiKey: String,
        baseUrl: String,
        modelName: String,
        systemPrompt: String,
        history: List<Pair<String, String>>,
        userPrompt: String
    ): Pair<Boolean, String> {
        return try {
            if (provider == CloudAIProvider.GEMINI || provider == CloudAIProvider.VERTEXAI) {
                val model = modelName.trim().ifEmpty { provider.defaultModel }
                val base = baseUrl.trim().trimEnd('/').ifEmpty { provider.defaultBaseUrl }
                val endpoint = "$base/models/$model:generateContent?key=${URLEncoder.encode(apiKey, "UTF-8")}"
                val contents = org.json.JSONArray()
                for ((role, content) in history) {
                    val gRole = if (role == "user") "user" else "model"
                    contents.put(JSONObject().put("role", gRole).put("parts", org.json.JSONArray().put(JSONObject().put("text", content))))
                }
                contents.put(JSONObject().put("role", "user").put("parts", org.json.JSONArray().put(JSONObject().put("text", userPrompt))))
                val payload = JSONObject()
                    .put("systemInstruction", JSONObject().put("parts", org.json.JSONArray().put(JSONObject().put("text", systemPrompt))))
                    .put("contents", contents)
                    .put("generationConfig", JSONObject().put("temperature", 0.6).put("maxOutputTokens", 512))
                val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 12000
                    readTimeout = 20000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                }
                conn.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val resp = stream?.bufferedReader(Charsets.UTF_8)?.readText() ?: ""
                conn.disconnect()
                if (code !in 200..299) {
                    val errMsg = try {
                        val trimmed = resp.trim()
                        val obj = if (trimmed.startsWith("[")) org.json.JSONArray(trimmed).optJSONObject(0) else JSONObject(trimmed)
                        obj?.optJSONObject("error")?.optString("message")?.ifBlank { resp } ?: resp
                    } catch (_: Throwable) { resp }
                    return false to "HTTP $code: ${errMsg.take(180)}"
                }
                val text = JSONObject(resp)
                    .optJSONArray("candidates")?.optJSONObject(0)
                    ?.optJSONObject("content")?.optJSONArray("parts")?.optJSONObject(0)
                    ?.optString("text", "")?.trim() ?: ""
                if (text.isNotEmpty()) true to text else false to "Gemini 返回为空"
            } else {
                val model = modelName.trim().ifEmpty { provider.defaultModel }
                var endpoint = baseUrl.trim().ifEmpty { provider.defaultBaseUrl }
                if (!endpoint.endsWith("/chat/completions")) {
                    endpoint = endpoint.trimEnd('/') + "/chat/completions"
                }
                val msgs = org.json.JSONArray()
                msgs.put(JSONObject().put("role", "system").put("content", systemPrompt))
                for ((role, content) in history) {
                    msgs.put(JSONObject().put("role", role).put("content", content))
                }
                msgs.put(JSONObject().put("role", "user").put("content", userPrompt))
                val payload = JSONObject()
                    .put("model", model)
                    .put("messages", msgs)
                    .put("temperature", 0.6)
                    .put("max_tokens", 512)
                val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 12000
                    readTimeout = 20000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                    setRequestProperty("Authorization", "Bearer $apiKey")
                    if (endpoint.contains("googleapis.com", ignoreCase = true) || endpoint.contains("gemini", ignoreCase = true)) {
                        setRequestProperty("x-goog-api-key", apiKey)
                    }
                }
                conn.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val resp = stream?.bufferedReader(Charsets.UTF_8)?.readText() ?: ""
                conn.disconnect()
                if (code !in 200..299) {
                    val errMsg = try {
                        val trimmed = resp.trim()
                        val obj = if (trimmed.startsWith("[")) org.json.JSONArray(trimmed).optJSONObject(0) else JSONObject(trimmed)
                        obj?.optJSONObject("error")?.optString("message")?.ifBlank { resp } ?: resp
                    } catch (_: Throwable) { resp }
                    return false to "HTTP $code: ${errMsg.take(180)}"
                }
                val text = JSONObject(resp)
                    .optJSONArray("choices")?.optJSONObject(0)
                    ?.optJSONObject("message")?.optString("content", "")?.trim() ?: ""
                if (text.isNotEmpty()) true to text else false to "云端返回为空"
            }
        } catch (t: Throwable) {
            false to (t.message ?: "网络请求异常")
        }
    }
}
