package com.tomy.httnavicompanion.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

enum class MusicCategoryFilter(val label: String) {
    ALL("全部"),
    READY("已就绪"),
    OPED("OP/ED"),
    INSERT("剧中歌"),
    CHARACTER("角色歌")
}

enum class MusicPlayMode(val label: String) {
    LOOP_ALL("列表循环"),
    LOOP_SINGLE("单曲循环"),
    SHUFFLE("随机播放")
}

data class KOnSongItem(
    val trackNumber: Int,
    val title: String,
    val titleRomaji: String,
    val artist: String,
    val album: String,
    val category: MusicCategoryFilter,
    val vocalistChar: String,
    val durationFormatted: String,
    val approxDurationSeconds: Int,
    var encryptedOffset: Int = -1,
    var encryptedLength: Int = 0,
    var rawFilename: String = "",
    var localFilePath: String? = null,
    var isCustomImport: Boolean = false
) {
    val isAvailable: Boolean
        get() = encryptedOffset >= 0 || localFilePath != null
}

class KOnMusicManager(private val context: Context) {
    private val TAG = "KOnMusicManager"
    private val xorKey = "K-On!AfterSchoolTeaTimeNavi2026".toByteArray(Charsets.UTF_8)

    private var mediaPlayer: MediaPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var containerPayloadOffset: Long = 0L
    private var containerAssetPath: String? = null
    private var containerLocalFile: File? = null

    val musicImportDir: File
        get() = File(context.filesDir, "Music").apply { if (!exists()) mkdirs() }

    private val _playlist = MutableStateFlow(canonicalSongs())
    val playlist: StateFlow<List<KOnSongItem>> = _playlist

    private val _currentTrack = MutableStateFlow(_playlist.value.first())
    val currentTrack: StateFlow<KOnSongItem> = _currentTrack

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    private val _currentTimeSec = MutableStateFlow(0)
    val currentTimeSec: StateFlow<Int> = _currentTimeSec

    private val _durationSec = MutableStateFlow(250)
    val durationSec: StateFlow<Int> = _durationSec

    private val _playMode = MutableStateFlow(MusicPlayMode.LOOP_ALL)
    val playMode: StateFlow<MusicPlayMode> = _playMode

    private val _selectedCategory = MutableStateFlow(MusicCategoryFilter.ALL)
    val selectedCategory: StateFlow<MusicCategoryFilter> = _selectedCategory

    private val _libraryStatusMessage = MutableStateFlow("轻音音乐馆 · 支持内置曲库与本地导入音乐")
    val libraryStatusMessage: StateFlow<String> = _libraryStatusMessage

    private var baseVolume = 0.85f
    private var isDucked = false

    init {
        Thread {
            scanAndLoadLibrary()
        }.start()
        startProgressTimer()
    }

    private fun startProgressTimer() {
        val runnable = object : Runnable {
            override fun run() {
                try {
                    val mp = mediaPlayer
                    if (mp != null && _isPlaying.value && mp.isPlaying) {
                        _currentTimeSec.value = mp.currentPosition / 1000
                        val dur = mp.duration / 1000
                        if (dur > 0) _durationSec.value = dur
                    }
                } catch (_: Exception) {}
                mainHandler.postDelayed(this, 500L)
            }
        }
        mainHandler.post(runnable)
    }

