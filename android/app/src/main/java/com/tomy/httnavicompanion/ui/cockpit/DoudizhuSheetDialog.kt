package com.tomy.httnavicompanion.ui.cockpit

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*

private val DdzBgGreen = Color(0xFF104B2C)
private val DdzCardGreen = Color(0xFF0A331D)
private val DdzGold = Color(0xFFE0B861)
private val DdzRed = Color(0xFFCC2D34)
private val DdzBlue = Color(0xFF1877F2)
private val DdzCream = Color(0xFFFAF2E0)

@Composable
fun KOnDoudizhuSheetDialog(onDismiss: () -> Unit) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val engine = manager.doudizhuEngine
    val lang by manager.language.collectAsState()
    val allMemberFrames by manager.allMemberFrames.collectAsState()

    val phase by engine.phase.collectAsState()
    val networkMode by engine.networkMode.collectAsState()
    val serverUrl by engine.serverUrl.collectAsState()
    val roomCode by engine.roomCode.collectAsState()
    val nickname by engine.myNickname.collectAsState()
    val myChar by engine.myChar.collectAsState()
    val isHosting by engine.isHostingRoom.collectAsState()
    val isScanning by engine.isScanningRooms.collectAsState()
    val isServerConn by engine.isServerConnected.collectAsState()
    val discoveredRooms by engine.discoveredRooms.collectAsState()
    val connectedPeers by engine.connectedPeerNames.collectAsState()

    val totalRounds by engine.totalRounds.collectAsState()
    val currentRound by engine.currentRound.collectAsState()
    val baseScore by engine.baseScore.collectAsState()
    val maxMult by engine.maxMultiplier.collectAsState()
    val turnLimit by engine.turnTimeLimit.collectAsState()
    val turnRem by engine.turnRemainingSeconds.collectAsState()
    val allowCounter by engine.allowCardCounter.collectAsState()
    val aiDiff by engine.aiDifficulty.collectAsState()

    val seats by engine.seats.collectAsState()
    val mySeatIdx by engine.mySeatIndex.collectAsState()
    val holeCards by engine.holeCards.collectAsState()
    val selectedIds by engine.selectedCardIds.collectAsState()
    val currentTurn by engine.currentTurnSeat.collectAsState()
    val highestBid by engine.highestBid.collectAsState()
    val multiplier by engine.multiplier.collectAsState()
    val statusBanner by engine.statusBanner.collectAsState()
    val playedHistory by engine.playedCardsHistory.collectAsState()

    var showCardCounter by remember { mutableStateOf(true) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.98f)
                .fillMaxHeight(0.95f)
                .clip(RoundedCornerShape(18.dp))
                .border(2.dp, DdzGold, RoundedCornerShape(18.dp)),
            color = DdzBgGreen
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(10.dp)) {
                // Top Bar (matches iOS 1:1)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(DdzCardGreen)
                            .clickable {
                                if (phase != DoudizhuGamePhase.LOBBY) {
                                    engine.leaveRoomAndResetLobby()
                                }
                            }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text(
                            if (phase == DoudizhuGamePhase.LOBBY) "♠ 房间大厅" else "< 退出房间",
                            color = DdzGold,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Text(
                        "放课后茶会 · 面对面斗地主",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )

                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(DdzCardGreen)
                            .clickable { onDismiss() }
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                    ) {
                        Text("✕ 关闭", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }

                Spacer(Modifier.height(6.dp))

                // Status Banner
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(DdzCardGreen)
                        .border(1.dp, DdzGold.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                ) {
                    Text(statusBanner, color = DdzCream, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                }

                Spacer(Modifier.height(8.dp))

                if (phase == DoudizhuGamePhase.LOBBY) {
                    // =====================================================
                    // LOBBY VIEW (1:1 match with iOS Screenshots 1-5)
                    // =====================================================
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Mode Switcher Tabs
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val isP2P = networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (isP2P) DdzRed else DdzCardGreen)
                                    .border(1.5.dp, if (isP2P) DdzGold else Color.Transparent, RoundedCornerShape(10.dp))
                                    .clickable { engine.setNetworkMode(DoudizhuNetworkMode.FACE_TO_FACE_P2P) }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("📡 面对面开房联机 (免流量)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(if (!isP2P) DdzBlue else DdzCardGreen)
                                    .border(1.5.dp, if (!isP2P) DdzGold else Color.Transparent, RoundedCornerShape(10.dp))
                                    .clickable { engine.setNetworkMode(DoudizhuNetworkMode.ONLINE_SERVER) }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("☁️ 在线服务器联机", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            }
                        }

                        // 1. Personal Nickname & Character Selection
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text("1. 个人昵称与出战轻音角色选择", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Black)
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text("昵称:", color = Color.LightGray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                OutlinedTextField(
                                    value = nickname,
                                    onValueChange = { engine.setMyNickname(it) },
                                    singleLine = true,
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedTextColor = Color.White,
                                        unfocusedTextColor = Color.White,
                                        focusedBorderColor = DdzGold,
                                        unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                    ),
                                    modifier = Modifier.weight(1f)
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                CharacterFilter.fiveIndividuals.forEach { ch ->
                                    val sel = myChar == ch
                                    Column(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(if (sel) DdzRed else Color.Black.copy(alpha = 0.25f))
                                            .border(1.5.dp, if (sel) DdzGold else Color.White.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                                            .clickable { engine.setMyCharacter(ch) }
                                            .padding(vertical = 6.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        allMemberFrames[ch.charId]?.let { bmp ->
                                            Image(
                                                bitmap = bmp.asImageBitmap(),
                                                contentDescription = null,
                                                filterQuality = FilterQuality.None,
                                                modifier = Modifier.size(40.dp)
                                            )
                                        }
                                        Text(ch.displayName(lang), color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                    }
                                }
                            }
                        }

                        // 2. Network Section (P2P Bluetooth+Wi-Fi OR Online Server)
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (networkMode == DoudizhuNetworkMode.FACE_TO_FACE_P2P) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text("2. 面对面开房联机 (蓝牙 + P2P Wi-Fi 直连)", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text("房号:", color = Color.LightGray, fontSize = 11.sp)
                                        OutlinedTextField(
                                            value = roomCode,
                                            onValueChange = { engine.setRoomCode(it) },
                                            singleLine = true,
                                            colors = OutlinedTextFieldDefaults.colors(
                                                focusedTextColor = DdzGold,
                                                unfocusedTextColor = DdzGold,
                                                focusedBorderColor = DdzGold,
                                                unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                            ),
                                            modifier = Modifier.width(80.dp)
                                        )
                                    }
                                }

                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(
                                        onClick = { engine.startHostingFaceToFaceRoom() },
                                        colors = ButtonDefaults.buttonColors(containerColor = if (isHosting) Color(0xFF2E7D32) else DdzRed),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f),
                                        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 8.dp)
                                    ) {
                                        Text(if (isHosting) "📡 房间已开启" else "🏠 创建面对面房间(房主)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1)
                                    }
                                    Button(
                                        onClick = { engine.startScanningFaceToFaceRooms() },
                                        colors = ButtonDefaults.buttonColors(containerColor = if (isScanning) DdzBlue else Color(0xFF1B5E20)),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f),
                                        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 8.dp)
                                    ) {
                                        Text(if (isScanning) "🔍 正在扫描中..." else "📡 扫描并加入附近房间", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, maxLines = 1)
                                    }
                                }

                                if (connectedPeers.isNotEmpty()) {
                                    Text("已连入玩家: ${connectedPeers.joinToString(", ")}", color = Color(0xFF00E676), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }

                                if (isScanning && discoveredRooms.isNotEmpty()) {
                                    discoveredRooms.forEach { room ->
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(Color.Black.copy(alpha = 0.35f))
                                                .border(1.dp, DdzGold, RoundedCornerShape(8.dp))
                                                .clickable { engine.joinDiscoveredRoom(room) }
                                                .padding(horizontal = 10.dp, vertical = 7.dp),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text("${room.hostName} (房号:${room.roomCode})", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                            Text("点击加入 >", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                }
                            } else {
                                Text("2. 在线联机服务器配置 (支持 ws:// 或 wss://)", color = DdzGold, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    OutlinedTextField(
                                        value = serverUrl,
                                        onValueChange = { engine.setServerUrl(it) },
                                        singleLine = true,
                                        colors = OutlinedTextFieldDefaults.colors(
                                            focusedTextColor = Color.White,
                                            unfocusedTextColor = Color.White,
                                            focusedBorderColor = DdzGold,
                                            unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                                        ),
                                        modifier = Modifier.weight(1f)
                                    )
                                    Button(
                                        onClick = { engine.connectOnlineServerRoom() },
                                        colors = ButtonDefaults.buttonColors(containerColor = if (isServerConn) Color(0xFF2E7D32) else DdzBlue),
                                        shape = RoundedCornerShape(10.dp)
                                    ) {
                                        Text(if (isServerConn) "已连接" else "连接服务器", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    }
                                }
                            }
                        }

                        // 3. Host Room Rules Settings
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text("3. 房主房间规则设置 (局数/底分/封顶/倒计时/AI难度)", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                Text("第 $currentRound / ${if (totalRounds == 0) "∞" else totalRounds} 局", color = Color(0xFF00E676), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }

                            RuleOptionRow("对局局数:", listOf(3 to "3局", 5 to "5局", 10 to "10局", 0 to "无限局"), totalRounds, DdzRed) { engine.setTotalRounds(it) }
                            RuleOptionRow("每局底分:", listOf(50 to "50分", 100 to "100分", 200 to "200分", 500 to "500分"), baseScore, Color(0xFFD99426)) { engine.setBaseScore(it) }
                            RuleOptionRow("倍数封顶:", listOf(16 to "16倍", 32 to "32倍", 64 to "64倍", 0 to "不封顶"), maxMult, Color(0xFF9C27B0)) { engine.setMaxMultiplier(it) }
                            RuleOptionRow("出牌限时:", listOf(15 to "15秒", 25 to "25秒", 30 to "30秒", 0 to "不限时"), turnLimit, DdzBlue) { engine.setTurnTimeLimit(it) }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)
                            ) {
                                Text("辅助与AI:", color = Color.LightGray, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(56.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(7.dp))
                                        .background(if (allowCounter) Color(0xFF2E7D32) else Color.Black.copy(alpha = 0.35f))
                                        .clickable { engine.setAllowCardCounter(!allowCounter) }
                                        .padding(horizontal = 7.dp, vertical = 5.dp)
                                ) {
                                    Text(if (allowCounter) "✓ 记牌器" else "记牌器", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                }
                                DoudizhuAIDifficulty.values().forEach { diff ->
                                    val sel = aiDiff == diff
                                    Box(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(7.dp))
                                            .background(if (sel) Color(0xFFD99426) else Color.Black.copy(alpha = 0.35f))
                                            .clickable { engine.setAIDifficulty(diff) }
                                            .padding(vertical = 5.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text(diff.label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                    }
                                }
                            }
                        }

                        // 4. Current Table Seat Preview
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(DdzCardGreen)
                                .padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text("4. 当前牌桌座位预览 (不足3人将由轻音少女 AI 自动补位)", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                seats.forEach { seat ->
                                    Column(
                                        modifier = Modifier
                                            .weight(1f)
                                            .clip(RoundedCornerShape(10.dp))
                                            .background(Color.Black.copy(alpha = 0.28f))
                                            .border(1.dp, if (!seat.isAI) Color(0xFF00E676) else Color.White.copy(alpha = 0.15f), RoundedCornerShape(10.dp))
                                            .padding(8.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        allMemberFrames[seat.character.charId]?.let { bmp ->
                                            Image(
                                                bitmap = bmp.asImageBitmap(),
                                                contentDescription = null,
                                                filterQuality = FilterQuality.None,
                                                modifier = Modifier.size(44.dp)
                                            )
                                        }
                                        Text(seat.name, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(if (seat.isAI) "🤖 轻音AI补位" else "📱 真机玩家", color = if (seat.isAI) Color(0xFF64B5F6) else Color(0xFF00E676), fontSize = 9.sp)
                                        Text("积分: ${seat.score}", color = Color.LightGray, fontSize = 9.sp)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Bottom Start Button
                    Button(
                        onClick = { engine.startNewGame() },
                        colors = ButtonDefaults.buttonColors(containerColor = DdzRed),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth().height(46.dp)
                    ) {
                        val roundTxt = if (totalRounds == 0) "无限局" else "${totalRounds}局制"
                        Text("▶ 立即开始牌局 ($roundTxt · 底分 $baseScore)", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black)
                    }
                } else {
                    // =====================================================
                    // ACTIVE GAME TABLE VIEW (1:1 match with Screenshot 6)
                    // =====================================================
                    // Top Hole Cards + Multiplier + Round + Timer + Card Counter Toggle
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        // 3 Hole Cards
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            val showHole = phase != DoudizhuGamePhase.BIDDING
                            holeCards.forEach { card ->
                                val bmp = app.assetDecryptor.getDoudizhuCardBitmap(if (showHole) card.cardImageKey else "back")
                                if (bmp != null) {
                                    Image(
                                        bitmap = bmp.asImageBitmap(),
                                        contentDescription = null,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier
                                            .size(34.dp, 46.dp)
                                            .clip(RoundedCornerShape(4.dp))
                                            .border(1.dp, DdzGold, RoundedCornerShape(4.dp))
                                    )
                                }
                            }
                        }

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(DdzRed)
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Text("倍数\nx$multiplier", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                        }

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(DdzCardGreen)
                                .padding(horizontal = 8.dp, vertical = 5.dp)
                        ) {
                            Text("第 $currentRound/${if (totalRounds == 0) "∞" else totalRounds}\n局", color = DdzCream, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(DdzCardGreen)
                                .padding(horizontal = 8.dp, vertical = 6.dp)
                        ) {
                            Text(if (turnLimit == 0) "⏱ ∞" else "⏱ ${turnRem}s", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }

                        if (allowCounter) {
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (showCardCounter) DdzGold else DdzCardGreen)
                                    .clickable { showCardCounter = !showCardCounter }
                                    .padding(horizontal = 8.dp, vertical = 6.dp)
                            ) {
                                Text("记牌器", color = if (showCardCounter) Color.Black else Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                            }
                        }
                    }

                    // Card Counter Strip
                    if (allowCounter && showCardCounter) {
                        Spacer(Modifier.height(6.dp))
                        val myHand = seats.getOrNull(mySeatIdx)?.hand ?: emptyList()
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(Color.Black.copy(alpha = 0.4f))
                                .padding(horizontal = 4.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                            (17 downTo 3).forEach { r ->
                                val total = if (r >= 16) 1 else 4
                                val played = playedHistory.count { it.rank == r }
                                val mine = myHand.count { it.rank == r }
                                val rem = (total - played - mine).coerceAtLeast(0)
                                val lbl = when (r) {
                                    17 -> "大王"; 16 -> "小王"; 15 -> "2"; 14 -> "A"; 13 -> "K"; 12 -> "Q"; 11 -> "J"; else -> r.toString()
                                }
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(lbl, color = if (r >= 15) DdzGold else Color.LightGray, fontSize = 8.sp, fontWeight = FontWeight.Bold)
                                    Text("$rem", color = if (rem > 0) Color.White else Color.DarkGray, fontSize = 10.sp, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Opponents Row (Left = Previous Seat, Right = Next Seat)
                    if (seats.size == 3) {
                        val prevIdx = (mySeatIdx + 2) % 3
                        val nextIdx = (mySeatIdx + 1) % 3
                        val leftSeat = seats[prevIdx]
                        val rightSeat = seats[nextIdx]

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.Top
                        ) {
                            OpponentSeatBox(leftSeat, currentTurn == prevIdx, allMemberFrames[leftSeat.character.charId], Modifier.weight(1f))

                            // Center Played Cards / Action Status
                            Column(
                                modifier = Modifier.weight(1.1f).padding(horizontal = 4.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    ActionBadge("⬅ 上家", leftSeat.lastActionText.ifBlank { "等待中" })
                                    ActionBadge("下家 ➡", rightSeat.lastActionText.ifBlank { "等待中" })
                                }
                                val lastPlayed = if (leftSeat.lastPlayed.isNotEmpty()) leftSeat.lastPlayed else rightSeat.lastPlayed
                                if (lastPlayed.isNotEmpty()) {
                                    LazyRow(horizontalArrangement = Arrangement.spacedBy((-14).dp)) {
                                        items(lastPlayed) { c ->
                                            val bmp = app.assetDecryptor.getDoudizhuCardBitmap(c.cardImageKey)
                                            if (bmp != null) {
                                                Image(
                                                    bitmap = bmp.asImageBitmap(),
                                                    contentDescription = null,
                                                    modifier = Modifier
                                                        .size(44.dp, 60.dp)
                                                        .clip(RoundedCornerShape(5.dp))
                                                        .border(1.dp, Color.Gray, RoundedCornerShape(5.dp))
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                            OpponentSeatBox(rightSeat, currentTurn == nextIdx, allMemberFrames[rightSeat.character.charId], Modifier.weight(1f))
                        }
                    }

                    Spacer(Modifier.weight(1f))

                    // Action Buttons Row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        when (phase) {
                            DoudizhuGamePhase.BIDDING -> {
                                if (currentTurn == mySeatIdx) {
                                    listOf(0 to "不叫", 1 to "1 分", 2 to "2 分", 3 to "3 分").forEach { (b, lbl) ->
                                        val enabled = (b == 0 || b > highestBid)
                                        Button(
                                            onClick = { if (enabled) engine.submitBid(b) },
                                            enabled = enabled,
                                            colors = ButtonDefaults.buttonColors(containerColor = if (b == 0) Color.DarkGray else DdzRed),
                                            shape = RoundedCornerShape(10.dp),
                                            modifier = Modifier.weight(1f)
                                        ) {
                                            Text(lbl, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black)
                                        }
                                    }
                                } else {
                                    Text("等待其他玩家叫分...", color = DdzCream, fontSize = 12.sp, modifier = Modifier.padding(8.dp))
                                }
                            }
                            DoudizhuGamePhase.PLAYING -> {
                                if (currentTurn == mySeatIdx) {
                                    Button(
                                        onClick = { engine.passTurn() },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color.DarkGray),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f)
                                    ) { Text("不出", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    Button(
                                        onClick = { engine.hintCards() },
                                        colors = ButtonDefaults.buttonColors(containerColor = DdzBlue),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f)
                                    ) { Text("提示", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    Button(
                                        onClick = { engine.clearSelection() },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF455A64)),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f)
                                    ) { Text("重选", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    Button(
                                        onClick = { engine.playSelectedCards() },
                                        colors = ButtonDefaults.buttonColors(containerColor = DdzRed),
                                        shape = RoundedCornerShape(10.dp),
                                        modifier = Modifier.weight(1f)
                                    ) { Text("出牌", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Black) }
                                } else {
                                    Text("等待对手出牌...", color = DdzCream, fontSize = 12.sp, modifier = Modifier.padding(8.dp))
                                }
                            }
                            DoudizhuGamePhase.FINISHED -> {
                                Button(
                                    onClick = { engine.startNewGame() },
                                    colors = ButtonDefaults.buttonColors(containerColor = DdzRed),
                                    shape = RoundedCornerShape(10.dp),
                                    modifier = Modifier.fillMaxWidth()
                                ) { Text("▶ 再来一局", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black) }
                            }
                            else -> {}
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Hand Cards 2-Row Fan Area using REAL K-ON! Poker Card Images!
                    val mySeat = seats.getOrNull(mySeatIdx)
                    if (mySeat != null) {
                        val hand = mySeat.hand
                        val splitIdx = if (hand.size > 10) (hand.size + 1) / 2 else hand.size
                        val row1 = hand.subList(0, splitIdx)
                        val row2 = if (splitIdx < hand.size) hand.subList(splitIdx, hand.size) else emptyList()

                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy((-20).dp)
                        ) {
                            HandCardFanRow(row1, selectedIds, app) { engine.toggleSelectCard(it) }
                            if (row2.isNotEmpty()) {
                                HandCardFanRow(row2, selectedIds, app) { engine.toggleSelectCard(it) }
                            }
                        }

                        Spacer(Modifier.height(8.dp))

                        // Bottom Player Status Bar
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(DdzCardGreen)
                                .border(1.dp, DdzGold.copy(alpha = 0.6f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                allMemberFrames[mySeat.character.charId]?.let { bmp ->
                                    Image(
                                        bitmap = bmp.asImageBitmap(),
                                        contentDescription = null,
                                        filterQuality = FilterQuality.None,
                                        modifier = Modifier.size(32.dp)
                                    )
                                }
                                Text(
                                    "${mySeat.name} ${if (mySeat.isLandlord) "[👑地主]" else ""} · 手牌: ${hand.size}张",
                                    color = Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (currentTurn == mySeatIdx) Color(0xFF2E7D32) else Color.DarkGray)
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text(
                                    if (currentTurn == mySeatIdx) "👉 轮到你操作" else "等待中",
                                    color = Color.White,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Black
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RuleOptionRow(
    label: String,
    options: List<Pair<Int, String>>,
    selectedVal: Int,
    activeColor: Color,
    onSelect: (Int) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(label, color = Color.LightGray, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(56.dp))
        options.forEach { (v, txt) ->
            val sel = v == selectedVal
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(7.dp))
                    .background(if (sel) activeColor else Color.Black.copy(alpha = 0.35f))
                    .clickable { onSelect(v) }
                    .padding(vertical = 5.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(txt, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            }
        }
    }
}

@Composable
private fun OpponentSeatBox(
    seat: DoudizhuPlayerSeat,
    isTurn: Boolean,
    spriteBmp: android.graphics.Bitmap?,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(DdzCardGreen)
            .border(1.5.dp, if (isTurn) DdzGold else Color.White.copy(alpha = 0.15f), RoundedCornerShape(10.dp))
            .padding(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (spriteBmp != null) {
            Image(
                bitmap = spriteBmp.asImageBitmap(),
                contentDescription = null,
                filterQuality = FilterQuality.None,
                modifier = Modifier.size(38.dp)
            )
        }
        Text(
            "${seat.name} ${if (seat.isLandlord) "👑" else ""}",
            color = Color.White,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text("🃏 ${seat.hand.size} 张", color = DdzGold, fontSize = 11.sp, fontWeight = FontWeight.Black)
        Text("积分: ${seat.score}", color = Color.LightGray, fontSize = 9.sp)
    }
}

@Composable
private fun ActionBadge(direction: String, action: String) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(DdzCardGreen)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(direction, color = Color.LightGray, fontSize = 9.sp)
        Text(action, color = DdzGold, fontSize = 10.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun HandCardFanRow(
    cards: List<DoudizhuCard>,
    selectedIds: Set<String>,
    app: HTTNaviApp,
    onToggle: (String) -> Unit
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy((-18).dp),
        verticalAlignment = Alignment.Bottom
    ) {
        cards.forEach { card ->
            val isSel = selectedIds.contains(card.id)
            val bmp = app.assetDecryptor.getDoudizhuCardBitmap(card.cardImageKey)
            Box(
                modifier = Modifier
                    .offset(y = if (isSel) (-12).dp else 0.dp)
                    .size(54.dp, 76.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White)
                    .border(
                        width = if (isSel) 2.5.dp else 1.dp,
                        color = if (isSel) DdzGold else Color.Gray,
                        shape = RoundedCornerShape(6.dp)
                    )
                    .clickable { onToggle(card.id) }
            ) {
                if (bmp != null) {
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = card.rankLabel,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    Text(
                        "${card.suit.symbol}\n${card.rankLabel}",
                        color = if (card.isRedCard) Color.Red else Color.Black,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Black,
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
            }
        }
    }
}
