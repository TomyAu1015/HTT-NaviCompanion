package com.tomy.httnavicompanion.ui.cockpit

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tomy.httnavicompanion.HTTNaviApp
import com.tomy.httnavicompanion.audio.*

private val SheetCrimson = Color(0xFFA61E2E)
private val SheetGold = Color(0xFFE0B861)
private val SheetCream = Color(0xFFFAF2E0)
private val SheetDarkBg = Color(0xFF161821)
private val SheetCardBg = Color(0xFF202431)

// 1. Music Library Sheet Dialog
@Composable
fun MusicLibrarySheetDialog(onDismiss: () -> Unit) {
    val app = HTTNaviApp.instance
    val musicMgr = app.musicManager
    val playlist by musicMgr.playlist.collectAsState()
    val currentTrack by musicMgr.currentTrack.collectAsState()
    val isPlaying by musicMgr.isPlaying.collectAsState()
    val currentTime by musicMgr.currentTimeSec.collectAsState()
    val duration by musicMgr.durationSec.collectAsState()
    val playMode by musicMgr.playMode.collectAsState()
    val selectedCat by musicMgr.selectedCategory.collectAsState()
    val statusMsg by musicMgr.libraryStatusMessage.collectAsState()

    val filteredList = remember(playlist, selectedCat) {
        if (selectedCat == MusicCategoryFilter.ALL) playlist
        else playlist.filter { it.category == selectedCat }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.88f)
                .clip(RoundedCornerShape(18.dp))
                .border(2.dp, SheetGold, RoundedCornerShape(18.dp)),
            color = SheetDarkBg
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(14.dp)) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.MusicNote, contentDescription = null, tint = SheetGold)
                        Column {
                            Text("放课后茶会 · 专属轻音音乐馆", color = SheetCream, fontSize = 16.sp, fontWeight = FontWeight.Black)
                            Text(statusMsg, color = SheetGold, fontSize = 10.sp)
                        }
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                    }
                }

                Spacer(Modifier.height(8.dp))

                // Current Playing Card
                Card(
                    colors = CardDefaults.cardColors(containerColor = SheetCardBg),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().border(1.dp, SheetGold.copy(alpha = 0.5f), RoundedCornerShape(14.dp))
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(currentTrack.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${currentTrack.artist} · ${currentTrack.album}", color = SheetGold, fontSize = 11.sp, maxLines = 1)
                            }
                            Text(
                                String.format("%02d:%02d / %02d:%02d", currentTime / 60, currentTime % 60, duration / 60, duration % 60),
                                color = SheetCream,
                                fontSize = 11.sp,
                                fontFamily = FontFamily.Monospace
                            )
                        }

                        Spacer(Modifier.height(8.dp))

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            TextButton(onClick = { musicMgr.cyclePlayMode() }) {
                                Text(playMode.label, color = SheetGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            }
                            IconButton(onClick = { musicMgr.prevTrack() }) {
                                Icon(Icons.Default.SkipPrevious, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
                            }
                            Button(
                                onClick = { musicMgr.togglePlayPause() },
                                colors = ButtonDefaults.buttonColors(containerColor = SheetCrimson),
                                shape = CircleShape
                            ) {
                                Icon(
                                    if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = null,
                                    tint = Color.White
                                )
                            }
                            IconButton(onClick = { musicMgr.nextTrack() }) {
                                Icon(Icons.Default.SkipNext, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
                            }
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

                // Category Filter Tabs
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MusicCategoryFilter.values().forEach { cat ->
                        val sel = cat == selectedCat
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) SheetCrimson else SheetCardBg)
                                .border(1.dp, if (sel) SheetGold else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { musicMgr.selectCategory(cat) }
                                .padding(vertical = 6.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(cat.label, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

                // Track List
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    items(filteredList) { song ->
                        val isCur = song.trackNumber == currentTrack.trackNumber
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(if (isCur) SheetCrimson.copy(alpha = 0.35f) else SheetCardBg)
                                .border(1.dp, if (isCur) SheetGold else Color.White.copy(alpha = 0.08f), RoundedCornerShape(10.dp))
                                .clickable { musicMgr.playSong(song) }
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.weight(1f)) {
                                Text(
                                    String.format("%02d", song.trackNumber),
                                    color = SheetGold,
                                    fontWeight = FontWeight.Bold,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 12.sp
                                )
                                Column {
                                    Text(song.title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text("${song.artist} · ${song.album}", color = Color.LightGray, fontSize = 10.sp, maxLines = 1)
                                }
                            }
                            Text(song.durationFormatted, color = SheetCream, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                        }
                    }
                }
            }
        }
    }
}