    private fun matchesCanonicalSong(song: KOnSongItem, lowerFilename: String): Boolean {
        val t = song.title.lowercase()
        val r = song.titleRomaji.lowercase()
        return lowerFilename.contains(t) || lowerFilename.contains(r) ||
            (t.contains("cagayake") && lowerFilename.contains("cagayake")) ||
            (t.contains("lazy") && lowerFilename.contains("lazy")) ||
            (t.contains("maniac") && lowerFilename.contains("maniac")) ||
            (t.contains("listen") && lowerFilename.contains("listen")) ||
            (t.contains("miracle") && lowerFilename.contains("miracle")) ||
            (t.contains("thank") && lowerFilename.contains("thank")) ||
            (t.contains("singing") && lowerFilename.contains("singing")) ||
            (t.contains("endless") && lowerFilename.contains("endless")) ||
            (t.contains("fuwa") && (lowerFilename.contains("fuwa") || lowerFilename.contains("ふわふわ") || lowerFilename.contains("滑滑"))) ||
            (t.contains("u&i") && (lowerFilename.contains("u&i") || lowerFilename.contains("u and i"))) ||
            (t.contains("天使") && lowerFilename.contains("天使")) ||
            (t.contains("ホッチキス") && (lowerFilename.contains("ホッチキス") || lowerFilename.contains("stapler") || lowerFilename.contains("订书机"))) ||
            (t.contains("ふでペン") && (lowerFilename.contains("ふでペン") || lowerFilename.contains("fude") || lowerFilename.contains("圆珠笔"))) ||
            (t.contains("ぴゅあ") && (lowerFilename.contains("ぴゅあ") || lowerFilename.contains("pure"))) ||
            (t.contains("ごはん") && (lowerFilename.contains("ごはん") || lowerFilename.contains("gohan") || lowerFilename.contains("米饭")))
    }

    fun scanAndLoadLibrary() {
        val updatedList = canonicalSongs().map { it.copy() }.toMutableList()
        var matchedCount = 0

        // 1. Check encrypted music_assets.dat in assets or imported Music folder
        val importedDat = File(musicImportDir, "music_assets.dat")
        if (importedDat.exists()) {
            try {
                FileInputStream(importedDat).use { stream ->
                    if (parseEncryptedContainerHeader(stream, updatedList)) {
                        containerLocalFile = importedDat
                        containerAssetPath = null
                    }
                }
            } catch (_: Exception) {}
        } else {
            val pathsToTry = listOf("music_assets.dat", "Music/music_assets.dat")
            for (path in pathsToTry) {
                var loadedFromAsset = false
                try {
                    context.assets.open(path).use { stream ->
                        if (parseEncryptedContainerHeader(stream, updatedList)) {
                            containerAssetPath = path
                            containerLocalFile = null
                            loadedFromAsset = true
                        }
                    }
                } catch (_: Exception) {}
                if (loadedFromAsset) break
            }
        }

        // 2. Scan user-imported audio files in filesDir/Music
        val audioExts = setOf("mp3", "m4a", "mp4", "m4b", "m4r", "flac", "wav", "aac", "ogg", "caf", "aiff")
        val localFiles = musicImportDir.listFiles()?.filter {
            it.isFile && audioExts.contains(it.extension.lowercase())
        }?.sortedBy { it.name } ?: emptyList()

        val usedFiles = HashSet<String>()
        for (song in updatedList) {
            val match = localFiles.firstOrNull { file ->
                !usedFiles.contains(file.absolutePath) && matchesCanonicalSong(song, file.nameWithoutExtension.lowercase())
            }
            if (match != null) {
                song.localFilePath = match.absolutePath
                usedFiles.add(match.absolutePath)
            }
        }

        // Append extra custom imported songs not in canonical 27 list
        for (file in localFiles) {
            if (usedFiles.contains(file.absolutePath)) continue
            val cleanTitle = file.nameWithoutExtension
            var durSecs = 240
            var durFmt = "04:00"
            try {
                val mmr = MediaMetadataRetriever()
                mmr.setDataSource(file.absolutePath)
                val durStr = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                mmr.release()
                val ms = durStr?.toLongOrNull() ?: 0L
                if (ms > 0L) {
                    durSecs = (ms / 1000L).toInt()
                    durFmt = String.format("%02d:%02d", durSecs / 60, durSecs % 60)
                }
            } catch (_: Exception) {}

            updatedList.add(
                KOnSongItem(
                    trackNumber = updatedList.size + 1,
                    title = cleanTitle,
                    titleRomaji = cleanTitle,
                    artist = "放课后茶会 / 本地导入",
                    album = "轻音少女导入曲库",
                    category = MusicCategoryFilter.INSERT,
                    vocalistChar = "放课后茶会",
                    durationFormatted = durFmt,
                    approxDurationSeconds = durSecs,
                    localFilePath = file.absolutePath,
                    isCustomImport = true
                )
            )
        }

        matchedCount = updatedList.count { it.isAvailable }
        mainHandler.post {
            _playlist.value = updatedList
            val firstAvail = updatedList.firstOrNull { it.isAvailable } ?: updatedList.first()
            if (!_isPlaying.value) {
                _currentTrack.value = firstAvail
                _durationSec.value = firstAvail.approxDurationSeconds
            }
            _libraryStatusMessage.value = if (matchedCount > 0) {
                "轻音音乐库已载入 $matchedCount 首可播放曲目 (支持「导入音乐」添加)"
            } else {
                "27首名曲索引已就绪 · 请点击右上角「导入音乐」放入音频文件"
            }
        }
    }

