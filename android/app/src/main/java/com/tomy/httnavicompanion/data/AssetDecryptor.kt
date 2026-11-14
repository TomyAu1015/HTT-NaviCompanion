package com.tomy.httnavicompanion.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.util.Log
import com.tomy.httnavicompanion.audio.CharacterFilter
import com.tomy.httnavicompanion.audio.MascotActionState
import com.tomy.httnavicompanion.audio.NavigationTravelMode
import com.tomy.httnavicompanion.audio.RM500ArrowOutfit
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipInputStream
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.math.cos
import kotlin.math.sin

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
    val cachedTeaPartyFrames = ArrayList<Bitmap>(4)

    var deskSpriteFrame: Bitmap? = null
        private set

    @Volatile
    var isInitialized: Boolean = false
        private set

    fun initAssets() {
        if (isInitialized) return
        loadVoicePackageIndex()
        loadMascotPackageIndex()
        loadVehicleSpritesArchive()
        loadDoudizhuCardsArchive()

        // Preload desk sprite frame
        getSpriteBitmap("desk00")?.let { deskSheet ->
            if (deskSheet.width >= 288 && deskSheet.height >= 110) {
                deskSpriteFrame = Bitmap.createBitmap(deskSheet, 96, 0, 192, 110)
            }
        }

        // Preload core character sprite sheets
        listOf(
            "yui01", "mio01", "ritsu01", "tsumugi01", "azusa01",
            "yui00", "mio00", "ritsu00", "tsumugi00", "azusa00",
            "desk00", "desk01"
        ).forEach { getSpriteBitmap(it) }

        // Prebuild 4 animated full 5-member tea party frames matching iOS v1.6.3
        cachedTeaPartyFrames.clear()
        for (t in 0..3) {
            renderTeaPartySceneFrame(setOf(1, 2, 3, 4, 5), t)?.let {
                cachedTeaPartyFrames.add(it)
            }
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
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed loading mascot_assets.dat", e)
        }
    }

    private fun loadVehicleSpritesArchive()
        loadDoudizhuCardsArchive() {
        try {
            context.assets.open("vehicle_sprites.zip").use { rawStream ->
                ZipInputStream(rawStream).use { zis ->
                    val opts = BitmapFactory.Options().apply { inScaled = false }
                    var entry = zis.nextEntry
                    while (entry != null) {
                        if (!entry.isDirectory && entry.name.endsWith(".png")) {
                            val key = entry.name.removeSuffix(".png")
                            val bytes = zis.readBytes()
                            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                            if (bmp != null) {
                                bitmapCache[key] = bmp
                            }
                        }
                        zis.closeEntry()
                        entry = zis.nextEntry
                    }
                }
            }
            Log.d(TAG, "Loaded vehicle sprites archive into cache")
        } catch (e: Exception) {
            Log.e(TAG, "Failed loading vehicle_sprites.zip", e)
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

        // 1. Check mascot_assets.dat first
        val entry = spriteEntries[spriteName]
        if (entry != null) {
            try {
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
                    val opts = BitmapFactory.Options().apply { inScaled = false }
                    val bmp = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size, opts)
                    if (bmp != null) {
                        bitmapCache[spriteName] = bmp
                        return bmp
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error loading sprite $spriteName", e)
            }
        }

        // 2. Check extracted vehicle / extra stage icons in assets/vehicles/<spriteName>.png
        return try {
            context.assets.open("vehicles/$spriteName.png").use { stream ->
                val opts = BitmapFactory.Options().apply { inScaled = false }
                val bmp = BitmapFactory.decodeStream(stream, null, opts)
                if (bmp != null) {
                    bitmapCache[spriteName] = bmp
                }
                bmp
            }
        } catch (_: Exception) {
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

    /**
     * Exact 1:1 port of iOS v1.6.3 `renderTeaPartySceneFrame(includedCharIds:tick:)`
     * Composites desk00 (chairs, petals, steam) + seated girls from yui00..azusa00 + desk01 (wooden table & teacups) + Yui's crossed arms!
     */
    fun renderTeaPartySceneFrame(includedCharIds: Set<Int> = setOf(1, 2, 3, 4, 5), tick: Int = 0): Bitmap? {
        val t = tick % 4
        if (includedCharIds.size == 5 && cachedTeaPartyFrames.size == 4) {
            return cachedTeaPartyFrames[t]
        }
        val sortedKey = includedCharIds.sorted().joinToString("_")
        val cKey = "teaparty_inc_${sortedKey}_t$t"
        croppedCache[cKey]?.let { return it }

        val d0 = getSpriteBitmap("desk00") ?: return null
        val d1 = getSpriteBitmap("desk01")
        val outBmp = Bitmap.createBitmap(288, 160, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(outBmp)
        val paint = Paint().apply { isFilterBitmap = false }
        val ox = t * 288

        // 1. Clean desk00 background (3 blue chairs + floating petals + teacup steam)
        canvas.drawBitmap(d0, Rect(ox, 0, ox + 288, 74), Rect(0, 0, 288, 74), paint)
        canvas.drawBitmap(d0, Rect(ox, 105, ox + 288, 160), Rect(0, 105, 288, 160), paint)
        // Clean chair tops
        val chairSrc = Rect(ox + 68, 99, ox + 68 + 49, 105)
        canvas.drawBitmap(d0, chairSrc, Rect(68, 99, 68 + 49, 105), paint)
        canvas.drawBitmap(d0, chairSrc, Rect(125, 99, 125 + 49, 105), paint)
        canvas.drawBitmap(d0, chairSrc, Rect(182, 99, 182 + 49, 105), paint)
        // Teacup steam
        canvas.drawBitmap(d0, Rect(ox + 60, 80, ox + 84, 99), Rect(60, 80, 84, 99), paint)
        canvas.drawBitmap(d0, Rect(ox + 170, 80, ox + 185, 99), Rect(170, 80, 185, 99), paint)

        // 2. Seated characters at their exact chairs
        if (includedCharIds.contains(2)) {
            getSpriteBitmap("mio00")?.let { mio ->
                canvas.drawBitmap(mio, Rect(0, 0, 64, 128), Rect(2, 20, 2 + 64, 20 + 128), paint)
            }
        }
        if (includedCharIds.contains(3)) {
            getSpriteBitmap("ritsu00")?.let { ritsu ->
                val rx = (t % 2) * 80
                canvas.drawBitmap(ritsu, Rect(rx, 128, rx + 80, 256), Rect(50, 20, 50 + 80, 20 + 128), paint)
            }
        }
        if (includedCharIds.contains(1)) {
            getSpriteBitmap("yui00")?.let { yui ->
                val yx = t * 64
                canvas.drawBitmap(yui, Rect(yx, 128, yx + 64, 256), Rect(115, 20, 115 + 64, 20 + 128), paint)
            }
        }
        if (includedCharIds.contains(4)) {
            getSpriteBitmap("tsumugi00")?.let { mugi ->
                val mx = t * 64
                canvas.drawBitmap(mugi, Rect(mx, 128, mx + 64, 256), Rect(182, 20, 182 + 64, 20 + 128), paint)
            }
        }
        if (includedCharIds.contains(5)) {
            getSpriteBitmap("azusa00")?.let { azusa ->
                canvas.drawBitmap(azusa, Rect(0, 0, 64, 128), Rect(230, 20, 230 + 64, 20 + 128), paint)
            }
        }

        // 3. Wooden Table, Teacups & Side Armchairs (desk01)
        if (d1 != null) {
            canvas.drawBitmap(d1, Rect(0, 0, 288, 160), Rect(0, 0, 288, 160), paint)
        }

        // 4. Yui's crossed arms over tabletop
        if (includedCharIds.contains(1)) {
            getSpriteBitmap("yui00")?.let { yui ->
                val yx = t * 64
                canvas.drawBitmap(yui, Rect(yx, 202, yx + 64, 218), Rect(115, 94, 115 + 64, 110), paint)
            }
        }

        croppedCache[cKey] = outBmp
        return outBmp
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

    /**
     * Exact 1:1 port of iOS v1.6.3 `getRM500NavigationArrowFrame`
     * Supports London Vintage Car (`c01_u`..`c49_r`) in Driving mode, Red Retro Scooter (`s01_u`..`s49_r`) in e-Bike mode,
     * and walking character sprite in Walking/Transit mode!
     */
    fun getRM500NavigationArrowFrame(
        selectedChar: CharacterFilter,
        activeAllChar: CharacterFilter,
        outfit: RM500ArrowOutfit,
        travelMode: NavigationTravelMode,
        walkStep: Int,
        headingDeg: Double,
        cameraHeadingDeg: Double,
        isMoving: Boolean = true
    ): Bitmap? {
        if (outfit == RM500ArrowOutfit.CLASSIC_3D) {
            return createClassic3DChevronBitmap(0.0, 0)
        }
        val stepBit = if (isMoving) (walkStep % 2) else 0
        val eff = if (selectedChar == CharacterFilter.ALL) activeAllChar else selectedChar
        val charBlock: Int
        val charPaletteIdx: Int
        if (outfit == RM500ArrowOutfit.TONCHAN) {
            charBlock = 51
            charPaletteIdx = 5
        } else {
            when (eff) {
                CharacterFilter.YUI, CharacterFilter.ALL -> { charBlock = 1; charPaletteIdx = 0 }
                CharacterFilter.MIO -> { charBlock = 11; charPaletteIdx = 1 }
                CharacterFilter.RITSU -> { charBlock = 21; charPaletteIdx = 2 }
                CharacterFilter.MUGI -> { charBlock = 31; charPaletteIdx = 3 }
                CharacterFilter.AZUSA -> { charBlock = 41; charPaletteIdx = 4 }
            }
        }
        val oddStripIdx = if (outfit == RM500ArrowOutfit.TONCHAN) 51 else (charBlock + outfit.rawValue * 2)
        val stripIdx = oddStripIdx + stepBit

        var rel = (headingDeg - cameraHeadingDeg) % 360.0
        if (rel < 0) rel += 360.0
        val clockSector = (((rel + 15.0) / 30.0).toInt()) % 12
        val sectorToCell = intArrayOf(0, 11, 8, 3, 4, 7, 6, 5, 2, 9, 10, 1)
        val cellIdx = sectorToCell[clockSector]

        val useScooter = travelMode == NavigationTravelMode.EBIKE
        val useCar = travelMode == NavigationTravelMode.DRIVING

        if ((useCar || useScooter) && outfit != RM500ArrowOutfit.TONCHAN) {
            val prefix = if (useScooter) "s" else "c"
            val modeCacheKey = "${prefix}_veh_${oddStripIdx}_c${cellIdx}_s$stepBit"
            croppedCache[modeCacheKey]?.let { return it }

            val poseChar: String
            val arrowAngle: Double
            when (cellIdx) {
                0 -> { poseChar = "u"; arrowAngle = 0.0 }
                11 -> { poseChar = "u"; arrowAngle = 30.0 }
                4 -> { poseChar = "r"; arrowAngle = 60.0 }
                3 -> { poseChar = "r"; arrowAngle = 90.0 }
                2 -> { poseChar = "r"; arrowAngle = 120.0 }
                7 -> { poseChar = "d"; arrowAngle = 150.0 }
                6 -> { poseChar = "d"; arrowAngle = 180.0 }
                5 -> { poseChar = "d"; arrowAngle = 210.0 }
                8 -> { poseChar = "l"; arrowAngle = 240.0 }
                9 -> { poseChar = "l"; arrowAngle = 270.0 }
                10 -> { poseChar = "l"; arrowAngle = 300.0 }
                1 -> { poseChar = "u"; arrowAngle = 330.0 }
                else -> { poseChar = "u"; arrowAngle = 0.0 }
            }
            val lookupPose = if (poseChar == "l") "r" else poseChar
            val sheetKey = String.format("%s%02d_%s", prefix, oddStripIdx, lookupPose)
            val vehBmp = getSpriteBitmap(sheetKey)
            if (vehBmp != null) {
                val outBmp = Bitmap.createBitmap(140, 182, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(outBmp)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { isFilterBitmap = false }
                val bounceY = if (stepBit == 1) -2f else 0f
                val leftX = (140f - vehBmp.width) * 0.5f
                val topY = (136f - vehBmp.height + bounceY).coerceAtLeast(0f)

                if (poseChar == "l") {
                    val m = Matrix().apply {
                        preScale(-1f, 1f)
                        postTranslate(leftX + vehBmp.width, topY)
                    }
                    canvas.drawBitmap(vehBmp, m, paint)
                } else {
                    canvas.drawBitmap(vehBmp, leftX, topY, paint)
                }
                draw3DFacetedChevronArrow(canvas, 70f, 159f, arrowAngle, charPaletteIdx, 38f)
                croppedCache[modeCacheKey] = outBmp
                return outBmp
            }
        }

        val key = String.format("arrow_%02d", stripIdx)
        val strip = getSpriteBitmap(key) ?: return null
        return safeCrop(strip, "${key}_cell_${cellIdx}", cellIdx * 110, 0, 110, 143)
    }

    private fun createClassic3DChevronBitmap(angleDegrees: Double, charPaletteIdx: Int): Bitmap {
        val key = "classic3d_${angleDegrees.toInt()}_$charPaletteIdx"
        croppedCache[key]?.let { return it }
        val bmp = Bitmap.createBitmap(80, 80, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        draw3DFacetedChevronArrow(canvas, 40f, 40f, angleDegrees, charPaletteIdx, 52f)
        croppedCache[key] = bmp
        return bmp
    }

    private fun draw3DFacetedChevronArrow(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        angleDegrees: Double,
        charPaletteIdx: Int,
        size: Float
    ) {
        val (lightCol, darkCol) = when (charPaletteIdx) {
            1 -> Pair(AndroidColor.rgb(22, 138, 248), AndroidColor.rgb(10, 75, 160))
            2 -> Pair(AndroidColor.rgb(252, 168, 15), AndroidColor.rgb(178, 96, 5))
            3 -> Pair(AndroidColor.rgb(244, 68, 168), AndroidColor.rgb(168, 24, 105))
            4 -> Pair(AndroidColor.rgb(24, 198, 118), AndroidColor.rgb(10, 120, 64))
            else -> Pair(AndroidColor.rgb(235, 12, 18), AndroidColor.rgb(162, 6, 10))
        }
        val rad = Math.toRadians(angleDegrees)
        val fx = sin(rad).toFloat()
        val fy = (-cos(rad)).toFloat()
        val rx = -fy
        val ry = fx
        val sc = size / 64f

        val tipX = cx + fx * 26f * sc
        val tipY = cy + fy * 26f * sc
        val notchX = cx - fx * 11f * sc
        val notchY = cy - fy * 11f * sc
        val lWingX = cx - fx * 24f * sc - rx * 21.5f * sc
        val lWingY = cy - fy * 24f * sc - ry * 21.5f * sc
        val rWingX = cx - fx * 24f * sc + rx * 21.5f * sc
        val rWingY = cy - fy * 24f * sc + ry * 21.5f * sc

        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        val leftPath = Path().apply {
            moveTo(tipX, tipY)
            lineTo(lWingX, lWingY)
            lineTo(notchX, notchY)
            close()
        }
        p.color = lightCol
        canvas.drawPath(leftPath, p)

        val rightPath = Path().apply {
            moveTo(tipX, tipY)
            lineTo(rWingX, rWingY)
            lineTo(notchX, notchY)
            close()
        }
        p.color = darkCol
        canvas.drawPath(rightPath, p)

        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = AndroidColor.WHITE
            strokeWidth = 2f
        }
        val outline = Path().apply {
            moveTo(tipX, tipY)
            lineTo(lWingX, lWingY)
            lineTo(notchX, notchY)
            lineTo(rWingX, rWingY)
            close()
        }
        canvas.drawPath(outline, strokePaint)
    }

    fun getRM500StageIcon(
        char: CharacterFilter,
        activeAllChar: CharacterFilter,
        outfit: RM500ArrowOutfit,
        walkStep: Int
    ): Bitmap? {
        val step2 = (walkStep % 2 == 1)
        if (outfit == RM500ArrowOutfit.TONCHAN) {
            return getSpriteBitmap(if (step2) "rm_stg_ton_2" else "rm_stg_ton_1")
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
            RM500ArrowOutfit.SUMMER_UNIFORM -> if (step2) "_summer_2" else "_summer"
            RM500ArrowOutfit.MAID -> if (step2) "_maid_2" else "_maid"
            RM500ArrowOutfit.HTT_SHIRT -> if (step2) "_htt_2" else "_htt"
            RM500ArrowOutfit.KIGURUMI -> if (step2) "_kig_2" else "_kig"
            else -> if (step2) "_2" else "_1"
        }
        return getSpriteBitmap(prefix + suffix) ?: getSpriteBitmap(prefix + "_1")
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
