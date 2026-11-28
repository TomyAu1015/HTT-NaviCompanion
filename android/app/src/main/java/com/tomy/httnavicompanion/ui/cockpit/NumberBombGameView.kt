package com.tomy.httnavicompanion.ui.cockpit

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import com.tomy.httnavicompanion.audio.AppLanguage
import com.tomy.httnavicompanion.audio.AudioPlayerManager
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import java.util.Locale
import java.util.UUID
import kotlin.random.Random

private object NumberBombParser {
    private val digits = mapOf('零' to 0, '〇' to 0, '一' to 1, '二' to 2, '两' to 2, '三' to 3, '四' to 4, '五' to 5, '六' to 6, '七' to 7, '八' to 8, '九' to 9)
    private val units = mapOf('十' to 10, '百' to 100, '千' to 1000)
    private val numRegex = Regex("""\d+|[零〇一二两三四五六七八九十百千]+""")

    fun parseChineseNumber(s: String): Int? {
        var total = 0
        var cur = 0
        var hasUnit = false
        for (ch in s) {
            val d = digits[ch]
            val u = units[ch]
            when {
                d != null -> cur = d
                u != null -> {
                    hasUnit = true
                    if (cur == 0 && u == 10 && total == 0) cur = 1
                    total += cur * u
                    cur = 0
                }
                else -> return null
            }
        }
        if (!hasUnit && s.length > 1) {
            var direct = 0
            for (ch in s) {
                val d = digits[ch] ?: return null
                direct = direct * 10 + d
            }
            return direct
        }
        return total + cur
    }

    fun extractAllNumbers(text: String): List<Int> {
        val out = mutableListOf<Int>()
        for (m in numRegex.findAll(text)) {
            val tok = m.value
            val v = tok.toIntOrNull() ?: parseChineseNumber(tok)
            if (v != null) out.add(v)
        }
        return out
    }

    fun extractNumber(text: String): Int? = extractAllNumbers(text).lastOrNull()

    fun extractPlayerNames(text: String): List<String> {
        var cleaned = text
        val strips = listOf("玩家有", "参加者有", "人数有", "添加", "加入", "玩家", "开始游戏", "开始", "开局", "数字炸弹", "请", "把", "一下", "吧", "哦", "呢", "呀", "啊")
        for (w in strips) cleaned = cleaned.replace(w, " ")
        val parts = cleaned.split(Regex("""[，,、。.;；!！?？\s]+"""))
        val out = mutableListOf<String>()
        for (p in parts) {
            var cur = p.trim()
            for (c in listOf("还有", "以及", "和", "跟", "与")) cur = cur.replace(c, "|")
            for (sub in cur.split("|")) {
                val s = sub.trim()
                if (s.length in 1..6 && extractNumber(s) == null) out.add(s)
            }
        }
        return out
    }
}

