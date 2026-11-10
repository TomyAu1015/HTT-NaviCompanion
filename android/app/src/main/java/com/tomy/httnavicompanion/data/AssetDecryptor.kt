package com.tomy.httnavicompanion.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.tomy.httnavicompanion.audio.CharacterFilter
import com.tomy.httnavicompanion.audio.MascotActionState
import com.tomy.httnavicompanion.audio.RM500ArrowOutfit
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
    private val croppedCache = ConcurrentHashMap<String, Bitmap>()
    var deskSpriteFrame: Bitmap? = null
        private set

    @Volatile
    var isInitialized: Boolean = false
        private set

    fun initAssets() {
        if (isInitialized) return
        loadVoicePackageIndex()
        loadMascotPackageIndex()
        // Preload desk sprite frame
        getSpriteBitmap("desk00")?.let { deskSheet ->
            if (deskSheet.width >= 288 && deskSheet.height >= 110) {
                deskSpriteFrame = Bitmap.createBitmap(deskSheet, 96, 0, 192, 110)
            }
        }
        // Preload core character sprite sheets
        listOf("yui01", "mio01", "ritsu01", "tsumugi01", "azusa01", "yui00", "mio00", "ritsu00", "tsumugi00", "azusa00").forEach {
            getSpriteBitmap(it)
        }
        isInitialized = true
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

    fun decryptVoiceChunk(oneBasedId: Int): ByteArray? {
        val index = oneBasedId - 1
        if (index < 0 || index >= voiceEntries.size) return null
        val entry = voiceEntries[index]
        return try {
            context.assets.open("voice_assets.dat").use { stream ->
                skipFully(stream, voicePayloadStart + entry.offset)
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
            Log.e(TAG, "Error decrypting voice chunk $oneBasedId", e)
            null
        }
    }

    fun decryptMascotVoice(entry: MascotVoiceEntry): ByteArray? {
        return try {
            context.assets.open("mascot_assets.dat").use { stream ->
                skipFully(stream, mascotPayloadStart + entry.offset)
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
            Log.e(TAG, "Error decrypting mascot voice", e)
            null
        }
    }

    fun getSpriteBitmap(spriteName: String): Bitmap? {
        bitmapCache[spriteName]?.let { return it }
        val entry = spriteEntries[spriteName] ?: return null
        return try {
            context.assets.open("mascot_assets.dat").use { stream ->
                skipFully(stream, mascotPayloadStart + entry.offset)
                val chunk = ByteArray(entry.length)
                var readTotal = 0
                while (readTotal < chunk.size) {
                    val r = stream.read(chunk, readTotal, chunk.size - readTotal)
                    if (r == -1) break
                    readTotal += r
                }
                val pngBytes = decryptAesGcm(chunk) ?: return null
                val opts = BitmapFactory.Options().apply {
                    inScaled = false
                }
                val bmp = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size, opts)
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

    fun getAssetBitmap(assetFileName: String): Bitmap? {
        bitmapCache[assetFileName]?.let { return it }
        return try {
            context.assets.open(assetFileName).use { stream ->
                val bmp = BitmapFactory.decodeStream(stream)
                if (bmp != null) {
                    bitmapCache[assetFileName] = bmp
                }
                bmp
            }
        } catch (e: Exception) {
            null
        }
    }

    fun sliceMascotFrame(
        char: CharacterFilter,
        action: MascotActionState,
        tick: Int,
        isPlayingVoice: Boolean
    ): Bitmap? {
        if (action == MascotActionState.TEA_CAKE) {
            val sheet = getSpriteBitmap(char.cakeSheetName) ?: return null
            val fw = if (char == CharacterFilter.RITSU) 80 else 64
            val fh = 128
            val row: Int
            val col: Int
            when (char) {
                CharacterFilter.YUI, CharacterFilter.MUGI, CharacterFilter.ALL -> {
                    row = 1; col = tick % 4
                }
                CharacterFilter.RITSU -> {
                    row = 1; col = tick % 2
                }
                CharacterFilter.MIO, CharacterFilter.AZUSA -> {
                    row = 0; col = 0
                }
            }
            return safeCrop(sheet, "${char.cakeSheetName}_${row}_${col}", col * fw, row * fh, fw, fh)
        }

        val sheet = getSpriteBitmap(char.mainSheetName) ?: return null
        val fw = if (char == CharacterFilter.MUGI || char == CharacterFilter.AZUSA) 112 else 96
        val fh = 96
        val row: Int
        val col: Int

        when (action) {
            MascotActionState.IDLE -> {
                row = 0
                col = if (isPlayingVoice) (tick % 4) else ((tick / 2) % 4)
            }
            MascotActionState.WALK_LEFT -> {
                row = 1
                col = tick % 6
            }
            MascotActionState.WALK_RIGHT -> {
                row = 2
                col = tick % 6
            }
            MascotActionState.GRABBED -> {
                row = 4
                val maxCols = when (char) {
                    CharacterFilter.MIO -> 1
                    CharacterFilter.AZUSA -> 2
                    else -> 4
                }
                col = tick % maxCols
            }
            MascotActionState.PANIC -> {
                when (char) {
                    CharacterFilter.YUI, CharacterFilter.ALL -> { row = 4; col = tick % 4 }
                    CharacterFilter.MIO -> { row = 5; col = tick % 2 }
                    CharacterFilter.RITSU -> { row = 4; col = tick % 4 }
                    CharacterFilter.MUGI -> { row = 3; col = tick % 2 }
                    CharacterFilter.AZUSA -> { row = 3; col = tick % 6 }
                }
            }
            MascotActionState.SPECIAL, MascotActionState.TEA_CAKE -> {
                when (char) {
                    CharacterFilter.YUI, CharacterFilter.ALL -> { row = 6; col = tick % 6 }
                    CharacterFilter.MIO -> { row = 3; col = tick % 2 }
                    CharacterFilter.RITSU -> { row = 5; col = tick % 4 }
                    CharacterFilter.MUGI -> { row = 5; col = tick % 6 }
                    CharacterFilter.AZUSA -> { row = 5; col = tick % 3 }
                }
            }
        }
        return safeCrop(sheet, "${char.mainSheetName}_${row}_${col}", col * fw, row * fh, fw, fh)
    }

    fun getRM500NavigationArrowFrame(
        selectedChar: CharacterFilter,
        activeAllChar: CharacterFilter,
        outfit: RM500ArrowOutfit,
        walkStep: Int,
        headingDeg: Double,
        cameraHeadingDeg: Double
    ): Bitmap? {
        if (outfit == RM500ArrowOutfit.CLASSIC_3D) return null
        val stripIdx = if (outfit == RM500ArrowOutfit.TONCHAN) {
            51 + (walkStep % 2)
        } else {
            val eff = if (selectedChar == CharacterFilter.ALL) activeAllChar else selectedChar
            val charBlock = when (eff) {
                CharacterFilter.YUI, CharacterFilter.ALL -> 1
                CharacterFilter.MIO -> 11
                CharacterFilter.RITSU -> 21
                CharacterFilter.MUGI -> 31
                CharacterFilter.AZUSA -> 41
            }
            charBlock + (outfit.rawValue * 2) + (walkStep % 2)
        }
        val key = String.format("arrow_%02d", stripIdx)
        val strip = getSpriteBitmap(key) ?: return null

        var rel = (headingDeg - cameraHeadingDeg) % 360.0
        if (rel < 0) rel += 360.0
        val cellIdx = (((rel + 15.0) / 30.0).toInt()) % 12
        return safeCrop(strip, "${key}_cell_${cellIdx}", cellIdx * 110, 0, 110, 143)
    }

    fun getRM500StageIcon(
        char: CharacterFilter,
        activeAllChar: CharacterFilter,
        outfit: RM500ArrowOutfit,
        walkStep: Int
    ): Bitmap? {
        if (outfit == RM500ArrowOutfit.TONCHAN) {
            return getSpriteBitmap(if (walkStep % 2 == 0) "rm_stg_ton_1" else "rm_stg_ton_2")
        }
        val eff = if (char == CharacterFilter.ALL) activeAllChar else char
        val prefix = when (eff) {
            CharacterFilter.YUI, CharacterFilter.ALL -> "rm_stg_yui"
            CharacterFilter.MIO -> "rm_stg_mio"
            CharacterFilter.RITSU -> "rm_stg_ritsu"
            CharacterFilter.MUGI -> "rm_stg_mugi"
            CharacterFilter.AZUSA -> "rm_stg_azusa"
        }
        val suffix = when (outfit) {
            RM500ArrowOutfit.MAID -> "_maid"
            RM500ArrowOutfit.KIGURUMI -> "_kig"
            else -> if (walkStep % 2 == 0) "_1" else "_2"
        }
        return getSpriteBitmap(prefix + suffix)
    }

    private fun safeCrop(sheet: Bitmap, cacheKey: String, x: Int, y: Int, w: Int, h: Int): Bitmap? {
        croppedCache[cacheKey]?.let { return it }
        if (x < 0 || y < 0 || x + w > sheet.width || y + h > sheet.height) return null
        return try {
            val bmp = Bitmap.createBitmap(sheet, x, y, w, h)
            croppedCache[cacheKey] = bmp
            bmp
        } catch (e: Exception) {
            null
        }
    }

    private fun skipFully(stream: java.io.InputStream, bytes: Long) {
        var remaining = bytes
        while (remaining > 0) {
            val s = stream.skip(remaining)
            if (s <= 0) break
            remaining -= s
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
