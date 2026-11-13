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
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*

@Composable
fun KOnDoudizhuSheetDialog(onDismiss: () -> Unit) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val engine = manager.doudizhuEngine
    val lang by manager.language.collectAsState()
    val allMemberFrames by manager.allMemberFrames.collectAsState()

    val phase by engine.phase.collectAsState()
    val seats by engine.seats.collectAsState()
    val holeCards by engine.holeCards.collectAsState()
    val selectedIds by engine.selectedCardIds.collectAsState()
    val currentTurn by engine.currentTurnSeat.collectAsState()
    val multiplier by engine.multiplier.collectAsState()
    val statusBanner by engine.statusBanner.collectAsState()
    val myChar by engine.myChar.collectAsState()
    val playedHistory by engine.playedCardsHistory.collectAsState()

    var showCardCounter by remember { mutableStateOf(false) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.96f)
                .fillMaxHeight(0.92f)
                .clip(RoundedCornerShape(18.dp))
                .border(2.dp, Color(0xFFE0B861), RoundedCornerShape(18.dp)),
            color = Color(0xFF0E291C)
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(12.dp)) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("🎸 放课后茶会斗地主", color = Color(0xFFE0B861), fontSize = 16.sp, fontWeight = FontWeight.Black)
                        Text(
                            "倍数: x$multiplier",
                            color = Color.White,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .background(Color(0xFFA61E2E), RoundedCornerShape(6.dp))
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (phase == DoudizhuGamePhase.PLAYING) {
                            TextButton(onClick = { showCardCounter = !showCardCounter }) {
                                Text("记牌器", color = Color(0xFF00E5FF), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                        }
                    }
                }

                // Status Banner
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.Black.copy(alpha = 0.45f))
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                ) {
                    Text(statusBanner, color = Color(0xFFFAF2E0), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }

                Spacer(Modifier.height(8.dp))

                if (phase == DoudizhuGamePhase.LOBBY) {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text("选择你的轻音部代表角色：", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(10.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CharacterFilter.fiveIndividuals.forEach { ch ->
                                val isSel = myChar == ch
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(if (isSel) Color(0xFFA61E2E) else Color.Black.copy(alpha = 0.4f))
                                        .border(1.5.dp, if (isSel) Color(0xFFE0B861) else Color.Gray, RoundedCornerShape(10.dp))
                                        .clickable { engine.setMyCharacter(ch) }
                                        .padding(8.dp)
                                ) {
                                    allMemberFrames[ch.charId]?.let { bmp ->
                                        Image(
                                            bitmap = bmp.asImageBitmap(),
                                            contentDescription = null,
                                            filterQuality = FilterQuality.None,
                                            modifier = Modifier.size(48.dp)
                                        )
                                    }
                                    Text(ch.displayName(lang), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                        Spacer(Modifier.height(20.dp))
                        Button(
                            onClick = { engine.startNewGame() },
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFA61E2E)),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.height(46.dp)
                        ) {
                            Text("开始发牌 (1v2 轻音部AI对战)", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Black)
                        }
                    }
                } else {
                    // Hole Cards Row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("底牌: ", color = Color(0xFFE0B861), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        holeCards.forEach { card ->
                            val showFace = phase != DoudizhuGamePhase.BIDDING
                            Box(
                                modifier = Modifier
                                    .padding(horizontal = 3.dp)
                                    .clip(RoundedCornerShape(5.dp))
                                    .background(if (showFace) Color.White else Color(0xFFA61E2E))
                                    .border(1.dp, Color(0xFFE0B861), RoundedCornerShape(5.dp))
                                    .padding(horizontal = 7.dp, vertical = 3.dp)
                            ) {
                                Text(
                                    if (showFace) "${card.suit.symbol}${card.rankLabel}" else "HTT",
                                    color = if (showFace) (if (card.suit.isRed) Color.Red else Color.Black) else Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Black
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(8.dp))

                    // Two AI Opponents Row
                    if (seats.size >= 3) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            listOf(seats[2], seats[1]).forEach { aiSeat ->
                                Column(
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(horizontal = 4.dp)
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(Color.Black.copy(alpha = 0.45f))
                                        .border(
                                            1.5.dp,
                                            if (currentTurn == aiSeat.seatIndex) Color(0xFFE0B861) else Color.White.copy(alpha = 0.15f),
                                            RoundedCornerShape(10.dp)
                                        )
                                        .padding(8.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        allMemberFrames[aiSeat.character.charId]?.let { bmp ->
                                            Image(
                                                bitmap = bmp.asImageBitmap(),
                                                contentDescription = null,
                                                filterQuality = FilterQuality.None,
                                                modifier = Modifier.size(36.dp)
                                            )
                                        }
                                        Column {
                                            Text(
                                                "${aiSeat.character.displayName(lang)} ${if (aiSeat.isLandlord) "[地主]" else "[农民]"}",
                                                color = if (aiSeat.isLandlord) Color(0xFFE0B861) else Color.White,
                                                fontSize = 11.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                            Text("余 ${aiSeat.hand.size} 张", color = Color(0xFF00E5FF), fontSize = 10.sp)
                                        }
                                    }
                                    Spacer(Modifier.height(4.dp))
                                    if (aiSeat.passedLast) {
                                        Text("不出", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    } else if (aiSeat.lastPlayed.isNotEmpty()) {
                                        LazyRow(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                            items(aiSeat.lastPlayed) { c ->
                                                MiniCardChip(c)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(Modifier.weight(1f))

                    // Card Counter Overlay if toggled
                    if (showCardCounter) {
                        val remainingRanks = (17 downTo 3).map { r ->
                            val totalForRank = if (r >= 16) 1 else 4
                            val played = playedHistory.count { it.rank == r }
                            val inMyHand = seats.firstOrNull()?.hand?.count { it.rank == r } ?: 0
                            val rem = (totalForRank - played - inMyHand).coerceAtLeast(0)
                            val label = when (r) {
                                17 -> "大"; 16 -> "小"; 15 -> "2"; 14 -> "A"; 13 -> "K"; 12 -> "Q"; 11 -> "J"; else -> r.toString()
                            }
                            "$label:$rem"
                        }
                        Text(
                            "记牌器(外面剩余): " + remainingRanks.joinToString("  "),
                            color = Color(0xFF00E5FF),
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(6.dp))
                                .padding(6.dp)
                        )
                        Spacer(Modifier.height(6.dp))
                    }

                    // My Played / Action Row
                    val mySeat = seats.firstOrNull()
                    if (mySeat != null) {
                        if (mySeat.lastPlayed.isNotEmpty()) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                                horizontalArrangement = Arrangement.Center
                            ) {
                                mySeat.lastPlayed.forEach { MiniCardChip(it) }
                            }
                        }

                        // Action Controls
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            when (phase) {
                                DoudizhuGamePhase.BIDDING -> {
                                    listOf(0 to "不叫", 1 to "1分", 2 to "2分", 3 to "3分").forEach { (b, lbl) ->
                                        Button(
                                            onClick = { engine.submitBid(b) },
                                            colors = ButtonDefaults.buttonColors(containerColor = if (b == 0) Color.DarkGray else Color(0xFFA61E2E)),
                                            modifier = Modifier.padding(horizontal = 4.dp)
                                        ) {
                                            Text(lbl, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                }
                                DoudizhuGamePhase.PLAYING -> {
                                    if (currentTurn == 0) {
                                        Button(
                                            onClick = { engine.passTurn() },
                                            colors = ButtonDefaults.buttonColors(containerColor = Color.DarkGray),
                                            modifier = Modifier.padding(horizontal = 4.dp)
                                        ) { Text("不出", color = Color.White, fontSize = 12.sp) }
                                        Button(
                                            onClick = { engine.hintCards() },
                                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2)),
                                            modifier = Modifier.padding(horizontal = 4.dp)
                                        ) { Text("提示", color = Color.White, fontSize = 12.sp) }
                                        Button(
                                            onClick = { engine.playSelectedCards() },
                                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFA61E2E)),
                                            modifier = Modifier.padding(horizontal = 4.dp)
                                        ) { Text("出牌", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
                                    } else {
                                        Text("等待对手出牌...", color = Color.LightGray, fontSize = 12.sp)
                                    }
                                }
                                DoudizhuGamePhase.FINISHED -> {
                                    Button(
                                        onClick = { engine.startNewGame() },
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFA61E2E))
                                    ) {
                                        Text("再来一局", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Black)
                                    }
                                }
                                else -> {}
                            }
                        }

                        Spacer(Modifier.height(8.dp))

                        // My Hand Cards Fan Row
                        Text(
                            "我的手牌 (${mySeat.character.displayName(lang)} ${if (mySeat.isLandlord) "· 地主" else "· 农民"}) · 余 ${mySeat.hand.size} 张",
                            color = Color(0xFFE0B861),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(Modifier.height(4.dp))
                        LazyRow(
                            modifier = Modifier.fillMaxWidth().height(84.dp),
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.Bottom
                        ) {
                            items(mySeat.hand, key = { it.id }) { card ->
                                val isSelected = selectedIds.contains(card.id)
                                Column(
                                    modifier = Modifier
                                        .width(42.dp)
                                        .height(if (isSelected) 78.dp else 66.dp)
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(Color.White)
                                        .border(
                                            width = if (isSelected) 2.dp else 1.dp,
                                            color = if (isSelected) Color(0xFFE0B861) else Color.Gray,
                                            shape = RoundedCornerShape(6.dp)
                                        )
                                        .clickable { engine.toggleSelectCard(card.id) }
                                        .padding(4.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        card.rankLabel,
                                        color = if (card.suit.isRed) Color.Red else Color.Black,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Black,
                                        textAlign = TextAlign.Center
                                    )
                                    Text(
                                        card.suit.symbol,
                                        color = if (card.suit.isRed) Color.Red else Color.Black,
                                        fontSize = 16.sp
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MiniCardChip(card: DoudizhuCard) {
    Box(
        modifier = Modifier
            .padding(horizontal = 1.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Color.White)
            .border(1.dp, Color.LightGray, RoundedCornerShape(4.dp))
            .padding(horizontal = 4.dp, vertical = 2.dp)
    ) {
        Text(
            "${card.suit.symbol}${card.rankLabel}",
            color = if (card.suit.isRed) Color.Red else Color.Black,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold
        )
    }
}