@Composable
fun KOnNumberBombContent() {
    val context = LocalContext.current
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    var phase by remember { mutableStateOf(0) } // 0=setup, 1=playing, 2=exploded
    var minBound by remember { mutableStateOf(1) }
    var maxBound by remember { mutableStateOf(100) }
    var currentLow by remember { mutableStateOf(1) }
    var currentHigh by remember { mutableStateOf(100) }
    var secretBomb by remember { mutableStateOf(50) }
    val players = remember { mutableStateListOf<String>() }
    var turnIdx by remember { mutableStateOf(0) }
    var explodedPlayer by remember { mutableStateOf("") }
    var statusLine by remember { mutableStateOf("点击下方开启全程语音，说出玩家名字（如：大强、冰冰）和「开始」即可免手玩！") }
    var lastHeard by remember { mutableStateOf("") }
    val history = remember { mutableStateListOf<String>() }
    var isHandsFree by remember { mutableStateOf(false) }
    var isListening by remember { mutableStateOf(false) }
    var isSpeaking by remember { mutableStateOf(false) }
    var manualInput by remember { mutableStateOf("") }

    var ttsRef by remember { mutableStateOf<TextToSpeech?>(null) }
    var srRef by remember { mutableStateOf<SpeechRecognizer?>(null) }
    val activeState = rememberUpdatedState(isHandsFree)

    fun currentWho(): String = if (players.isEmpty()) "" else players[turnIdx % players.size]

    fun stopListen() {
        try { srRef?.cancel() } catch (_: Exception) {}
        isListening = false
    }

    lateinit var startListen: () -> Unit
    lateinit var speakAndListen: (String) -> Unit

    fun startNewRound(announce: Boolean = true) {
        currentLow = minBound
        currentHigh = maxBound
        secretBomb = Random.nextInt(minBound, maxBound + 1)
        explodedPlayer = ""
        history.clear()
        if (players.isNotEmpty()) turnIdx %= players.size
        phase = 1
        val msg = "数字炸弹开始！范围 $currentLow 到 $currentHigh，请${currentWho()}报数！"
        statusLine = msg
        if (announce) {
            isHandsFree = true
            speakAndListen(msg)
        }
    }

    fun handleGuess(guess: Int) {
        val who = currentWho()
        val prefix = if (who.isEmpty()) "" else "[$who] "
        if (guess < currentLow || guess > currentHigh) {
            speakAndListen("$guess 不在 $currentLow 到 $currentHigh 范围内哦，请${who}重新报数！")
            return
        }
        if (guess == secretBomb) {
            phase = 2
            explodedPlayer = who.ifEmpty { "当前玩家" }
            history.add(0, "💥 ${prefix}报 $guess — 踩中炸弹！")
            speakAndListen("砰！炸弹就是 $secretBomb！$explodedPlayer 中招啦！说再来一局就可以继续玩！")
            return
        }
        if (guess < secretBomb) currentLow = guess + 1 else currentHigh = guess - 1
        history.add(0, "✅ ${prefix}报 $guess → 新范围 $currentLow-$currentHigh")
        if (players.isNotEmpty()) turnIdx = (turnIdx + 1) % players.size
        val nxt = currentWho()
        val nxtAsk = if (nxt.isEmpty()) "" else "，请 $nxt 报数"
        speakAndListen("$currentLow 到 $currentHigh$nxtAsk！")
    }

    fun handleSpoken(raw: String) {
        val txt = raw.trim()
        if (txt.isEmpty()) return
        lastHeard = txt
        if (txt.contains("停止") || txt.contains("退出")) {
            isHandsFree = false
            stopListen()
            ttsRef?.stop()
            statusLine = "已暂停语音主持"
            return
        }
        if (txt.contains("再来一局") || txt.contains("重新开始") || txt.contains("下一局")) {
            if (players.isNotEmpty()) turnIdx = (turnIdx + 1) % players.size
            startNewRound(true)
            return
        }
        when (phase) {
            0 -> {
                if (txt.contains("清空") || txt.contains("重置名单")) {
                    players.clear()
                    speakAndListen("已清空玩家名单，请重新说出玩家名字或说开始！")
                    return
                }
                val nums = NumberBombParser.extractAllNumbers(txt)
                if (nums.size >= 2 && (txt.contains("到") || txt.contains("至") || txt.contains("范围"))) {
                    val lo = minOf(nums[0], nums[1]).coerceAtLeast(1)
                    val hi = maxOf(nums[0], nums[1]).coerceAtLeast(lo + 2)
                    minBound = lo; maxBound = hi; currentLow = lo; currentHigh = hi
                    speakAndListen("范围已设为 $minBound 到 $maxBound！请说玩家名字或说开始！")
                    return
                }
                if (txt.contains("开始") || txt.contains("开局")) {
                    NumberBombParser.extractPlayerNames(txt).forEach { if (!players.contains(it)) players.add(it) }
                    startNewRound(true)
                    return
                }
                val names = NumberBombParser.extractPlayerNames(txt)
                if (names.isNotEmpty()) {
                    val added = mutableListOf<String>()
                    names.forEach { if (!players.contains(it)) { players.add(it); added.add(it) } }
                    if (added.isNotEmpty()) {
                        speakAndListen("已加入 ${added.joinToString("、")}，当前共 ${players.size} 人！继续报人名或说开始！")
                    } else {
                        speakAndListen("这些名字已经在名单里啦，说开始就可以玩！")
                    }
                } else {
                    if (activeState.value) mainHandler.postDelayed({ startListen() }, 350)
                }
            }
            1 -> {
                val g = NumberBombParser.extractNumber(txt)
                if (g != null) handleGuess(g)
                else if (activeState.value) mainHandler.postDelayed({ startListen() }, 350)
            }
            2 -> {
                if (txt.contains("开始") || txt.contains("再来") || txt.contains("继续")) {
                    if (players.isNotEmpty()) turnIdx = (turnIdx + 1) % players.size
                    startNewRound(true)
                } else if (activeState.value) {
                    mainHandler.postDelayed({ startListen() }, 400)
                }
            }
        }
    }

    startListen = {
        if (activeState.value && !isSpeaking) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                statusLine = "⚠️ 请先授予麦克风权限"
                isHandsFree = false
            } else {
                mainHandler.post {
                    try {
                        if (srRef == null) {
                            srRef = SpeechRecognizer.createSpeechRecognizer(context).apply {
                                setRecognitionListener(object : RecognitionListener {
                                    override fun onReadyForSpeech(params: Bundle?) { isListening = true }
                                    override fun onBeginningOfSpeech() {}
                                    override fun onRmsChanged(rmsdB: Float) {}
                                    override fun onBufferReceived(buffer: ByteArray?) {}
                                    override fun onEndOfSpeech() { isListening = false }
                                    override fun onError(error: Int) {
                                        isListening = false
                                        if (activeState.value && !isSpeaking) {
                                            mainHandler.postDelayed({ startListen() }, 450)
                                        }
                                    }
                                    override fun onResults(results: Bundle?) {
                                        isListening = false
                                        val txt = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                                        if (txt.isNotBlank()) handleSpoken(txt)
                                        else if (activeState.value && !isSpeaking) mainHandler.postDelayed({ startListen() }, 350)
                                    }
                                    override fun onPartialResults(partialResults: Bundle?) {
                                        val p = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                                        if (p.isNotBlank()) lastHeard = p
                                    }
                                    override fun onEvent(eventType: Int, params: Bundle?) {}
                                })
                            }
                        }
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
                            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                        }
                        srRef?.startListening(intent)
                    } catch (e: Exception) {
                        statusLine = "语音监听启动失败: ${e.message}"
                    }
                }
            }
        }
    }

    speakAndListen = { text ->
        stopListen()
        statusLine = text
        isSpeaking = true
        val tts = ttsRef
        if (tts != null) {
            tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, UUID.randomUUID().toString())
        } else {
            isSpeaking = false
            if (activeState.value) mainHandler.postDelayed({ startListen() }, 300)
        }
    }

    DisposableEffect(Unit) {
        val tts = TextToSpeech(context) { st ->
            if (st == TextToSpeech.SUCCESS) {
                ttsRef?.language = Locale.SIMPLIFIED_CHINESE
                ttsRef?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) {
                        mainHandler.post {
                            isSpeaking = false
                            if (activeState.value) mainHandler.postDelayed({ startListen() }, 250)
                        }
                    }
                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        mainHandler.post {
                            isSpeaking = false
                            if (activeState.value) mainHandler.postDelayed({ startListen() }, 350)
                        }
                    }
                })
            }
        }
        ttsRef = tts
        onDispose {
            isHandsFree = false
            stopListen()
            try { srRef?.destroy() } catch (_: Exception) {}
            try { tts.stop(); tts.shutdown() } catch (_: Exception) {}
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // 1. 区间/爆炸大卡片
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(if (phase == 2) Color(0xFFB71C1C) else Color.Black.copy(alpha = 0.35f))
                .border(1.5.dp, Color(0xFFFFD54F).copy(alpha = 0.7f), RoundedCornerShape(16.dp))
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                if (phase == 2) "💥 BOOM! 踩中数字炸弹！" else if (phase == 1) "💣 当前安全区间（说数字即可）" else "🎙️ 放课后派对 · 语音数字炸弹",
                color = Color(0xFFFFD54F), fontSize = 13.sp, fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(6.dp))
            if (phase == 2) {
                Text("$secretBomb", color = Color.White, fontSize = 52.sp, fontWeight = FontWeight.Black)
                Text("中招玩家：$explodedPlayer", color = Color(0xFFFFEB3B), fontSize = 16.sp, fontWeight = FontWeight.Bold)
            } else {
                Text("$currentLow — $currentHigh", color = Color.White, fontSize = 42.sp, fontWeight = FontWeight.Black)
            }
            Spacer(Modifier.height(6.dp))
            Text(statusLine, color = Color.White.copy(alpha = 0.92f), fontSize = 13.sp, textAlign = TextAlign.Center)
            if (lastHeard.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text("👂 刚刚听到：「$lastHeard」", color = Color(0xFF81C784), fontSize = 12.sp)
            }
        }

        // 2. 全程语音主控按钮
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = {
                    if (isHandsFree) {
                        isHandsFree = false
                        stopListen()
                        ttsRef?.stop()
                        isSpeaking = false
                        statusLine = "已暂停语音主持，随时可点击继续"
                    } else {
                        isHandsFree = true
                        if (phase == 0) {
                            val tip = if (players.isEmpty()) "数字炸弹已就绪！范围 $minBound 到 $maxBound。请直接说出玩家名字，比如大强、冰冰，或者直接说开始！"
                            else "数字炸弹已就绪！玩家有 ${players.joinToString("、")}，说开始就可以玩啦！"
                            speakAndListen(tip)
                        } else if (phase == 1) {
                            speakAndListen("继续游戏！范围 $currentLow 到 $currentHigh，请${currentWho()}报数！")
                        } else {
                            speakAndListen("说再来一局就可以重新开始哦！")
                        }
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = if (isHandsFree) Color(0xFFD32F2F) else Color(0xFF2E7D32)),
                modifier = Modifier.weight(1f).height(46.dp),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text(
                    if (isHandsFree) (if (isListening) "🎙️ 持续监听中（点此停止）" else "🔊 主持人播报中...") else "🎙️ 启动全程免手语音主持",
                    fontSize = 13.sp, fontWeight = FontWeight.Black, color = Color.White
                )
            }
            if (phase != 1) {
                Button(
                    onClick = { startNewRound(true) },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFB8C00)),
                    modifier = Modifier.height(46.dp),
                    shape = RoundedCornerShape(12.dp)
                ) { Text("▶ 开局", fontWeight = FontWeight.Black, color = Color.White) }
            }
        }

        // 3. 范围快捷选择
        Column(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.Black.copy(alpha = 0.28f)).padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text("1. 设定数字范围（默认 1-100，也可语音说“1到200”）", color = Color(0xFFFFD54F), fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(1 to 50, 1 to 100, 1 to 200, 1 to 500).forEach { (lo, hi) ->
                    Box(
                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp))
                            .background(if (maxBound == hi) Color(0xFFFB8C00) else Color.White.copy(alpha = 0.14f))
                            .clickable { minBound = lo; maxBound = hi; if (phase == 0) { currentLow = lo; currentHigh = hi } }
                            .padding(vertical = 7.dp),
                        contentAlignment = Alignment.Center
                    ) { Text("$lo-$hi", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                }
            }
        }

        // 4. 玩家名单
        Column(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.Black.copy(alpha = 0.28f)).padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("2. 参与玩家（直接说「大强、冰冰」自动识别）", color = Color(0xFFFFD54F), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                if (players.isNotEmpty()) {
                    Text("清空", color = Color(0xFFFF5252), fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { players.clear() })
                }
            }
            if (players.isEmpty()) {
                Text("暂无指定名单（可直接语音报人名，或不填名单直接轮流报数）", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
            } else {
                Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    players.forEachIndexed { idx, nm ->
                        val active = (phase == 1 && idx == turnIdx % players.size)
                        Box(
                            modifier = Modifier.clip(RoundedCornerShape(999.dp))
                                .background(if (active) Color(0xFFFB8C00) else Color.White.copy(alpha = 0.18f))
                                .clickable { players.removeAt(idx); if (turnIdx >= players.size) turnIdx = 0 }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) { Text(if (active) "👉 $nm ×" else "$nm ×", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                    }
                }
            }
        }

        // 5. 嘈杂环境兜底输入
        if (phase == 1) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = manualInput,
                    onValueChange = { manualInput = it.filter { ch -> ch.isDigit() } },
                    placeholder = { Text("嘈杂环境可手输数字", fontSize = 12.sp) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                Button(onClick = {
                    NumberBombParser.extractNumber(manualInput)?.let { handleGuess(it) }
                    manualInput = ""
                }) { Text("报数") }
            }
        }

        if (history.isNotEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.25f)).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text("本局记录", color = Color(0xFFFFD54F), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                history.take(8).forEach { Text(it, color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp) }
            }
        }
    }
}


@Composable
fun KOnPartySheetDialog(manager: AudioPlayerManager, onDismiss: () -> Unit) {
    val lang by manager.language.collectAsState()
    fun tr(s: String, t: String, e: String) = when (lang) {
        AppLanguage.ZH_HANS -> s
        AppLanguage.ZH_HANT -> t
        AppLanguage.EN -> e
    }
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.88f),
            shape = RoundedCornerShape(18.dp),
            color = Color(0xFF1A102B)
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF281642))
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = tr("🎉 放课后派对", "🎉 放課後派對", "🎉 Ho-kago Party"),
                        color = Color(0xFFFAD048),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.ExtraBold
                    )
                    TextButton(onClick = onDismiss) {
                        Text(tr("关闭", "關閉", "Close"), color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    KOnNumberBombContent()
                }
            }
        }
    }
}
