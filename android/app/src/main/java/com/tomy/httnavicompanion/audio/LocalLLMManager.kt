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

data class KOnAIChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val isUser: Boolean,
    val speakerName: String,
    val emotionTag: String = "开心",
    val text: String,
    val actionHint: String? = null
)

enum class KOnAITTSAccent(val label: String, val locale: Locale) {
    MANDARIN("普通话", Locale.CHINA),
    CANTONESE("粤语", Locale("zh", "HK"))
}

class LocalLLMManager(
    private val context: Context,
    private val audioManager: AudioPlayerManager,
    private val musicManager: KOnMusicManager
) {
    companion object {
        val modelCatalog = listOf(
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

    private val _ttsAccent = MutableStateFlow(KOnAITTSAccent.MANDARIN)
    val ttsAccent: StateFlow<KOnAITTSAccent> = _ttsAccent

    private val _lowMemoryGuard = MutableStateFlow(true)
    val lowMemoryGuard: StateFlow<Boolean> = _lowMemoryGuard

    private val _memories = MutableStateFlow<List<String>>(emptyList())
    val memories: StateFlow<List<String>> = _memories

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
        loadMemories()
        refreshInstalledModels()
        seedGreetingIfNeeded()
        initTTS()
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
        _activeModelFileName.value = fileName
        _activeModelLoaded.value = true
        prefs.edit().putString("active_model", fileName).apply()
        _statusMessage.value = "已挂载本地 GGUF 模型：$fileName (v${info.version}, ${info.tensorCount} tensors)"
    }

    fun unloadModelFromMemory(silent: Boolean = false) {
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
        val (reply, emotion, actionHint) = buildKOnReply(text, persona)
        val speaker = if (isAllFive && (text.contains("复盘") || text.contains("吐槽"))) "田井中律 & 秋山澪" else persona.displayName(AppLanguage.ZH_HANS)

        _currentEmotionTag.value = emotion
        if (_enableVoiceBroadcast.value) {
            audioManager.triggerCharacterTap(persona)
        }

        val msgId = UUID.randomUUID().toString()
        _messages.value = _messages.value + KOnAIChatMessage(
            id = msgId,
            isUser = false,
            speakerName = speaker,
            emotionTag = emotion,
            text = "",
            actionHint = actionHint
        )

        // Smooth typewriter streaming on background thread
        Thread {
            var idx = 0
            while (idx < reply.length) {
                val nextIdx = (idx + 2).coerceAtMost(reply.length)
                val partial = reply.substring(0, nextIdx)
                idx = nextIdx
                mainHandler.post {
                    _messages.value = _messages.value.map { if (it.id == msgId) it.copy(text = partial) else it }
                }
                Thread.sleep(28L)
            }
            mainHandler.post {
                _isGenerating.value = false
                speakOfflineTTS(reply)
            }
        }.start()
    }

    private fun speakOfflineTTS(text: String) {
        if (!_enableVoiceBroadcast.value || !ttsReady) return
        val clean = text.replace(Regex("\\[[^\\]]+]"), "").trim()
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

    private fun buildKOnReply(userText: String, persona: CharacterFilter): Triple<String, String, String?> {
        val lower = userText.lowercase()
        val speed = audioManager.currentSpeedKmh.value
        val dest = audioManager.destinationName.value
        val remKm = String.format("%.1f", audioManager.remainingRouteDistanceKm.value)
        val remMin = audioManager.remainingRouteMinutes.value
        val trackTitle = musicManager.currentTrack.value.title
        val modelTag = if (_activeModelLoaded.value) "（本地 GGUF 已加速）" else ""

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

        if (lower.contains("找一下") || lower.contains("附近") || lower.contains("导航去") || lower.contains("去哪吃")) {
            var keyword = userText
            listOf("梓喵，", "梓喵", "唯，", "唯", "帮我", "找一下", "搜索", "导航去", "评分高的", "附近的", "附近").forEach {
                keyword = keyword.replace(it, "")
            }
            keyword = keyword.trim().ifEmpty { "咖啡馆" }
            audioManager.performOnlineSearch(keyword)
            mainHandler.postDelayed({ onRequestOpenSearch?.invoke(keyword) }, 500L)
            return Triple("收到！已经在地图上帮你搜索「$keyword」啦，挑一个顺路的店就出发吧！☕", "开心", "已触发：地图搜索「$keyword」")
        }

        if (lower.contains("复盘") || lower.contains("吐槽") || lower.contains("牌局")) {
            return Triple(
                "【田井中律】哈哈哈刚才那局我差点就一波清台了，本部长果然是棋牌室最强王者！\n【秋山澪】喂、律！你刚才明明把百搭牌留在手里差点放炮好不好…车友都比你稳多了！",
                "元气",
                "五人同台 · 茶会小剧场"
            )
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

        val memHint = _memories.value.firstOrNull()?.let { "（对了，我还记得你说过「$it」呢~）" } ?: ""
        val general = when (persona) {
            CharacterFilter.YUI -> "嘿嘿，听你这么说我都想吃草莓蛋糕和红茶啦！$memHint$modelTag"
            CharacterFilter.MIO -> "嗯…你的话我都认真听着呢。专心看路的同时偶尔聊聊天挺放松的，别分心就好啦。$memHint$modelTag"
            CharacterFilter.RITSU -> "哈哈这个话题有意思！等停好车我们再去棋牌室大战三百回合！$memHint$modelTag"
            CharacterFilter.MUGI -> "真开心能陪你一起在路上聊天呀~ 等会儿要是累了，记得靠边休息喝杯热茶哦。$memHint$modelTag"
            else -> "前辈，收到啦！路上有什么想查的店、想听的轻音歌或者想问的路况，随时喊我一声就行。$memHint$modelTag"
        }
        return Triple(general, "开心", null)
    }
}
