package com.tomy.httnavicompanion.ui.cockpit

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import android.Manifest
import android.app.Activity
import android.speech.RecognizerIntent
import android.content.pm.PackageManager
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Stop
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.tomy.httnavicompanion.audio.VoiceInputLanguage
import com.tomy.httnavicompanion.audio.VoiceInputManager
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.AppLanguage
import com.tomy.httnavicompanion.audio.CloudAIProvider
import com.tomy.httnavicompanion.audio.LocalLLMManager

private val AiCrimson = Color(0xFFA61E2E)
private val AiGold = Color(0xFFE0B861)
private val AiCream = Color(0xFFFAF2E0)
private val AiDarkBg = Color(0xFF141620)
private val AiCardBg = Color(0xFF1E2230)

@Composable
fun LocalAIChatSheetDialog(
    onDismiss: () -> Unit,
    onOpenGameRoom: () -> Unit,
    onOpenSearch: () -> Unit
) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val llm = app.localLLMManager

    val messages by llm.messages.collectAsState()
    val isGenerating by llm.isGenerating.collectAsState()
    val installedModels by llm.installedModels.collectAsState()
    val activeModel by llm.activeModelFileName.collectAsState()
    val activeLoaded by llm.activeModelLoaded.collectAsState()
    val downloadingId by llm.downloadingModelId.collectAsState()
    val downloadProgress by llm.downloadProgress.collectAsState()
    val statusMsg by llm.statusMessage.collectAsState()
    val emotionTag by llm.currentEmotionTag.collectAsState()
    val voiceOn by llm.enableVoiceBroadcast.collectAsState()
    val webOn by llm.enableWebSearch.collectAsState()
    val accent by llm.ttsAccent.collectAsState()
    val lowMemGuard by llm.lowMemoryGuard.collectAsState()
    val cloudProvider by llm.cloudProvider.collectAsState()
    val cloudApiKey by llm.cloudApiKey.collectAsState()
    val cloudBaseUrl by llm.cloudBaseUrl.collectAsState()
    val cloudModelName by llm.cloudModelName.collectAsState()
    val cloudTestStatus by llm.cloudTestStatus.collectAsState()
    var keyDraft by remember(cloudApiKey) { mutableStateOf(cloudApiKey) }
    var urlDraft by remember(cloudBaseUrl) { mutableStateOf(cloudBaseUrl) }
    var modelDraft by remember(cloudModelName) { mutableStateOf(cloudModelName) }
    val memories by llm.memories.collectAsState()
    val speedKmh by manager.currentSpeedKmh.collectAsState()
    val selectedChar by manager.selectedCharacter.collectAsState()

    var selectedTab by remember { mutableIntStateOf(0) }
    var inputText by remember { mutableStateOf("") }
    val ctx = LocalContext.current
    val voiceMgr = remember(ctx) { VoiceInputManager(ctx) }
    var voiceBasePrefix by remember { mutableStateOf("") }
    val speechOverlayLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { res ->
        if (res.resultCode == Activity.RESULT_OK) {
            val best = res.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty()
            if (best.isNotBlank()) {
                inputText = if (voiceBasePrefix.isEmpty()) best else "$voiceBasePrefix $best"
            }
        }
    }
    val isVoiceRecording by voiceMgr.isRecording.collectAsState()
    val voiceStatus by voiceMgr.statusMessage.collectAsState()
    val voiceLang by voiceMgr.selectedLanguage.collectAsState()
    var showLangMenu by remember { mutableStateOf(false) }

    val startVoiceNow: () -> Unit = {
        voiceBasePrefix = inputText.trim()
        voiceMgr.startRecording(
            onUpdate = { partial ->
                inputText = if (voiceBasePrefix.isEmpty()) partial else "$voiceBasePrefix $partial"
            },
            onFallbackToDialog = { intent ->
                try { speechOverlayLauncher.launch(intent) } catch (_: Exception) {}
            }
        )
    }
    val micPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startVoiceNow()
    }
    DisposableEffect(Unit) {
        onDispose { voiceMgr.stopRecording() }
    }
    val listState = rememberLazyListState()
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val hideKb = { focusManager.clearFocus(); keyboardController?.hide() }

    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            llm.importLocalGGUF(uri)
        }
    }

    LaunchedEffect(Unit) {
        llm.onRequestOpenGameRoom = {
            onDismiss()
            onOpenGameRoom()
        }
        llm.onRequestOpenSearch = {
            onDismiss()
            onOpenSearch()
        }
        if (activeModel.isNotEmpty() && !activeLoaded) {
            llm.loadModelIntoMemory(activeModel)
        }
    }

    LaunchedEffect(activeModel, activeLoaded) {
        if (activeModel.isNotEmpty() && !activeLoaded) {
            llm.autoMountIfNeeded()
        }
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.90f)
                .clip(RoundedCornerShape(18.dp))
                .border(2.dp, AiGold, RoundedCornerShape(18.dp)),
            color = AiDarkBg
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(12.dp)) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("✨ 放课后茶会 · AI 副驾", color = AiCream, fontSize = 15.sp, fontWeight = FontWeight.Black)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        IconButton(onClick = { llm.toggleVoiceBroadcast() }, modifier = Modifier.size(32.dp)) {
                            Icon(
                                if (voiceOn) Icons.Default.VolumeUp else Icons.Default.VolumeOff,
                                contentDescription = null,
                                tint = if (voiceOn) AiGold else Color.Gray
                            )
                        }
                        IconButton(onClick = onDismiss, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                        }
                    }
                }

                // Tab Switcher
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("🍵 茶会副驾对话", "⚙️ 本地模型与记忆").forEachIndexed { idx, title ->
                        val sel = selectedTab == idx
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(10.dp))
                                .background(if (sel) AiCrimson else AiCardBg)
                                .border(1.dp, if (sel) AiGold else Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                                .clickable { hideKb(); selectedTab = idx }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(title, color = if (sel) Color.White else AiCream.copy(alpha = 0.8f), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

                if (selectedTab == 0) {
                    // Live Context Strip
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(AiCardBg)
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        val engineLabel = if (cloudProvider != CloudAIProvider.LOCAL && cloudApiKey.isNotBlank()) "☁️ ${cloudProvider.label}" else "📱 本地"
                        Text(
                            "[${selectedChar.displayName(AppLanguage.ZH_HANS)} · $engineLabel]",
                            color = AiGold,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color.White.copy(alpha = 0.08f))
                                .clickable {
                                    if (llm.hasSavedCloudKey()) llm.toggleCloudLocalMode() else selectedTab = 1
                                }
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("$speedKmh km/h", color = Color(0xFF4CAF50), fontSize = 11.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (webOn) Color(0xFF1E5AA8) else Color.White.copy(alpha = 0.12f))
                                    .clickable { llm.toggleWebSearch() }
                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                            ) {
                                Text(if (webOn) "🌐联网:开" else "🌐联网:关", color = AiCream, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(Color.White.copy(alpha = 0.12f))
                                    .clickable { llm.toggleAccent() }
                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                            ) {
                                Text("播报:${accent.label}", color = AiCream, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Quick Command Chips
                    Row(
                        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        listOf(
                            "🚗 路况汇报" to "汇报一下当前路况和还有多久到",
                            "🍵 茶会复盘" to "茶会复盘！吐槽一下刚才的牌局",
                            "🎸 切一首轻音" to "切歌，放下一首轻音歌",
                            "☕ 找附近咖啡馆" to "帮我找一下附近的咖啡馆",
                            "🀄 开棋牌室" to "我想打拉密牌，打开棋牌室"
                        ).forEach { (label, prompt) ->
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(AiCardBg)
                                    .border(1.dp, AiGold.copy(alpha = 0.45f), RoundedCornerShape(14.dp))
                                    .clickable(enabled = !isGenerating) { hideKb(); llm.sendUserMessage(prompt) }
                                    .padding(horizontal = 10.dp, vertical = 5.dp)
                            ) {
                                Text(label, color = AiCream, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Chat Messages
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.weight(1f).fillMaxWidth().pointerInput(Unit) { detectTapGestures(onTap = { hideKb() }) },
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(messages, key = { it.id }) { msg ->
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalAlignment = if (msg.isUser) Alignment.End else Alignment.Start
                            ) {
                                if (!msg.isUser) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Text(msg.speakerName, color = AiGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                        if (msg.emotionTag.isNotEmpty()) {
                                            Text(
                                                "[${msg.emotionTag}]",
                                                color = Color.White,
                                                fontSize = 9.sp,
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(4.dp))
                                                    .background(AiCrimson.copy(alpha = 0.65f))
                                                    .padding(horizontal = 4.dp, vertical = 1.dp)
                                            )
                                        }
                                    }
                                    Spacer(Modifier.height(2.dp))
                                }
                                Box(
                                    modifier = Modifier
                                        .widthIn(max = 285.dp)
                                        .clip(RoundedCornerShape(13.dp))
                                        .background(if (msg.isUser) AiCrimson else AiCardBg)
                                        .padding(horizontal = 11.dp, vertical = 8.dp)
                                ) {
                                    Text(msg.text.ifEmpty { "..." }, color = if (msg.isUser) Color.White else AiCream, fontSize = 13.sp)
                                }
                                if (msg.nearbyPlaces.isNotEmpty()) {
                                    Spacer(Modifier.height(6.dp))
                                    Column(
                                        modifier = Modifier.widthIn(max = 295.dp),
                                        verticalArrangement = Arrangement.spacedBy(5.dp)
                                    ) {
                                        msg.nearbyPlaces.forEachIndexed { idx, place ->
                                            val distLabel = if (place.distanceMeters < 1000.0) "${place.distanceMeters.toInt()}m" else String.format("%.1fkm", place.distanceMeters / 1000.0)
                                            Row(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .clip(RoundedCornerShape(10.dp))
                                                    .background(Color(0xFF1A2232))
                                                    .border(1.dp, AiGold.copy(alpha = 0.45f), RoundedCornerShape(10.dp))
                                                    .padding(horizontal = 9.dp, vertical = 7.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                                            ) {
                                                Column(modifier = Modifier.weight(1f)) {
                                                    Text("${idx + 1}. ${place.name}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                    Text("距你 $distLabel" + if (place.address.isNotBlank()) " · ${place.address}" else "", color = Color.LightGray, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                }
                                                Box(
                                                    modifier = Modifier
                                                        .clip(RoundedCornerShape(7.dp))
                                                        .background(Color(0xFF1565C0))
                                                        .clickable {
                                                            llm.navigateToNearbyPlace(place)
                                                            onDismiss()
                                                        }
                                                        .padding(horizontal = 9.dp, vertical = 5.dp)
                                                ) {
                                                    Text("一键导航", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                                }
                                            }
                                        }
                                    }
                                }
                                msg.actionHint?.let { hint ->
                                    Text("✨ $hint", color = Color(0xFF4CAF50), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Voice Status Banner
                    if (isVoiceRecording || voiceStatus.isNotBlank()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White.copy(alpha = 0.08f))
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                if (isVoiceRecording) "🎙️ 正在聆听（${voiceLang.shortLabel} · 软件内直录）..." else voiceStatus,
                                color = if (isVoiceRecording) Color(0xFFFCA5A5) else AiCream,
                                fontSize = 11.sp,
                                modifier = Modifier.weight(1f),
                                maxLines = 2
                            )
                            if (isVoiceRecording) {
                                Text(
                                    "完成",
                                    color = AiGold,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.clickable { voiceMgr.stopRecording() }
                                )
                            }
                        }
                        Spacer(Modifier.height(4.dp))
                    }

                    // Input Bar with In-App Voice Recognition (Cantonese / Multi-Language / iFlytek)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Box {
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(AiCardBg)
                                    .border(1.dp, AiGold.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                                    .clickable { showLangMenu = true }
                                    .padding(horizontal = 8.dp, vertical = 10.dp)
                            ) {
                                Text(voiceLang.shortLabel, color = AiGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                            DropdownMenu(
                                expanded = showLangMenu,
                                onDismissRequest = { showLangMenu = false }
                            ) {
                                VoiceInputLanguage.values().forEach { lang ->
                                    DropdownMenuItem(
                                        text = { Text(lang.displayName, fontSize = 12.sp) },
                                        onClick = {
                                            voiceMgr.setLanguage(lang)
                                            showLangMenu = false
                                        }
                                    )
                                }
                            }
                        }

                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(if (isVoiceRecording) Color(0xFFDC2626) else Color(0xFF2563EB))
                                .pointerInput(isVoiceRecording) {
                                    detectTapGestures(
                                        onPress = {
                                            hideKb()
                                            val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                                            if (!granted) {
                                                micPermLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                                return@detectTapGestures
                                            }
                                            if (isVoiceRecording) {
                                                voiceMgr.finishListeningGracefully()
                                                return@detectTapGestures
                                            }
                                            val downTime = System.currentTimeMillis()
                                            startVoiceNow()
                                            tryAwaitRelease()
                                            // Long press (>= 350ms): release to finish; Quick tap (< 350ms): stay listening until tapped again!
                                            if (System.currentTimeMillis() - downTime >= 350L) {
                                                voiceMgr.finishListeningGracefully()
                                            }
                                        }
                                    )
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                if (isVoiceRecording) Icons.Default.Stop else Icons.Default.Mic,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(18.dp)
                            )
                        }

                        OutlinedTextField(
                            value = inputText,
                            onValueChange = { inputText = it },
                            placeholder = { Text("语音或打字提问（支持粤语/多语言）...", color = Color.Gray, fontSize = 11.5.sp) },
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                                focusedBorderColor = AiGold,
                                unfocusedBorderColor = Color.White.copy(alpha = 0.25f)
                            ),
                            modifier = Modifier.weight(1f)
                        )
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(if (isGenerating || inputText.isBlank()) Color.Gray else AiCrimson)
                                .clickable(enabled = !isGenerating && inputText.isNotBlank()) {
                                    voiceMgr.stopRecording()
                                    val q = inputText
                                    inputText = ""
                                    hideKb()
                                    llm.sendUserMessage(q)
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Send, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
                        }
                    }
                } else {
                    // Tab 1: On-Demand Model Manager & Memory
                    Column(
                        modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        // In-App Zero-Cost System Voice Recognition Card
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(AiCardBg).border(1.dp, AiGold.copy(alpha = 0.4f), RoundedCornerShape(12.dp)).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(5.dp)
                        ) {
                            Text("🎙️ 软件内语音录入（零成本 · 粤语/多语言）", color = AiGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Text(
                                "当前语言：${voiceLang.displayName}。直接嵌入本软件内流式转文字，不跳转外部应用、无需 API Key。",
                                color = AiCream,
                                fontSize = 10.5.sp
                            )
                            Text(
                                "离线多语言包：在手机「系统设置 → 语言与输入法 → 语音输入 / 语音识别」下载粤语、英语、日语等语言包即可离线使用。",
                                color = Color.LightGray,
                                fontSize = 10.sp
                            )
                        }

                        // Cloud API Key Card (Gemini / Doubao / DeepSeek / Custom)
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(AiCardBg).border(1.dp, AiGold.copy(alpha = 0.4f), RoundedCornerShape(12.dp)).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(7.dp)
                        ) {
                            Text("☁️ 云端大模型 API Key（Gemini / 豆包 / DeepSeek）", color = AiGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Row(
                                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                CloudAIProvider.values().forEach { prov ->
                                    val selected = cloudProvider == prov
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(if (selected) AiCrimson else Color.White.copy(alpha = 0.1f))
                                            .clickable {
                                                llm.selectCloudProvider(prov)
                                                urlDraft = llm.cloudBaseUrl.value
                                                modelDraft = llm.cloudModelName.value
                                            }
                                            .padding(horizontal = 9.dp, vertical = 5.dp)
                                    ) {
                                        Text(prov.label, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    }
                                }
                            }
                            val isCloudOn = cloudProvider != CloudAIProvider.LOCAL && cloudApiKey.isNotBlank()
                            Text(
                                if (isCloudOn) "当前生效：☁️ ${cloudProvider.label}（点上方「本地 Qwen2.5」可随时切回离线模型）" else "当前生效：📱 本地离线 Qwen2.5（不消耗云端 API 额度）",
                                color = if (isCloudOn) Color(0xFF4CAF50) else AiCream,
                                fontSize = 11.sp
                            )
                            if (cloudProvider != CloudAIProvider.LOCAL) {
                                OutlinedTextField(
                                    value = keyDraft,
                                    onValueChange = { keyDraft = it },
                                    label = { Text("API Key", color = Color.LightGray, fontSize = 11.sp) },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedTextColor = Color.White,
                                        unfocusedTextColor = Color.White,
                                        focusedBorderColor = AiGold,
                                        unfocusedBorderColor = Color.Gray
                                    )
                                )
                                OutlinedTextField(
                                    value = modelDraft,
                                    onValueChange = { modelDraft = it },
                                    label = { Text("模型名 / 豆包接入点 ID (ep-...)", color = Color.LightGray, fontSize = 11.sp) },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth(),
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedTextColor = Color.White,
                                        unfocusedTextColor = Color.White,
                                        focusedBorderColor = AiGold,
                                        unfocusedBorderColor = Color.Gray
                                    )
                                )
                                if (cloudProvider != CloudAIProvider.GEMINI) {
                                    OutlinedTextField(
                                        value = urlDraft,
                                        onValueChange = { urlDraft = it },
                                        label = { Text("API Base URL", color = Color.LightGray, fontSize = 11.sp) },
                                        singleLine = true,
                                        modifier = Modifier.fillMaxWidth(),
                                        colors = OutlinedTextFieldDefaults.colors(
                                            focusedTextColor = Color.White,
                                            unfocusedTextColor = Color.White,
                                            focusedBorderColor = AiGold,
                                            unfocusedBorderColor = Color.Gray
                                        )
                                    )
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Box(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(Color(0xFF2E7D32))
                                            .clickable {
                                                hideKb()
                                                llm.saveCloudConfig(cloudProvider, keyDraft, urlDraft, modelDraft)
                                            }
                                            .padding(vertical = 8.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text("保存启用", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    }
                                    Box(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(Color(0xFF1565C0))
                                            .clickable {
                                                hideKb()
                                                llm.saveCloudConfig(cloudProvider, keyDraft, urlDraft, modelDraft)
                                                llm.testCloudConnection()
                                            }
                                            .padding(vertical = 8.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text("保存并测试连接", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    }
                                }
                                if (cloudTestStatus.isNotBlank()) {
                                    Text(cloudTestStatus, color = AiGold, fontSize = 11.sp)
                                }
                            }
                        }
                        Column(
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(AiCardBg).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(5.dp)
                        ) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("📱 设备内存：${String.format("%.1f", llm.deviceTotalRamGB)} GB", color = AiGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text("上下文上限：${llm.maxContextTurns} 轮", color = Color.LightGray, fontSize = 11.sp)
                            }
                            Text(statusMsg, color = AiCream, fontSize = 11.sp)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                                Text("低内存保护（退出自动释放模型内存）", color = Color.White, fontSize = 11.sp)
                                Switch(checked = lowMemGuard, onCheckedChange = { llm.setLowMemoryGuard(it) })
                            }
                        }

                        Text("📦 按需下载本地模型（不占 APK 安装包体积）", color = AiGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)

                        LocalLLMManager.modelCatalog.forEach { spec ->
                            val isInstalled = installedModels.contains(spec.fileName)
                            val isActive = activeModel == spec.fileName && activeLoaded
                            val isDownloading = downloadingId == spec.id
                            Column(
                                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(AiCardBg).padding(10.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(spec.displayName, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        Text(spec.subtitle, color = Color.LightGray, fontSize = 10.sp)
                                    }
                                    Text(spec.sizeLabel, color = AiGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                                if (isDownloading) {
                                    LinearProgressIndicator(progress = { downloadProgress }, modifier = Modifier.fillMaxWidth(), color = AiGold)
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        Text("下载中 ${(downloadProgress * 100).toInt()}%", color = AiCream, fontSize = 11.sp)
                                        Text("取消", color = Color(0xFFFF5252), fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { llm.cancelDownload() })
                                    }
                                } else if (isInstalled) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(if (isActive) Color(0xFF2E7D32) else AiCrimson)
                                                .clickable {
                                                    if (isActive) llm.unloadModelFromMemory() else llm.loadModelIntoMemory(spec.fileName)
                                                }
                                                .padding(horizontal = 10.dp, vertical = 5.dp)
                                        ) {
                                            Text(if (isActive) "✓ 已挂载 (点击释放)" else "挂载启用", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                        }
                                        Text("删除释放空间", color = Color(0xFFFF5252), fontSize = 11.sp, modifier = Modifier.clickable { llm.deleteModel(spec.fileName) })
                                    }
                                } else {
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(if (downloadingId == null) AiCrimson else Color.Gray)
                                            .clickable(enabled = downloadingId == null) { llm.startDownload(spec) }
                                            .padding(horizontal = 12.dp, vertical = 5.dp)
                                    ) {
                                        Text("⬇️ 一键下载 (.gguf)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    }
                                }
                            }
                        }

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(Color.White.copy(alpha = 0.08f))
                                .border(1.dp, AiGold.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
                                .clickable { importLauncher.launch(arrayOf("*/*")) }
                                .padding(vertical = 10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("📂 从手机文件导入本地 .gguf 模型", color = AiGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }

                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("📝 茶会本地长期记忆（${memories.size} 条）", color = AiGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            if (memories.isNotEmpty()) {
                                Text("清空", color = Color(0xFFFF5252), fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { llm.clearMemories() })
                            }
                        }
                        if (memories.isEmpty()) {
                            Text("对话中说“记住我喜欢…”即可自动存入本地小本本。", color = Color.Gray, fontSize = 11.sp)
                        } else {
                            memories.forEach { m ->
                                Text("• $m", color = AiCream, fontSize = 11.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}
