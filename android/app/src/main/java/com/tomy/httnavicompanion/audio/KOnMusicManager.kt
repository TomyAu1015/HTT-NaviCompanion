package com.tomy.httnavicompanion.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream

enum class MusicCategoryFilter(val label: String) {
    ALL("全部"),
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
    var rawFilename: String = ""
) {
    val isAvailable: Boolean
        get() = encryptedOffset >= 0
}

class KOnMusicManager(private val context: Context) {
    private val TAG = "KOnMusicManager"
    private val xorKey = "K-On!AfterSchoolTeaTimeNavi2026".toByteArray(Charsets.UTF_8)

    private var mediaPlayer: MediaPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var containerPayloadOffset: Long = 0L
    private var containerAssetPath: String? = null

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

    private val _libraryStatusMessage = MutableStateFlow("轻音音乐馆 · 27首名曲曲库已就绪")
    val libraryStatusMessage: StateFlow<String> = _libraryStatusMessage

    private var baseVolume = 0.85f
    private var isDucked = false

    init {
        Thread {
            scanAndLoadEncryptedContainer()
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

    private fun scanAndLoadEncryptedContainer() {
        val pathsToTry = listOf("music_assets.dat", "Music/music_assets.dat")
        for (path in pathsToTry) {
            try {
                context.assets.open(path).use { stream ->
                    // Read first 16KB to locate HEADER_END
                    val headerBuf = ByteArray(16384)
                    val readBytes = stream.read(headerBuf)
                    if (readBytes <= 0) return@use
                    val text = String(headerBuf, 0, readBytes, Charsets.ISO_8859_1)
                    if (!text.startsWith("KON_ENC_MUSIC_V1\n")) return@use

                    val marker = "\nHEADER_END\n"
                    val markerIdx = text.indexOf(marker)
                    if (markerIdx == -1) return@use

                    val jsonStrBytes = headerBuf.copyOfRange("KON_ENC_MUSIC_V1\n".length, markerIdx)
                    val jsonStr = String(jsonStrBytes, Charsets.UTF_8)
                    containerPayloadOffset = (markerIdx + marker.length).toLong()
                    containerAssetPath = path

                    val arr = JSONArray(jsonStr)
                    val updatedList = _playlist.value.map { it.copy() }.toMutableList()
                    var matchedCount = 0

                    for (i in 0 until arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val fname = obj.getString("filename")
                        val off = obj.getInt("offset")
                        val len = obj.getInt("length")
                        val lower = fname.lowercase()

                        val matchIdx = updatedList.indexOfFirst { song ->
                            val t = song.title.lowercase()
                            val r = song.titleRomaji.lowercase()
                            lower.contains(t) || lower.contains(r) ||
                                (t.contains("cagayake") && lower.contains("cagayake")) ||
                                (t.contains("lazy") && lower.contains("lazy")) ||
                                (t.contains("maniac") && lower.contains("maniac")) ||
                                (t.contains("listen") && lower.contains("listen")) ||
                                (t.contains("miracle") && lower.contains("miracle")) ||
                                (t.contains("thank") && lower.contains("thank")) ||
                                (t.contains("singing") && lower.contains("singing")) ||
                                (t.contains("endless") && lower.contains("endless")) ||
                                (t.contains("fuwa") && (lower.contains("fuwa") || lower.contains("ふわふわ") || lower.contains("滑滑"))) ||
                                (t.contains("u&i") && (lower.contains("u&i") || lower.contains("u and i"))) ||
                                (t.contains("天使") && lower.contains("天使")) ||
                                (t.contains("ホッチキス") && (lower.contains("ホッチキス") || lower.contains("stapler") || lower.contains("订书机"))) ||
                                (t.contains("ふでペン") && (lower.contains("ふでペン") || lower.contains("fude") || lower.contains("圆珠笔"))) ||
                                (t.contains("ぴゅあ") && (lower.contains("ぴゅあ") || lower.contains("pure"))) ||
                                (t.contains("ごはん") && (lower.contains("ごはん") || lower.contains("gohan") || lower.contains("米饭")))
                        }

                        if (matchIdx != -1) {
                            updatedList[matchIdx].encryptedOffset = off
                            updatedList[matchIdx].encryptedLength = len
                            updatedList[matchIdx].rawFilename = fname
                            matchedCount++
                        } else {
                            // Add as extra track
                            val cleanTitle = fname.substringBeforeLast(".")
                            updatedList.add(
                                KOnSongItem(
                                    trackNumber = updatedList.size + 1,
                                    title = cleanTitle,
                                    titleRomaji = cleanTitle,
                                    artist = "放課後ティータイム",
                                    album = "K-ON! 原声曲库",
                                    category = MusicCategoryFilter.INSERT,
                                    vocalistChar = "放課後ティータイム",
                                    durationFormatted = "04:00",
                                    approxDurationSeconds = 240,
                                    encryptedOffset = off,
                                    encryptedLength = len,
                                    rawFilename = fname
                                )
                            )
                            matchedCount++
                        }
                    }

                    _playlist.value = updatedList
                    val firstAvail = updatedList.firstOrNull { it.isAvailable } ?: updatedList.first()
                    _currentTrack.value = firstAvail
                    _durationSec.value = firstAvail.approxDurationSeconds
                    _libraryStatusMessage.value = "轻音音乐馆 · 已内置载入 $matchedCount 首原声名曲"
                    Log.d(TAG, "Loaded $matchedCount encrypted music tracks from $path")
                    return
                }
            } catch (_: Exception) {
            }
        }
    }

    fun selectCategory(cat: MusicCategoryFilter) {
        _selectedCategory.value = cat
    }

    fun cyclePlayMode() {
        val all = MusicPlayMode.values()
        _playMode.value = all[(_playMode.value.ordinal + 1) % all.size]
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

        val cPath = containerAssetPath
        if (cPath == null || !song.isAvailable) {
            // Try fallback finding first available song
            val avail = _playlist.value.firstOrNull { it.isAvailable }
            if (avail != null && avail != song) {
                playSong(avail)
            } else {
                _isPlaying.value = false
            }
            return
        }

        Thread {
            try {
                context.assets.open(cPath).use { stream ->
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
        val prev = list[(idx - 1 + list.size) % list.size]
        playSong(prev)
    }

    fun duckForVoice(duck: Boolean) {
        isDucked = duck
        val vol = if (duck) 0.18f else baseVolume
        try {
            mediaPlayer?.setVolume(vol, vol)
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
            KOnSongItem(7, "Singing!", "Singing!", "放课后茶会 / 秋山澪", "K-ON! 电影版 ED", MusicCategoryFilter.OPED, "秋山澪", "03:54", 234),
            KOnSongItem(8, "Unmei♪wa♪Endless!", "Unmei wa Endless!", "放课后茶会 / 平泽唯", "K-ON! 电影版 OP", MusicCategoryFilter.OPED, "平泽唯", "03:52", 232),
            KOnSongItem(9, "ふわふわ時間 (Fuwa Fuwa Time)", "Fuwa Fuwa Time", "放课后茶会 / 秋山澪·平泽唯", "放课后茶会 经典舞台曲", MusicCategoryFilter.INSERT, "放课后茶会", "03:59", 239),
            KOnSongItem(10, "わたしの恋はホッチキス", "Watashi no Koi wa Hotchkiss", "放课后茶会 / 平泽唯·秋山澪", "放课后茶会 I", MusicCategoryFilter.INSERT, "平泽唯·秋山澪", "04:24", 264),
            KOnSongItem(11, "ふでペン 〜ボールペン〜", "Fude Pen ~Ballpoint Pen~", "放课后茶会 / 秋山澪·平泽唯", "放课后茶会 I", MusicCategoryFilter.INSERT, "秋山澪", "03:58", 238),
            KOnSongItem(12, "ぴゅあぴゅあはーと", "Pure Pure Heart", "放课后茶会 / 秋山澪", "放课后茶会 II", MusicCategoryFilter.INSERT, "秋山澪", "04:35", 275),
            KOnSongItem(13, "ごはんはおかず (米饭是小菜)", "Gohan wa Okazu", "放课后茶会 / 平泽唯", "放课后茶会 II", MusicCategoryFilter.INSERT, "平泽唯", "03:12", 192),
            KOnSongItem(14, "U&I", "U and I", "放课后茶会 / 平泽唯", "放课后茶会 II (献给妹妹忧)", MusicCategoryFilter.INSERT, "平泽唯", "04:36", 276),
            KOnSongItem(15, "天使にふれたよ! (相遇天使)", "Tenshi ni Fureta yo!", "放课后茶会 (给梓喵的毕业赠歌)", "放课后茶会 II 最终话", MusicCategoryFilter.INSERT, "放课后茶会四人", "04:42", 282),
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
