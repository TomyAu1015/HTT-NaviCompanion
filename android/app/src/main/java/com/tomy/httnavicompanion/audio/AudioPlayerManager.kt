package com.tomy.httnavicompanion.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log
import com.tomy.httnavicompanion.data.AssetDecryptor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.io.FileOutputStream

enum class HTTCharacter(val id: Int, val displayName: String, val jpName: String) {
    YUI(0, "平泽唯", "平沢 唯"),
    MIO(1, "秋山澪", "秋山 澪"),
    RITSU(2, "田井中律", "田井中 律"),
    TSUMUGI(3, "琴吹紬", "琴吹 紬"),
    AZUSA(4, "中野梓", "中野 梓"),
    ALL(5, "HTT 全员", "放課後ティータイム")
}

class AudioPlayerManager(
    private val context: Context,
    private val assetDecryptor: AssetDecryptor
) {
    private val TAG = "AudioPlayerManager"
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var mediaPlayer: MediaPlayer? = null

    private val _selectedCharacter = MutableStateFlow(HTTCharacter.YUI)
    val selectedCharacter: StateFlow<HTTCharacter> = _selectedCharacter

    private val _mascotSpeechText = MutableStateFlow("放课后茶会导航伴侣已就绪！")
    val mascotSpeechText: StateFlow<String> = _mascotSpeechText

    fun selectCharacter(char: HTTCharacter) {
        _selectedCharacter.value = char
        playCharacterGreeting(char)
    }

    fun initVoicePackage() {
        Log.d(TAG, "AudioPlayerManager initialized")
    }

    fun playCharacterGreeting(char: HTTCharacter) {
        _mascotSpeechText.value = when (char) {
            HTTCharacter.YUI -> "出发啦～今天也要开心开车哦！"
            HTTCharacter.MIO -> "请系好安全带，注意行车安全。"
            HTTCharacter.RITSU -> "冲啊！今天就交给我律队来带路！"
            HTTCharacter.TSUMUGI -> "大家辛苦了～来喝杯红茶休息一下吧。"
            HTTCharacter.AZUSA -> "唯前辈，请专心看路，不要分心！"
            HTTCharacter.ALL -> "放课后茶会，全员合奏出发！"
        }
        triggerCharacterVoice(char.id)
    }

    fun triggerCharacterVoice(charId: Int) {
        val mascotVoices = assetDecryptor.mascotVoiceEntries.filter { it.charId == charId || charId == 5 }
        if (mascotVoices.isNotEmpty()) {
            val pick = mascotVoices.random()
            playVoiceByOffset(pick.offset, pick.length)
        } else if (assetDecryptor.voiceEntries.isNotEmpty()) {
            playVoiceByIndex((0 until minOf(20, assetDecryptor.voiceEntries.size)).random())
        }
    }

    fun playVoiceByIndex(index: Int) {
        val audioBytes = assetDecryptor.decryptVoiceChunk(index) ?: return
        playAudioData(audioBytes)
    }

    private fun playVoiceByOffset(offset: Long, length: Int) {
        try {
            context.assets.open("mascot_assets.dat").use { stream ->
                stream.skip(assetDecryptor.mascotPayloadStart + offset)
                val chunk = ByteArray(length)
                var readTotal = 0
                while (readTotal < chunk.size) {
                    val r = stream.read(chunk, readTotal, chunk.size - readTotal)
                    if (r == -1) break
                    readTotal += r
                }
                // Decrypt chunk via decryptor
                val iv = chunk.copyOfRange(0, 12)
                val ct = chunk.copyOfRange(12, chunk.size)
                val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
                val spec = javax.crypto.spec.GCMParameterSpec(128, iv)
                cipher.init(javax.crypto.Cipher.DECRYPT_MODE, javax.crypto.spec.SecretKeySpec(com.tomy.httnavicompanion.data.KeyConfig.keyBytes, "AES"), spec)
                val plain = cipher.doFinal(ct)
                playAudioData(plain)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error playing mascot voice", e)
        }
    }

    private fun playAudioData(audioBytes: ByteArray) {
        try {
            requestAudioFocus()
            val tempFile = File.createTempFile("htt_voice_", ".mp3", context.cacheDir)
            FileOutputStream(tempFile).use { it.write(audioBytes) }

            mediaPlayer?.release()
            mediaPlayer = MediaPlayer().apply {
                setDataSource(tempFile.absolutePath)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setOnCompletionListener {
                    tempFile.delete()
                    abandonAudioFocus()
                }
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error playback audio", e)
        }
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .build()
            audioManager.requestAudioFocus(req)
        }
    }

    private fun abandonAudioFocus() {
        // Audio focus will restore music volume automatically
    }
}