    private fun parseEncryptedContainerHeader(
        stream: java.io.InputStream,
        updatedList: MutableList<KOnSongItem>
    ): Boolean {
        val headerBuf = ByteArray(16384)
        val readBytes = stream.read(headerBuf)
        if (readBytes <= 0) return false
        val text = String(headerBuf, 0, readBytes, Charsets.ISO_8859_1)
        if (!text.startsWith("KON_ENC_MUSIC_V1\n")) return false

        val marker = "\nHEADER_END\n"
        val markerIdx = text.indexOf(marker)
        if (markerIdx == -1) return false

        val jsonStrBytes = headerBuf.copyOfRange("KON_ENC_MUSIC_V1\n".length, markerIdx)
        val jsonStr = String(jsonStrBytes, Charsets.UTF_8)
        containerPayloadOffset = (markerIdx + marker.length).toLong()

        val arr = JSONArray(jsonStr)
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val fname = obj.getString("filename")
            val off = obj.getInt("offset")
            val len = obj.getInt("length")
            val lower = fname.lowercase()

            val matchIdx = updatedList.indexOfFirst { song -> matchesCanonicalSong(song, lower) }
            if (matchIdx != -1) {
                updatedList[matchIdx].encryptedOffset = off
                updatedList[matchIdx].encryptedLength = len
                updatedList[matchIdx].rawFilename = fname
            } else {
                val cleanTitle = fname.substringBeforeLast(".")
                updatedList.add(
                    KOnSongItem(
                        trackNumber = updatedList.size + 1,
                        title = cleanTitle,
                        titleRomaji = cleanTitle,
                        artist = "放課後ティータイム",
                        album = "放课后茶会 独立音乐馆",
                        category = MusicCategoryFilter.INSERT,
                        vocalistChar = "放課後ティータイム",
                        durationFormatted = "04:00",
                        approxDurationSeconds = 240,
                        encryptedOffset = off,
                        encryptedLength = len,
                        rawFilename = fname
                    )
                )
            }
        }
        return true
    }

    fun importAudioUris(uris: List<Uri>) {
        if (uris.isEmpty()) return
        Thread {
            var importedCount = 0
            val dir = musicImportDir
            for (uri in uris) {
                try {
                    var displayName = "kon_track_${System.currentTimeMillis()}.mp3"
                    context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0 && cursor.moveToFirst()) {
                            val n = cursor.getString(nameIdx)
                            if (!n.isNullOrBlank()) displayName = n
                        }
                    }
                    val destFile = File(dir, displayName)
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(destFile).use { output ->
                            input.copyTo(output)
                        }
                        importedCount++
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed importing audio uri $uri", e)
                }
            }
            scanAndLoadLibrary()
            mainHandler.post {
                _libraryStatusMessage.value = if (importedCount > 0) {
                    "✅ 成功导入 $importedCount 首轻音音乐！"
                } else {
                    "⚠️ 导入失败，请检查文件权限或格式"
                }
            }
        }.start()
    }

    fun deleteSongFile(song: KOnSongItem) {
        val path = song.localFilePath ?: return
        if (_currentTrack.value.trackNumber == song.trackNumber && _isPlaying.value) {
            try { mediaPlayer?.stop() } catch (_: Exception) {}
            _isPlaying.value = false
        }
        try {
            File(path).delete()
        } catch (_: Exception) {}
        Thread {
            scanAndLoadLibrary()
            mainHandler.post {
                _libraryStatusMessage.value = "已移除本地导入歌曲: ${song.title}"
            }
        }.start()
    }

    fun selectCategory(cat: MusicCategoryFilter) {
        _selectedCategory.value = cat
    }

    fun cyclePlayMode() {
        val all = MusicPlayMode.values()
        _playMode.value = all[(_playMode.value.ordinal + 1) % all.size]
    }

    fun seekToFraction(fraction: Float) {
        val mp = mediaPlayer ?: return
        try {
            val durMs = mp.duration
            if (durMs > 0) {
                val targetMs = (durMs * fraction.coerceIn(0f, 1f)).toInt()
                mp.seekTo(targetMs)
                _currentTimeSec.value = targetMs / 1000
            }
        } catch (_: Exception) {}
    }

    fun togglePlayPause() {
        val mp = mediaPlayer
        if (_isPlaying.value && mp != null) {
            try {
                mp.pause()
            } catch (_: Exception) {}
            _isPlaying.value = false
        } else if (mp != null && !_isPlaying.value) {
            try {
                mp.start()
                _isPlaying.value = true
            } catch (_: Exception) {
                playSong(_currentTrack.value)
            }
        } else {
            playSong(_currentTrack.value)
        }
    }

    fun playSong(song: KOnSongItem) {
        _currentTrack.value = song
        _currentTimeSec.value = 0
        _durationSec.value = song.approxDurationSeconds

        // 1. Play local imported file if present
        val localPath = song.localFilePath
        if (localPath != null && File(localPath).exists()) {
            try {
                mediaPlayer?.release()
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(localPath)
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    val vol = if (isDucked) 0.18f else baseVolume
                    setVolume(vol, vol)
                    setOnCompletionListener { onTrackEnded() }
                    prepare()
                    start()
                }
                _isPlaying.value = true
                val realDur = (mediaPlayer?.duration ?: 0) / 1000
                if (realDur > 0) _durationSec.value = realDur
                _libraryStatusMessage.value = "正在播放: ${song.title}"
                return
            } catch (e: Exception) {
                Log.e(TAG, "Error playing local file $localPath", e)
            }
        }

        // 2. Play from encrypted container (assets or imported music_assets.dat)
        val cPath = containerAssetPath
        val cFile = containerLocalFile
        if ((cPath == null && cFile == null) || song.encryptedOffset < 0) {
            val avail = _playlist.value.firstOrNull { it.isAvailable }
            if (avail != null && avail.trackNumber != song.trackNumber) {
                playSong(avail)
            } else {
                _isPlaying.value = false
                _libraryStatusMessage.value = "【${song.title}】尚未导入音频文件，请点击右上角「导入音乐」放入歌曲"
            }
            return
        }

        Thread {
            try {
                val inputStream = if (cFile != null && cFile.exists()) {
                    FileInputStream(cFile)
                } else {
                    context.assets.open(cPath!!)
                }
                inputStream.use { stream ->
                    var toSkip = containerPayloadOffset + song.encryptedOffset.toLong()
                    while (toSkip > 0) {
                        val s = stream.skip(toSkip)
                        if (s <= 0) break
                        toSkip -= s
                    }
                    val buf = ByteArray(song.encryptedLength)
                    var readTotal = 0
                    while (readTotal < buf.size) {
                        val r = stream.read(buf, readTotal, buf.size - readTotal)
                        if (r == -1) break
                        readTotal += r
                    }
                    for (i in buf.indices) {
                        buf[i] = (buf[i].toInt() xor xorKey[i % xorKey.size].toInt()).toByte()
                    }
                    val ext = song.rawFilename.substringAfterLast(".", "mp3")
                    val tempFile = File.createTempFile("kon_music_", ".$ext", context.cacheDir)
                    FileOutputStream(tempFile).use { it.write(buf) }

                    mainHandler.post {
                        try {
                            mediaPlayer?.release()
                            mediaPlayer = MediaPlayer().apply {
                                setDataSource(tempFile.absolutePath)
                                setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                        .build()
                                )
                                val vol = if (isDucked) 0.18f else baseVolume
                                setVolume(vol, vol)
                                setOnCompletionListener {
                                    tempFile.delete()
                                    onTrackEnded()
                                }
                                prepare()
                                start()
                            }
                            _isPlaying.value = true
                            val realDur = (mediaPlayer?.duration ?: 0) / 1000
                            if (realDur > 0) _durationSec.value = realDur
                            _libraryStatusMessage.value = "正在播放: ${song.title}"
                        } catch (e: Exception) {
                            Log.e(TAG, "Playback error", e)
                            _isPlaying.value = false
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Decrypt music error", e)
            }
        }.start()
    }

    private fun onTrackEnded() {
        when (_playMode.value) {
            MusicPlayMode.LOOP_SINGLE -> playSong(_currentTrack.value)
            MusicPlayMode.SHUFFLE -> {
                val avail = _playlist.value.filter { it.isAvailable }.ifEmpty { _playlist.value }
                playSong(avail.random())
            }
            MusicPlayMode.LOOP_ALL -> nextTrack()
        }
    }

    fun nextTrack() {
        val list = _playlist.value.filter { it.isAvailable }.ifEmpty { _playlist.value }
        val idx = list.indexOfFirst { it.trackNumber == _currentTrack.value.trackNumber }
        val next = list[(idx + 1) % list.size]
        playSong(next)
    }

    fun prevTrack() {
        val list = _playlist.value.filter { it.isAvailable }.ifEmpty { _playlist.value }
        val idx = list.indexOfFirst { it.trackNumber == _currentTrack.value.trackNumber }
        val prev = list[if (idx - 1 < 0) list.lastIndex else idx - 1]
        playSong(prev)
    }

    fun duckForVoice(duck: Boolean) {
        isDucked = duck
        val targetVol = if (duck) 0.16f else baseVolume
        try {
            mediaPlayer?.setVolume(targetVol, targetVol)
        } catch (_: Exception) {}
    }

    companion object {
        fun canonicalSongs(): List<KOnSongItem> = listOf(
            KOnSongItem(1, "Cagayake! GIRLS", "Cagayake! GIRLS", "放课后茶会 / 平泽唯", "K-ON! 1st Season OP", MusicCategoryFilter.OPED, "平泽唯", "04:10", 250),
            KOnSongItem(2, "Don't say \"lazy\"", "Don't say lazy", "放课后茶会 / 秋山澪", "K-ON! 1st Season ED", MusicCategoryFilter.OPED, "秋山澪", "04:24", 264),
            KOnSongItem(3, "GO! GO! MANIAC", "GO! GO! MANIAC", "放课后茶会 / 平泽唯", "K-ON!! 2nd Season OP1", MusicCategoryFilter.OPED, "平泽唯", "04:11", 251),
            KOnSongItem(4, "Listen!!", "Listen!!", "放课后茶会 / 秋山澪", "K-ON!! 2nd Season ED1", MusicCategoryFilter.OPED, "秋山澪", "03:47", 227),
            KOnSongItem(5, "Utauyo!!MIRACLE", "Utauyo!! MIRACLE", "放课后茶会 / 平泽唯", "K-ON!! 2nd Season OP2", MusicCategoryFilter.OPED, "平泽唯", "04:02", 242),
            KOnSongItem(6, "NO,Thank You!", "NO, Thank You!", "放课后茶会 / 秋山澪", "K-ON!! 2nd Season ED2", MusicCategoryFilter.OPED, "秋山澪", "04:17", 257),
            KOnSongItem(7, "Singing!", "Singing!", "放课后茶会 / 秋山澪", "K-ON! 剧场版 ED", MusicCategoryFilter.OPED, "秋山澪", "03:54", 234),
            KOnSongItem(8, "Unmei♪wa♪Endless!", "Unmei wa Endless!", "放课后茶会 / 平泽唯", "K-ON! 剧场版 OP", MusicCategoryFilter.OPED, "平泽唯", "03:52", 232),
            KOnSongItem(9, "ふわふわ時間 (Fuwa Fuwa Time)", "Fuwa Fuwa Time", "放课后茶会 / 秋山澪·平泽唯", "放课后茶会 经典舞台曲", MusicCategoryFilter.INSERT, "放课后茶会", "03:59", 239),
            KOnSongItem(10, "わたしの恋はホッチキス", "Watashi no Koi wa Hotchkiss", "放课后茶会 / 平泽唯·秋山澪", "放课后茶会 I", MusicCategoryFilter.INSERT, "平泽唯·秋山澪", "04:24", 264),
            KOnSongItem(11, "ふでペン 〜ボールペン〜", "Fude Pen Ballpoint Pen", "放课后茶会 / 秋山澪·平泽唯", "放课后茶会 I", MusicCategoryFilter.INSERT, "秋山澪", "03:58", 238),
            KOnSongItem(12, "ぴゅあぴゅあはーと (Pure Pure Heart)", "Pure Pure Heart", "放课后茶会 / 秋山澪", "放课后茶会 II", MusicCategoryFilter.INSERT, "秋山澪", "04:35", 275),
            KOnSongItem(13, "ごはんはおかず (米饭是小菜)", "Gohan wa Okazu", "放课后茶会 / 平泽唯", "放课后茶会 II", MusicCategoryFilter.INSERT, "平泽唯", "03:12", 192),
            KOnSongItem(14, "U&I", "U and I", "放课后茶会 / 平泽唯", "放课后茶会 II (献给忧)", MusicCategoryFilter.INSERT, "平泽唯", "04:36", 276),
            KOnSongItem(15, "天使にふれたよ! (相遇天使)", "Tenshi ni Fureta yo!", "放课后茶会 (毕业赠歌)", "放课后茶会 II 最终话", MusicCategoryFilter.INSERT, "放课后茶会四人", "04:42", 282),
            KOnSongItem(16, "カレーのちライス", "Curry Nochi Rice", "放课后茶会 / 平泽唯", "放课后茶会 I", MusicCategoryFilter.INSERT, "平泽唯", "03:16", 196),
            KOnSongItem(17, "いちばんいっぱい", "Ichiban Ippai", "平泽唯", "K-ON! 剧场版 主题曲", MusicCategoryFilter.INSERT, "平泽唯", "03:10", 190),
            KOnSongItem(18, "ギー太に首ったけ", "Giita ni Kubittake", "平泽唯 (CV: 丰崎爱生)", "平泽唯 Character Single", MusicCategoryFilter.CHARACTER, "平泽唯", "03:33", 213),
            KOnSongItem(19, "Sunday Siesta", "Sunday Siesta", "平泽唯 (CV: 丰崎爱生)", "平泽唯 Character Single", MusicCategoryFilter.CHARACTER, "平泽唯", "03:38", 218),
            KOnSongItem(20, "Heart Goes Boom!!", "Heart Goes Boom!!", "秋山澪 (CV: 日笠阳子)", "秋山澪 Character Single", MusicCategoryFilter.CHARACTER, "秋山澪", "03:56", 236),
            KOnSongItem(21, "Hello Little Girl", "Hello Little Girl", "秋山澪 (CV: 日笠阳子)", "秋山澪 Character Single", MusicCategoryFilter.CHARACTER, "秋山澪", "04:42", 282),
            KOnSongItem(22, "Girly Storm 疾走 Style", "Girly Storm Shissou Style", "田井中律 (CV: 佐藤聪美)", "田井中律 Character Single", MusicCategoryFilter.CHARACTER, "田井中律", "03:52", 232),
            KOnSongItem(23, "目指せハッピー100%↑↑↑", "Mezase Happy 100%", "田井中律 (CV: 佐藤聪美)", "田井中律 Character Single", MusicCategoryFilter.CHARACTER, "田井中律", "03:17", 197),
            KOnSongItem(24, "Dear My Keys 〜鍵盤の魔法〜", "Dear My Keys", "琴吹紬 (CV: 寿美菜子)", "琴吹紬 Character Single", MusicCategoryFilter.CHARACTER, "琴吹紬", "04:39", 279),
            KOnSongItem(25, "Humming Bird", "Humming Bird", "琴吹紬 (CV: 寿美菜子)", "琴吹紬 Character Single", MusicCategoryFilter.CHARACTER, "琴吹紬", "03:48", 228),
            KOnSongItem(26, "じゃじゃ馬Way To Go", "Jajauma Way To Go", "中野梓 (CV: 竹达彩奈)", "中野梓 Character Single", MusicCategoryFilter.CHARACTER, "中野梓", "04:29", 269),
            KOnSongItem(27, "私は私の道を行く", "Watashi wa Watashi no Michi wo Yuku", "中野梓 (CV: 竹达彩奈)", "中野梓 Character Single", MusicCategoryFilter.CHARACTER, "中野梓", "03:18", 198)
        )
    }
}