// 2. RM-500HTT Album & Outfit Sheet Dialog
@Composable
fun RM500AlbumAndOutfitSheetDialog(
    initialTab: Int = 0,
    onDismiss: () -> Unit
) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val lang by manager.language.collectAsState()
    val currentOutfit by manager.arrowOutfit.collectAsState()
    val selectedChar by manager.selectedCharacter.collectAsState()
    val activeAllChar by manager.activeAllMemberChar.collectAsState()
    val navArrowBmp by manager.currentNavArrowBitmap.collectAsState()

    var selectedTab by remember { mutableStateOf(initialTab) }
    var selectedCGIndex by remember { mutableStateOf(1) }

    val episodeTitles = remember {
        listOf(
            "けいおん！ #1 廃部！", "けいおん！ #2 楽器！", "けいおん！ #3 特訓！", "けいおん！ #4 合宿！",
            "けいおん！ #5 顧問！", "けいおん！ #6 学園祭！", "けいおん！ #7 クリスマス！", "けいおん！ #8 新歓！",
            "けいおん！ #9 新入部員！", "けいおん！ #10 また合宿！", "けいおん！ #11 ピンチ！", "けいおん！ 最終回 軽音！",
            "けいおん！！ #1 高3！", "けいおん！！ #2 整頓！", "けいおん！！ #3 ドラマー！", "けいおん！！ #4 修学旅行！",
            "けいおん！！ #5 お留守番！", "けいおん！！ #6 梅雨！", "けいおん！！ #7 お茶会！", "けいおん！！ #8 進路！",
            "けいおん！！ #9 期末試験！", "けいおん！！ #10 先生！", "けいおん！！ #11 暑い！", "けいおん！！ #12 夏フェス！",
            "けいおん！！ #13 残暑見舞い！", "けいおん！！ #14 夏期講習！", "けいおん！！ #15 マラソン大会！", "けいおん！！ #16 先輩！",
            "けいおん！！ #17 部室がない！", "けいおん！！ #18 主役！", "けいおん！！ #19 ロミジュリ！", "けいおん！！ #20 またまた学園祭！",
            "けいおん！！ #21 卒業アルバム！", "けいおん！！ #22 受験！", "けいおん！！ #23 放課後！", "けいおん！！ 最終回 卒業式！"
        )
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
                .border(2.dp, SheetGold, RoundedCornerShape(18.dp)),
            color = SheetDarkBg
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(14.dp)) {
                // Top Segmented Tabs + Close
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(modifier = Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("导航车标换装", "RM-500HTT纪念相册", "作者与BUG反馈").forEachIndexed { idx, title ->
                            val sel = selectedTab == idx
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (sel) SheetCrimson else SheetCardBg)
                                    .border(1.dp, if (sel) SheetGold else Color.Transparent, RoundedCornerShape(8.dp))
                                    .clickable { selectedTab = idx }
                                    .padding(vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(title, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                            }
                        }
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                    }
                }

                Spacer(Modifier.height(10.dp))

                when (selectedTab) {
                    0 -> {
                        // Outfit Tab
                        Column(
                            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Card(
                                colors = CardDefaults.cardColors(containerColor = SheetCardBg),
                                shape = RoundedCornerShape(14.dp),
                                modifier = Modifier.fillMaxWidth().border(1.dp, SheetGold, RoundedCornerShape(14.dp))
                            ) {
                                Column(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Text("当前地图自车导航箭头与立绘预览", color = SheetGold, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    Spacer(Modifier.height(8.dp))
                                    Row(
                                        horizontalArrangement = Arrangement.spacedBy(24.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        if (navArrowBmp != null) {
                                            Image(
                                                bitmap = navArrowBmp!!.asImageBitmap(),
                                                contentDescription = null,
                                                filterQuality = FilterQuality.None,
                                                modifier = Modifier.size(90.dp, 115.dp)
                                            )
                                        }
                                        val stgBmp = remember(selectedChar, activeAllChar, currentOutfit) {
                                            app.assetDecryptor.getRM500StageIcon(selectedChar, activeAllChar, currentOutfit, 0)
                                        }
                                        if (stgBmp != null) {
                                            Image(
                                                bitmap = stgBmp.asImageBitmap(),
                                                contentDescription = null,
                                                modifier = Modifier.size(95.dp).clip(RoundedCornerShape(12.dp))
                                            )
                                        }
                                    }
                                    Spacer(Modifier.height(6.dp))
                                    Text(
                                        "${selectedChar.displayName(lang)} · ${currentOutfit.title(lang)}",
                                        color = Color.White,
                                        fontWeight = FontWeight.Black,
                                        fontSize = 14.sp
                                    )
                                }
                            }

                            Text("选择 RM-500HTT 官方角色车标造型：", color = SheetCream, fontSize = 12.sp, fontWeight = FontWeight.Bold)

                            RM500ArrowOutfit.values().forEach { outfit ->
                                val isSel = currentOutfit == outfit
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(if (isSel) SheetCrimson else SheetCardBg)
                                        .border(1.5.dp, if (isSel) SheetGold else Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                                        .clickable { manager.selectArrowOutfit(outfit) }
                                        .padding(horizontal = 14.dp, vertical = 10.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(outfit.title(lang), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                    if (isSel) {
                                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = SheetGold)
                                    }
                                }
                            }
                        }
                    }

                    1 -> {
                        // 36 Episode CG Album Tab
                        Column(
                            modifier = Modifier.fillMaxSize(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            val cgName = String.format("rm_cg_%02d", selectedCGIndex)
                            val cgBmp = remember(selectedCGIndex) {
                                app.assetDecryptor.getSpriteBitmap(cgName)
                            }
                            if (cgBmp != null) {
                                Image(
                                    bitmap = cgBmp.asImageBitmap(),
                                    contentDescription = null,
                                    contentScale = ContentScale.Fit,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(190.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .border(2.dp, SheetGold, RoundedCornerShape(12.dp))
                                )
                            }
                            Spacer(Modifier.height(6.dp))
                            Text(
                                episodeTitles.getOrElse(selectedCGIndex - 1) { "K-ON! CG #$selectedCGIndex" },
                                color = SheetGold,
                                fontWeight = FontWeight.Black,
                                fontSize = 13.sp
                            )
                            Spacer(Modifier.height(8.dp))

                            LazyVerticalGrid(
                                columns = GridCells.Adaptive(minSize = 64.dp),
                                modifier = Modifier.weight(1f),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                items((1..36).toList()) { idx ->
                                    val sel = idx == selectedCGIndex
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(if (sel) SheetCrimson else SheetCardBg)
                                            .border(1.dp, if (sel) SheetGold else Color.White.copy(alpha = 0.15f), RoundedCornerShape(8.dp))
                                            .clickable { selectedCGIndex = idx }
                                            .padding(vertical = 8.dp),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Text("#$idx", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }

                    2 -> {
                        // Author & P1/P2/P3/P4 Feedback Tab
                        AboutAndFeedbackContent(manager = manager)
                    }
                }
            }
        }
    }
}

// 3. About & P1/P2/P3/P4 QR Feedback View
data class SocialQRPlatform(
    val title: String,
    val accountLabel: String,
    val copyValue: String,
    val assetImageName: String,
    val appUri: String,
    val webUrl: String,
    val badgeColor: Color
)

@Composable
fun AboutAndFeedbackContent(manager: AudioPlayerManager) {
    val context = LocalContext.current
    val app = HTTNaviApp.instance
    var previewBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var previewTitle by remember { mutableStateOf("") }

    val platforms = remember {
        listOf(
            SocialQRPlatform(
                title = "抖音 (Douyin)",
                accountLabel = "不懂二次元的君殇 · 抖音号: 363314224",
                copyValue = "363314224",
                assetImageName = "qr_douyin_square.jpg",
                appUri = "snssdk1128://user/profile/94609777686",
                webUrl = "https://www.douyin.com",
                badgeColor = Color(0xFFFE2C55)
            ),
            SocialQRPlatform(
                title = "Instagram",
                accountLabel = "@tomy.au1015",
                copyValue = "tomy.au1015",
                assetImageName = "qr_instagram_square.jpg",
                appUri = "instagram://user?username=tomy.au1015",
                webUrl = "https://www.instagram.com/tomy.au1015",
                badgeColor = Color(0xFFE1306C)
            ),
            SocialQRPlatform(
                title = "哔哩哔哩 (Bilibili)",
                accountLabel = "小君殇 · UID: 239899475",
                copyValue = "239899475",
                assetImageName = "qr_bilibili_square.jpg",
                appUri = "bilibili://space/239899475",
                webUrl = "https://space.bilibili.com/239899475",
                badgeColor = Color(0xFFFB7299)
            ),
            SocialQRPlatform(
                title = "小红书 (Xiaohongshu)",
                accountLabel = "小君殇 · 小红书号: 638021380",
                copyValue = "638021380",
                assetImageName = "qr_xiaohongshu_square.jpg",
                appUri = "xhsdiscover://user/638021380",
                webUrl = "https://www.xiaohongshu.com",
                badgeColor = Color(0xFFFF2442)
            )
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // App Author Header
            Card(
                colors = CardDefaults.cardColors(containerColor = SheetCardBg),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.fillMaxWidth().border(1.dp, SheetGold, RoundedCornerShape(14.dp))
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text("放课后茶会伴侣 (HTT-NaviCompanion)", color = Color.White, fontWeight = FontWeight.Black, fontSize = 16.sp)
                    Spacer(Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "版本 v${manager.appVersion}",
                            color = SheetGold,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                        Text(
                            manager.appAuthorLabel(),
                            color = SheetCream,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .background(SheetCrimson, RoundedCornerShape(6.dp))
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                    Spacer(Modifier.height(4.dp))
                    Text("点击任意二维码图片可放大全屏预览，或点击按钮一键复制账号/跳转App", color = Color.LightGray, fontSize = 10.sp, textAlign = TextAlign.Center)
                }
            }

            // 4 QR Cards
            platforms.forEach { pf ->
                val bmp = remember(pf.assetImageName) {
                    app.assetDecryptor.getAssetBitmap(pf.assetImageName)
                }
                Card(
                    colors = CardDefaults.cardColors(containerColor = SheetCardBg),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().border(1.dp, pf.badgeColor.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        if (bmp != null) {
                            Image(
                                bitmap = bmp.asImageBitmap(),
                                contentDescription = pf.title,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(86.dp)
                                    .clip(RoundedCornerShape(10.dp))
                                    .border(1.5.dp, SheetGold, RoundedCornerShape(10.dp))
                                    .clickable {
                                        previewBitmap = bmp
                                        previewTitle = "${pf.title} · ${pf.accountLabel}"
                                    }
                            )
                        }
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(pf.title, color = pf.badgeColor, fontWeight = FontWeight.Black, fontSize = 14.sp)
                            Text(pf.accountLabel, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(
                                    onClick = {
                                        val cb = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                        cb.setPrimaryClip(ClipData.newPlainText("account", pf.copyValue))
                                        Toast.makeText(context, "已复制: ${pf.copyValue}", Toast.LENGTH_SHORT).show()
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.14f)),
                                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                                    shape = RoundedCornerShape(8.dp),
                                    modifier = Modifier.height(30.dp)
                                ) {
                                    Text("复制账号", color = SheetGold, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                                Button(
                                    onClick = {
                                        try {
                                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(pf.appUri)))
                                        } catch (_: Exception) {
                                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(pf.webUrl)))
                                        }
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = pf.badgeColor),
                                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                                    shape = RoundedCornerShape(8.dp),
                                    modifier = Modifier.height(30.dp)
                                ) {
                                    Text("打开App", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fullscreen QR Lightbox Overlay
        if (previewBitmap != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.88f))
                    .clickable { previewBitmap = null },
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(previewTitle, color = SheetGold, fontWeight = FontWeight.Black, fontSize = 14.sp)
                    Spacer(Modifier.height(10.dp))
                    Image(
                        bitmap = previewBitmap!!.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .size(260.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .border(2.dp, SheetGold, RoundedCornerShape(14.dp))
                    )
                    Spacer(Modifier.height(10.dp))
                    Text("点击任意空白处关闭预览", color = Color.LightGray, fontSize = 12.sp)
                }
            }
        }
    }
}

// 4. Destination Search & Route Sheet Dialog (Domestic Amap POI + 60+ Built-in Landmarks + Clipboard Smart Parse)
@Composable
fun DestinationSearchSheetDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val lang by manager.language.collectAsState()
    val travelMode by manager.travelMode.collectAsState()
    val onlineResults by manager.onlineSearchResults.collectAsState()
    val isSearching by manager.isSearchingPlaces.collectAsState()
    val userCoord by manager.userCoordinate.collectAsState()
    var queryText by remember { mutableStateOf("") }

    val builtInLandmarks = remember(userCoord) {
        com.tomy.httnavicompanion.data.MapAndRouteEngine.domesticLandmarksDatabase.map { item ->
            val dKm = com.tomy.httnavicompanion.data.CoordinateConverter.distanceMeters(userCoord, item.coordinate) / 1000.0
            item.copy(distanceKm = dKm)
        }.sortedBy { it.distanceKm }
    }

    val displayList = remember(queryText, onlineResults, builtInLandmarks) {
        val q = queryText.trim()
        if (q.isEmpty()) {
            builtInLandmarks
        } else {
            val localMatches = builtInLandmarks.filter {
                it.name.contains(q, ignoreCase = true) ||
                    it.address.contains(q, ignoreCase = true) ||
                    it.category.contains(q, ignoreCase = true)
            }
            val merged = ArrayList<PlaceSearchItem>()
            val seen = HashSet<String>()
            (localMatches + onlineResults).forEach { item ->
                if (seen.add(item.name.lowercase())) {
                    merged.add(item)
                }
            }
            merged
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
                .border(2.dp, SheetGold, RoundedCornerShape(18.dp)),
            color = SheetDarkBg
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(14.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("目的地搜索与真实路口导航 (适配国内高德)", color = SheetCream, fontSize = 15.sp, fontWeight = FontWeight.Black)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                    }
                }

                // Travel Mode Switcher
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    NavigationTravelMode.values().forEach { mode ->
                        val sel = mode == travelMode
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) SheetCrimson else SheetCardBg)
                                .border(1.dp, if (sel) SheetGold else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { manager.setTravelMode(mode) }
                                .padding(vertical = 7.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(mode.title(lang), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                Spacer(Modifier.height(6.dp))

                // One-Click Clipboard Smart Address Recognition Bar (matches iOS v1.6.3!)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFF1976D2).copy(alpha = 0.22f))
                        .border(1.dp, Color(0xFF64B5F6).copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                        .clickable {
                            val cb = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            val clipText = cb.primaryClip?.getItemAt(0)?.text?.toString()?.trim() ?: ""
                            if (clipText.isNotEmpty()) {
                                queryText = clipText
                                manager.performOnlineSearch(clipText)
                                Toast.makeText(context, "已粘贴剪贴板地址: $clipText", Toast.LENGTH_SHORT).show()
                            } else {
                                Toast.makeText(context, "剪贴板为空，请先复制地址或地点名称", Toast.LENGTH_SHORT).show()
                            }
                        }
                        .padding(horizontal = 10.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("📋 一键识别剪贴板复制的地址 / 分享地名并搜索", color = Color(0xFF64B5F6), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    Text("点按粘贴 >", color = SheetGold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }

                Spacer(Modifier.height(6.dp))

                OutlinedTextField(
                    value = queryText,
                    onValueChange = {
                        queryText = it
                        if (it.trim().isNotEmpty()) {
                            manager.performOnlineSearch(it)
                        }
                    },
                    placeholder = { Text("输入目的地 (如：广州南站、罗湖口岸、万象城、华强北)...", color = Color.Gray, fontSize = 12.sp) },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedBorderColor = SheetGold,
                        unfocusedBorderColor = Color.Gray,
                        cursorColor = SheetGold
                    ),
                    trailingIcon = {
                        if (isSearching) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), color = SheetGold, strokeWidth = 2.dp)
                        } else if (queryText.isNotEmpty()) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                TextButton(onClick = { manager.performOnlineSearch(queryText) }) {
                                    Text("搜索", color = SheetGold, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(Modifier.height(6.dp))

                // Quick City/Hot Tag Chips for 1-Tap Search
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                    items(listOf("罗湖口岸", "福田口岸", "深圳北站", "万象城", "华强北", "广州南站", "松山湖", "旺角信和", "西九龙", "轻音部圣地")) { tag ->
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color.White.copy(alpha = 0.1f))
                                .clickable {
                                    queryText = tag
                                    manager.performOnlineSearch(tag)
                                }
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                        ) {
                            Text(tag, color = SheetGold, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    items(displayList) { item ->
                        Card(
                            colors = CardDefaults.cardColors(containerColor = SheetCardBg),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .border(1.dp, SheetGold.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
                                .clickable {
                                    manager.startRouteToPlace(item.name, item.coordinate)
                                    onDismiss()
                                }
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(11.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Text(item.name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(4.dp))
                                                .background(SheetCrimson.copy(alpha = 0.5f))
                                                .padding(horizontal = 5.dp, vertical = 1.dp)
                                        ) {
                                            Text(item.category, color = SheetGold, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                    Spacer(Modifier.height(2.dp))
                                    Text(
                                        "${String.format("%.1f km", item.distanceKm)} · ${item.address}",
                                        color = Color.LightGray,
                                        fontSize = 11.sp,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                                Spacer(Modifier.width(8.dp))
                                Button(
                                    onClick = {
                                        manager.startRouteToPlace(item.name, item.coordinate)
                                        onDismiss()
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = SheetCrimson),
                                    shape = RoundedCornerShape(8.dp),
                                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text("去这里", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// 5. Soundboard 984 Original Voice Sheet Dialog
@Composable
fun SoundboardSheetDialog(onDismiss: () -> Unit) {
    val app = HTTNaviApp.instance
    val manager = app.audioPlayerManager
    val lang by manager.language.collectAsState()
    val currentPlayingId by manager.currentPlayingId.collectAsState()
    var selectedSection by remember { mutableStateOf(0) }

    val sections = remember(lang) {
        listOf(
            Pair("${CharacterFilter.YUI.displayName(lang)} (192)", CharacterFilter.YUI.verifiedVoiceIds),
            Pair("${CharacterFilter.MIO.displayName(lang)} (192)", CharacterFilter.MIO.verifiedVoiceIds),
            Pair("${CharacterFilter.RITSU.displayName(lang)} (192)", CharacterFilter.RITSU.verifiedVoiceIds),
            Pair("${CharacterFilter.MUGI.displayName(lang)} (192)", CharacterFilter.MUGI.verifiedVoiceIds),
            Pair("${CharacterFilter.AZUSA.displayName(lang)} (192)", CharacterFilter.AZUSA.verifiedVoiceIds),
            Pair("全员生日与纪念彩蛋 (11)", (1112..1122).toList())
        )
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.88f)
                .clip(RoundedCornerShape(18.dp))
                .border(2.dp, SheetGold, RoundedCornerShape(18.dp)),
            color = SheetDarkBg
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(14.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("RM-500HTT 全角色 984 句原声鉴赏", color = SheetCream, fontSize = 16.sp, fontWeight = FontWeight.Black)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = null, tint = Color.White)
                    }
                }

                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(vertical = 8.dp)) {
                    items(sections.indices.toList()) { idx ->
                        val sel = idx == selectedSection
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (sel) SheetCrimson else SheetCardBg)
                                .border(1.dp, if (sel) SheetGold else Color.Transparent, RoundedCornerShape(8.dp))
                                .clickable { selectedSection = idx }
                                .padding(horizontal = 12.dp, vertical = 6.dp)
                        ) {
                            Text(sections[idx].first, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    items(sections[selectedSection].second) { vid ->
                        val isCur = currentPlayingId == vid
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(if (isCur) SheetCrimson.copy(alpha = 0.4f) else SheetCardBg)
                                .border(1.dp, if (isCur) SheetGold else Color.White.copy(alpha = 0.08f), RoundedCornerShape(10.dp))
                                .clickable { manager.playVoice(vid) }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                "[${manager.characterForVoiceId(vid).displayName(lang)}] 原声语音 #$vid",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 13.sp
                            )
                            Icon(
                                if (isCur) Icons.Default.VolumeUp else Icons.Default.PlayCircleFilled,
                                contentDescription = null,
                                tint = SheetGold
                            )
                        }
                    }
                }
            }
        }
    }
}
