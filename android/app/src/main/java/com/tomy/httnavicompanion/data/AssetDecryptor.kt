package com.tomy.httnavicompanion.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class VoiceIndexEntry(val offset: Long, val length: Int)
data class MascotVoiceEntry(val charId: Int, val offset: Long, val length: Int)
data class SpriteEntry(val name: String, val offset: Long, val length: Int)

class AssetDecryptor(private val context: Context) {
    private val TAG = "AssetDecryptor"
    private val secretKey = SecretKeySpec(KeyConfig.keyBytes, "AES")

    val voiceEntries = ArrayList<VoiceIndexEntry>()
    var voicePayloadStart: Long = 0L

    val spriteEntries = HashMap<String, SpriteEntry>()
    val mascotVoiceEntries = ArrayList<MascotVoiceEntry>()
    var mascotPayloadStart: Long = 0L

    private val bitmapCache = ConcurrentHashMap<String, Bitmap>()

    fun initAssets() {
        loadVoicePackageIndex()
        loadMascotPackageIndex()
    }

    private fun loadVoicePackageIndex() {
        try {
            context.assets.open("voice_assets.dat").use { stream ->
                val magic = ByteArray(8)
                stream.read(magic)
                if (String(magic, 0, 7) != "HTT_PKG") {
                    Log.w(TAG, "Invalid voice magic")
                    return
                }

                val countBuf = ByteArray(4)
                stream.read(countBuf)
                val count = ByteBuffer.wrap(countBuf).order(ByteOrder.LITTLE_ENDIAN).int

                val tableBuf = ByteArray(count * 8)
                var readTotal = 0
                while (readTotal < tableBuf.size) {
                    val r = stream.read(tableBuf, readTotal, tableBuf.size - readTotal)
                    if (r == -1) break
                    readTotal += r
                }

                val bb = ByteBuffer.wrap(tableBuf).order(ByteOrder.LITTLE_ENDIAN)
                voiceEntries.clear()
                for (i in 0 until count) {
                    val off = bb.int.toLong() and 0xFFFFFFFFL
                    val len = bb.int
                    voiceEntries.add(VoiceIndexEntry(off, len))
                }
                voicePayloadStart = 8L + 4L + (count.toLong() * 8L)
                Log.d(TAG, "Loaded ${voiceEntries.size} voice entries")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed loading voice_assets.dat", e)
        }
    }

    private fun loadMascotPackageIndex() {
        try {
            context.assets.open("mascot_assets.dat").use { stream ->
                val magic = ByteArray(8)
                stream.read(magic)

                val countsBuf = ByteArray(8)
                stream.read(countsBuf)
                val bbCounts = ByteBuffer.wrap(countsBuf).order(ByteOrder.LITTLE_ENDIAN)
                val spriteCount = bbCounts.int
                val voiceCount = bbCounts.int

                spriteEntries.clear()
                for (i in 0 until spriteCount) {
                    val entryBuf = ByteArray(40)
                    stream.read(entryBuf)
                    val nameRaw = String(entryBuf, 0, 32, Charsets.US_ASCII).trimEnd(0.toChar())
                    val bb = ByteBuffer.wrap(entryBuf, 32, 8).order(ByteOrder.LITTLE_ENDIAN)
                    val off = bb.int.toLong() and 0xFFFFFFFFL
                    val len = bb.int
                    spriteEntries[nameRaw] = SpriteEntry(nameRaw, off, len)
                }

                mascotVoiceEntries.clear()
                for (i in 0 until voiceCount) {
                    val vBuf = ByteArray(12)
                    stream.read(vBuf)
                    val bb = ByteBuffer.wrap(vBuf).order(ByteOrder.LITTLE_ENDIAN)
                    val cid = bb.int
                    val off = bb.int.toLong() and 0xFFFFFFFFL
                    val len = bb.int
                    mascotVoiceEntries.add(MascotVoiceEntry(cid, off, len))
                }

                mascotPayloadStart = 16L + (spriteCount.toLong() * 40L) + (voiceCount.toLong() * 12L)
                Log.d(TAG, "Loaded ${spriteEntries.size} sprites, ${mascotVoiceEntries.size} mascot voices")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed loading mascot_assets.dat", e)
        }
    }

    fun decryptVoiceChunk(index: Int): ByteArray? {
        if (index < 0 || index >= voiceEntries.size) return null
        val entry = voiceEntries[index]
        return try {
            context.assets.open("voice_assets.dat").use { stream ->
                stream.skip(voicePayloadStart + entry.offset)
                val chunk = ByteArray(entry.length)
                var readTotal = 0
                while (readTotal < chunk.size) {
                    val r = stream.read(chunk, readTotal, chunk.size - readTotal)
                    if (r == -1) break
                    readTotal += r
                }
                decryptAesGcm(chunk)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error decrypting voice chunk $index", e)
            null
        }
    }

    fun getSpriteBitmap(spriteName: String): Bitmap? {
        bitmapCache[spriteName]?.let { return it }
        val entry = spriteEntries[spriteName] ?: return null
        return try {
            context.assets.open("mascot_assets.dat").use { stream ->
                stream.skip(mascotPayloadStart + entry.offset)
                val chunk = ByteArray(entry.length)
                var readTotal = 0
                while (readTotal < chunk.size) {
                    val r = stream.read(chunk, readTotal, chunk.size - readTotal)
                    if (r == -1) break
                    readTotal += r
                }
                val pngBytes = decryptAesGcm(chunk) ?: return null
                val bmp = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
                if (bmp != null) {
                    bitmapCache[spriteName] = bmp
                }
                bmp
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading sprite $spriteName", e)
            null
        }
    }

    private fun decryptAesGcm(chunk: ByteArray): ByteArray? {
        if (chunk.size < 28) return null
        val iv = chunk.copyOfRange(0, 12)
        val cipherTextAndTag = chunk.copyOfRange(12, chunk.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
        return cipher.doFinal(cipherTextAndTag)
    }
}
