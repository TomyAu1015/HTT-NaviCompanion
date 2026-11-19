package com.tomy.httnavicompanion.audio

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.Collections
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.zip.ZipInputStream
import kotlin.random.Random

enum class RmkColor(val code: String, val labelZh: String) {
    RED("R", "红"), BLUE("B", "蓝"), YELLOW("Y", "黄"), BLACK("K", "绿"), JOKER("J", "百搭");
    companion object {
        fun fromCode(c: String): RmkColor = values().firstOrNull { it.code == c } ?: RED
    }
}

data class RmkTile(val id: String, val color: RmkColor, val number: Int) {
    val isJoker: Boolean get() = color == RmkColor.JOKER

    val assetFileName: String
        get() {
            if (isJoker) return "rmk_joker.png"
            val cIdx = when (color) {
                RmkColor.RED -> 1
                RmkColor.BLUE -> 2
                RmkColor.YELLOW -> 3
                RmkColor.BLACK -> 4
                RmkColor.JOKER -> 5
            }
            val n = number.coerceIn(1, 13)
            return "rmk_${cIdx}_${n}.png"
        }
}

data class RmkMeld(val id: String, val tiles: List<RmkTile>)

data class RmkSeat(
    val id: Int,
    val name: String,
    val characterId: Int,
    val isAI: Boolean,
    val peerDisplayName: String,
    val hand: List<RmkTile> = emptyList(),
    val hasBrokenIce: Boolean = false,
    val score: Int = 1000
)

enum class RmkGamePhase { LOBBY, PLAYING, ROUND_OVER }
enum class RmkNetworkMode { LOCAL_LAN, ONLINE_SERVER }

object RmkEvaluator {
    fun sortMeldForDisplay(tiles: List<RmkTile>, preferLeadingJoker: Boolean = false): List<RmkTile> {
        val jokers = tiles.filter { it.isJoker }.toMutableList()
        val normals = tiles.filter { !it.isJoker }.sortedWith(Comparator { a, b ->
            if (a.number != b.number) a.number - b.number else a.color.code.compareTo(b.color.code)
        })
        if (normals.isEmpty()) return tiles
        if (normals.all { it.number == normals[0].number }) {
            return if (preferLeadingJoker) jokers + normals else normals + jokers
        }
        val res = ArrayList<RmkTile>(tiles.size)
        for (i in normals.indices) {
            res.add(normals[i])
            if (i + 1 < normals.size) {
                val gap = normals[i + 1].number - normals[i].number - 1
                if (gap > 0) {
                    repeat(gap) { if (jokers.isNotEmpty()) res.add(jokers.removeAt(0)) }
                }
            }
        }
        var curLow = normals.first().number
        var curHigh = normals.last().number
        while (jokers.isNotEmpty()) {
            val j = jokers.removeAt(0)
            if (preferLeadingJoker && curLow > 1) {
                res.add(0, j)
                curLow -= 1
            } else if (curHigh >= 13 && curLow > 1) {
                res.add(0, j)
                curLow -= 1
            } else if (curHigh < 13) {
                res.add(j)
                curHigh += 1
            } else {
                res.add(0, j)
                curLow -= 1
            }
        }
        return res
    }

    fun evaluateMeld(tiles: List<RmkTile>): Int? {
        if (tiles.size < 3) return null
        val jokers = tiles.filter { it.isJoker }
        val normals = tiles.filter { !it.isJoker }
        if (normals.isEmpty()) return null

        // Group: same number, distinct colors, max 4
        if (tiles.size <= 4) {
            val num = normals[0].number
            val sameNum = normals.all { it.number == num }
            val cols = normals.map { it.color }.toSet()
            if (sameNum && cols.size == normals.size) return num * tiles.size
        }

        // Run: same color, strictly consecutive 1..13
        val col = normals[0].color
        if (normals.all { it.color == col }) {
            val nums = normals.map { it.number }.sorted()
            if (nums.toSet().size != nums.size) return null
            val span = nums.last() - nums.first() + 1
            val gaps = span - nums.size
            if (gaps <= jokers.size && tiles.size <= 13) {
                var remJ = jokers.size - gaps
                var low = nums.first()
                var high = nums.last()
                while (remJ > 0 && high < 13) { high++; remJ-- }
                while (remJ > 0 && low > 1) { low--; remJ-- }
                if (high - low + 1 == tiles.size && low >= 1 && high <= 13) {
                    return (low + high) * tiles.size / 2
                }
            }
        }
        return null
    }

    fun autoSplitMeldTiles(tiles: List<RmkTile>, preferLeadingJoker: Boolean = false): List<List<RmkTile>> {
        if (tiles.size <= 2) return listOf(sortMeldForDisplay(tiles, preferLeadingJoker))
        if (evaluateMeld(tiles) != null) return listOf(sortMeldForDisplay(tiles, preferLeadingJoker))

        val jokers = tiles.filter { it.isJoker }
        val normals = tiles.filter { !it.isJoker }.sortedWith(Comparator { a, b ->
            if (a.number != b.number) a.number - b.number else a.color.code.compareTo(b.color.code)
        })
        if (normals.isEmpty()) return listOf(tiles)

        // Case A: Same-color run with duplicate number (e.g. 2-3-4-4-5-6-7 -> [2,3,4] + [4,5,6,7]) or gap (1-2-3-5-6-7 -> [1,2,3] + [5,6,7])
        if (normals.all { it.color == normals[0].color }) {
            val rawSorted = normals + jokers
            if (rawSorted.size >= 6) {
                for (cut in 3..(rawSorted.size - 3)) {
                    val left = rawSorted.subList(0, cut)
                    val right = rawSorted.subList(cut, rawSorted.size)
                    if (evaluateMeld(left) != null && evaluateMeld(right) != null) {
                        return listOf(
                            sortMeldForDisplay(left, preferLeadingJoker),
                            sortMeldForDisplay(right, false)
                        )
                    }
                }
            }

            val chains = ArrayList<MutableList<RmkTile>>()
            for (t in normals) {
                val matching = chains.indices.filter { idx ->
                    val last = chains[idx].lastOrNull()
                    last != null && last.number == t.number - 1
                }
                val bestIdx = matching.sortedWith(Comparator { a, b ->
                    val aNeed = chains[a].size < 3
                    val bNeed = chains[b].size < 3
                    if (aNeed != bNeed) {
                        if (aNeed) -1 else 1
                    } else {
                        chains[a].size - chains[b].size
                    }
                }).firstOrNull()
                if (bestIdx != null) {
                    chains[bestIdx].add(t)
                } else {
                    chains.add(mutableListOf(t))
                }
            }

            val remJ = jokers.toMutableList()
            for (idx in chains.indices) {
                if (remJ.isNotEmpty() && chains[idx].size == 2) {
                    chains[idx].add(remJ.removeAt(0))
                }
            }
            while (remJ.isNotEmpty()) {
                if (chains.isNotEmpty()) chains.last().add(remJ.removeAt(0))
                else chains.add(mutableListOf(remJ.removeAt(0)))
            }

            if (chains.size >= 2 && chains.any { evaluateMeld(it) != null }) {
                return chains.map { sortMeldForDisplay(it, preferLeadingJoker) }
            }
        }

        // Case B: Same-number group overflow
        if (normals.all { it.number == normals[0].number } && tiles.size >= 4) {
            val grp1 = ArrayList<RmkTile>()
            val seenCols = HashSet<RmkColor>()
            val extras = ArrayList<RmkTile>()
            for (t in normals) {
                if (seenCols.add(t.color) && grp1.size < 4) grp1.add(t) else extras.add(t)
            }
            for (j in jokers) {
                if (grp1.size < 3) grp1.add(j) else extras.add(j)
            }
            if (evaluateMeld(grp1) != null && extras.isNotEmpty()) {
                return listOf(sortMeldForDisplay(grp1), sortMeldForDisplay(extras))
            }
        }

        return listOf(sortMeldForDisplay(tiles, preferLeadingJoker))
    }

    fun findBestMeld(hand: List<RmkTile>): List<RmkTile>? {
        val normals = hand.filter { !it.isJoker }
        val jokers = hand.filter { it.isJoker }
        var best: List<RmkTile>? = null
        var bestPts = 0

        for ((_, grp) in normals.groupBy { it.number }) {
            val uniq = ArrayList<RmkTile>()
            val seen = HashSet<RmkColor>()
            for (t in grp) if (seen.add(t.color)) uniq.add(t)
            if (uniq.size >= 3) {
                val pts = evaluateMeld(uniq) ?: 0
                if (pts > bestPts) { bestPts = pts; best = uniq }
            } else if (uniq.size == 2 && jokers.isNotEmpty()) {
                val cand = uniq + jokers[0]
                val pts = evaluateMeld(cand) ?: 0
                if (pts > bestPts) { bestPts = pts; best = cand }
            }
        }

        for ((_, grp) in normals.groupBy { it.color }) {
            val uniq = ArrayList<RmkTile>()
            val seen = HashSet<Int>()
            for (t in grp.sortedBy { it.number }) if (seen.add(t.number)) uniq.add(t)
            val cur = ArrayList<RmkTile>()
            for (t in uniq) {
                if (cur.isEmpty() || t.number == cur.last().number + 1) {
                    cur.add(t)
                } else {
                    if (cur.size >= 3) {
                        val pts = evaluateMeld(cur) ?: 0
                        if (pts > bestPts) { bestPts = pts; best = cur.toList() }
                    }
                    cur.clear(); cur.add(t)
                }
            }
            if (cur.size >= 3) {
                val pts = evaluateMeld(cur) ?: 0
                if (pts > bestPts) { bestPts = pts; best = cur.toList() }
            }
        }
        return best
    }

    fun organizeHandIntoGroups(hand: List<RmkTile>, preferRuns: Boolean): Pair<List<List<RmkTile>>, List<RmkTile>> {
        val remaining = hand.toMutableList()
        val melds = ArrayList<List<RmkTile>>()

        fun extractRuns() {
            var changed = true
            while (changed) {
                changed = false
                val byCol = remaining.filter { !it.isJoker }.groupBy { it.color }
                for (col in listOf(RmkColor.RED, RmkColor.BLUE, RmkColor.YELLOW, RmkColor.BLACK)) {
                    val grp = byCol[col] ?: continue
                    val uniq = ArrayList<RmkTile>()
                    val seen = HashSet<Int>()
                    for (t in grp.sortedBy { it.number }) if (seen.add(t.number)) uniq.add(t)
                    val run = ArrayList<RmkTile>()
                    for (t in uniq) {
                        if (run.isEmpty() || t.number == run.last().number + 1) run.add(t)
                        else {
                            if (run.size >= 3) break
                            run.clear(); run.add(t)
                        }
                    }
                    if (run.size >= 3) {
                        val copy = run.toList()
                        melds.add(copy)
                        val ids = copy.map { it.id }.toSet()
                        remaining.removeAll { ids.contains(it.id) }
                        changed = true
                        break
                    }
                }
            }
        }

        fun extractGroups() {
            var changed = true
            while (changed) {
                changed = false
                val byNum = remaining.filter { !it.isJoker }.groupBy { it.number }
                for (num in 13 downTo 1) {
                    val grp = byNum[num] ?: continue
                    val uniq = ArrayList<RmkTile>()
                    val seen = HashSet<RmkColor>()
                    for (t in grp) if (seen.add(t.color)) uniq.add(t)
                    if (uniq.size >= 3) {
                        val pick = uniq.take(4)
                        melds.add(pick)
                        val ids = pick.map { it.id }.toSet()
                        remaining.removeAll { ids.contains(it.id) }
                        changed = true
                        break
                    }
                }
            }
        }

        if (preferRuns) { extractRuns() }
        else { extractGroups() }

        while (true) {
            val jIdx = remaining.indexOfFirst { it.isJoker }
            if (jIdx < 0) break
            val joker = remaining[jIdx]
            var paired: List<RmkTile>? = null
            if (preferRuns) {
                val byCol = remaining.filter { !it.isJoker }.groupBy { it.color }
                for (col in listOf(RmkColor.RED, RmkColor.BLUE, RmkColor.YELLOW, RmkColor.BLACK)) {
                    val s = (byCol[col] ?: emptyList()).sortedBy { it.number }
                    if (s.size >= 2) {
                        for (i in 0 until s.size - 1) {
                            if (s[i + 1].number - s[i].number in 1..2) {
                                paired = listOf(s[i], s[i + 1], joker)
                                break
                            }
                        }
                    }
                    if (paired != null) break
                }
            }
            if (paired == null) {
                val byNum = remaining.filter { !it.isJoker }.groupBy { it.number }
                for (num in 13 downTo 1) {
                    val uniq = ArrayList<RmkTile>()
                    val seen = HashSet<RmkColor>()
                    for (t in (byNum[num] ?: emptyList())) if (seen.add(t.color)) uniq.add(t)
                    if (uniq.size == 2) { paired = listOf(uniq[0], uniq[1], joker); break }
                }
            }
            if (paired != null) {
                melds.add(paired)
                val ids = paired.map { it.id }.toSet()
                remaining.removeAll { ids.contains(it.id) }
            } else break
        }

        val sortedLeft = remaining.sortedWith(Comparator { a, b ->
            if (a.isJoker != b.isJoker) return@Comparator if (a.isJoker) 1 else -1
            if (preferRuns) {
                if (a.color != b.color) a.color.code.compareTo(b.color.code) else a.number - b.number
            } else {
                if (a.number != b.number) a.number - b.number else a.color.code.compareTo(b.color.code)
            }
        })
        return melds to sortedLeft
    }

    data class AITableMoveResult(
        val newMelds: List<RmkMeld>,
        val playedIds: Set<String>,
        val highlightedIds: Set<String>
    )

    fun findAITableCombinationMove(
        hand: List<RmkTile>,
        tableMelds: List<RmkMeld>,
        hasBrokenIce: Boolean
    ): AITableMoveResult? {
        var remHand = hand.toMutableList()
        val nextMelds = tableMelds.map { RmkMeld(it.id, it.tiles.toList()) }.toMutableList()
        val playedIds = HashSet<String>()
        val highlightedIds = HashSet<String>()

        // Step 1: Extract both 789 runs and 777 groups from hand
        val (rMelds, afterRuns) = organizeHandIntoGroups(remHand, true)
        val (gMelds, afterBoth) = organizeHandIntoGroups(afterRuns, false)
        val allHandMelds = rMelds + gMelds
        val totalHandPts = allHandMelds.sumOf { evaluateMeld(it) ?: 0 }

        var chosenHandMelds = allHandMelds
        if (!hasBrokenIce) {
            if (totalHandPts < 30) return null
            // On icebreak turn, play only minimum melds needed to reach >= 30 pts (official Rummikub pacing)
            val sortedByPts = allHandMelds.sortedByDescending { evaluateMeld(it) ?: 0 }
            val minMelds = mutableListOf<List<RmkTile>>()
            var accPts = 0
            for (m in sortedByPts) {
                minMelds.add(m)
                accPts += evaluateMeld(m) ?: 0
                if (accPts >= 30) break
            }
            chosenHandMelds = minMelds
        } else if (chosenHandMelds.size > 1) {
            val totalPlayedCount = chosenHandMelds.sumOf { it.size }
            if (totalPlayedCount < hand.size) {
                chosenHandMelds = chosenHandMelds.sortedByDescending { evaluateMeld(it) ?: 0 }.take(2)
            }
        }

        if (hasBrokenIce || totalHandPts >= 30) {
            for (m in chosenHandMelds) {
                val sortedM = sortMeldForDisplay(m)
                nextMelds.add(RmkMeld(UUID.randomUUID().toString(), sortedM))
                for (t in sortedM) {
                    playedIds.add(t.id)
                    highlightedIds.add(t.id)
                }
            }
            val playedSet = playedIds.toSet()
            remHand = hand.filterNot { playedSet.contains(it.id) }.toMutableList()
        }

        // Step 2: Only after already breaking ice on a prior turn can AI manipulate existing table melds
        if (hasBrokenIce) {
            var changed = true
            var tableActionsThisTurn = 0
            val maxTableActions = if (remHand.size <= 3) 4 else if (chosenHandMelds.isEmpty()) 2 else 1
            while (changed && tableActionsThisTurn < maxTableActions) {
                changed = false
                // 2A-Joker. Combine hand Joker + 1 hand tile + 1 spare table tile before ever appending Joker to a valid meld!
                val jIdx = remHand.indexOfFirst { it.isJoker }
                if (jIdx >= 0 && remHand.size >= 2) {
                    val jTile = remHand[jIdx]
                    outerJokerCombo@ for (hIdx in remHand.indices) {
                        if (hIdx == jIdx) continue
                        val ht = remHand[hIdx]
                        if (ht.isJoker) continue
                        for (mIdx in nextMelds.indices) {
                            val mTiles = nextMelds[mIdx].tiles
                            if (mTiles.size < 4) continue
                            for (cIdx in mTiles.indices) {
                                val spareTile = mTiles[cIdx]
                                val remainTable = mTiles.toMutableList().apply { removeAt(cIdx) }
                                if (evaluateMeld(remainTable) == null) continue
                                val newTriad = listOf(jTile, ht, spareTile)
                                if (evaluateMeld(newTriad) != null) {
                                    nextMelds[mIdx] = nextMelds[mIdx].copy(tiles = sortMeldForDisplay(remainTable))
                                    nextMelds.add(RmkMeld(UUID.randomUUID().toString(), sortMeldForDisplay(newTriad)))
                                    playedIds.add(jTile.id)
                                    playedIds.add(ht.id)
                                    highlightedIds.add(jTile.id)
                                    highlightedIds.add(ht.id)
                                    highlightedIds.add(spareTile.id)
                                    remHand.removeAll { it.id == jTile.id || it.id == ht.id }
                                    tableActionsThisTurn += 1
                                    changed = true
                                    break@outerJokerCombo
                                }
                            }
                        }
                    }
                    if (changed) continue
                }

                // 2A. Append/prepend any single NON-JOKER hand tile onto an existing table meld
                // (Only allow appending a Joker if it is AI's final winning tile!)
                outerSingle@ for (hIdx in remHand.indices) {
                    val ht = remHand[hIdx]
                    if (ht.isJoker && remHand.size > 1) continue
                    for (mIdx in nextMelds.indices) {
                        val cand = nextMelds[mIdx].tiles + ht
                        if (evaluateMeld(cand) != null) {
                            nextMelds[mIdx] = nextMelds[mIdx].copy(tiles = sortMeldForDisplay(cand))
                            playedIds.add(ht.id)
                            highlightedIds.add(ht.id)
                            remHand.removeAt(hIdx)
                            tableActionsThisTurn += 1
                            changed = true
                            break@outerSingle
                        }
                    }
                }
                if (changed) continue

                // 2B. Split 1 tile from a 4-tile table group or 4+ tile table run to combine with 2 hand tiles into a new valid meld!
                outerSplit@ for (mIdx in nextMelds.indices) {
                    val mTiles = nextMelds[mIdx].tiles
                    if (mTiles.size < 4) continue
                    val candIndices = listOf(0, mTiles.lastIndex, 1, mTiles.lastIndex - 1)
                    for (cIdx in candIndices) {
                        if (cIdx !in mTiles.indices) continue
                        val spareTile = mTiles[cIdx]
                        val remainTable = mTiles.toMutableList().apply { removeAt(cIdx) }
                        if (evaluateMeld(remainTable) == null) continue
                        if (remHand.size >= 2) {
                            for (i in 0 until remHand.size - 1) {
                                for (j in (i + 1) until remHand.size) {
                                    val newTriad = listOf(spareTile, remHand[i], remHand[j])
                                    if (evaluateMeld(newTriad) != null) {
                                        val h1 = remHand[i]
                                        val h2 = remHand[j]
                                        nextMelds[mIdx] = nextMelds[mIdx].copy(tiles = sortMeldForDisplay(remainTable))
                                        val sortedTriad = sortMeldForDisplay(newTriad)
                                        nextMelds.add(RmkMeld(UUID.randomUUID().toString(), sortedTriad))
                                        playedIds.add(h1.id)
                                        playedIds.add(h2.id)
                                        highlightedIds.add(spareTile.id)
                                        highlightedIds.add(h1.id)
                                        highlightedIds.add(h2.id)
                                        remHand.removeAll { it.id == h1.id || it.id == h2.id }
                                        tableActionsThisTurn += 1
                                        changed = true
                                        break@outerSplit
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (playedIds.isEmpty()) return null
        return AITableMoveResult(nextMelds, playedIds, highlightedIds)
    }

}

object RmkSoundFX {
    private data class Note(val freq: Double, val dur: Double, val amp: Double, val harmonic: Double)

    private fun playNotes(notes: List<Note>) {
        Thread {
            try {
                val sampleRate = 44100
                val totalSamples = notes.sumOf { (sampleRate * it.dur).toInt().coerceAtLeast(1) }
                val pcm = ShortArray(totalSamples)
                var offset = 0
                for (n in notes) {
                    val count = (sampleRate * n.dur).toInt().coerceAtLeast(1)
                    val attackSamples = (sampleRate * 0.004).toInt().coerceAtLeast(1)
                    for (i in 0 until count) {
                        val t = i.toDouble() / sampleRate
                        val prog = i.toDouble() / count
                        val attack = (i.toDouble() / attackSamples).coerceAtMost(1.0)
                        val decay = kotlin.math.exp(-3.8 * prog)
                        val env = attack * decay
                        val f1 = kotlin.math.sin(2.0 * Math.PI * n.freq * t)
                        val f2 = 0.32 * kotlin.math.sin(2.0 * Math.PI * (n.freq * n.harmonic) * t)
                        val f3 = 0.14 * kotlin.math.sin(2.0 * Math.PI * (n.freq * 3.0) * t)
                        val raw = ((f1 + f2 + f3) * n.amp * env).coerceIn(-0.98, 0.98)
                        pcm[offset + i] = (raw * 32767.0).toInt().toShort()
                    }
                    offset += count
                }
                val minBuf = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                ).coerceAtLeast(2048)
                val finalPcm = if (pcm.size * 2 < minBuf) {
                    ShortArray((minBuf + 1) / 2).also { System.arraycopy(pcm, 0, it, 0, pcm.size) }
                } else pcm
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(finalPcm.size * 2)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()
                track.write(finalPcm, 0, finalPcm.size)
                track.play()
                Thread.sleep((totalSamples * 1000L / sampleRate) + 80L)
                track.release()
            } catch (_: Exception) {}
        }.start()
    }

    /** Fixed, unmistakable special chime played every time the player gets a Joker tile! */
    fun playJokerAcquired() = playNotes(listOf(
        Note(523.25, 0.075, 0.48, 2.0),
        Note(659.25, 0.075, 0.50, 2.0),
        Note(783.99, 0.080, 0.52, 2.0),
        Note(987.77, 0.085, 0.54, 2.0),
        Note(1046.50, 0.110, 0.58, 3.0),
        Note(1318.51, 0.240, 0.62, 2.0)
    ))

    fun playTileClick() = playNotes(listOf(
        Note(1480.0, 0.022, 0.36, 1.5),
        Note(680.0, 0.028, 0.28, 1.2)
    ))

    fun playTileSnap() = playNotes(listOf(
        Note(880.0, 0.028, 0.36, 1.5),
        Note(1320.0, 0.045, 0.42, 2.0)
    ))

    fun playMeldSplit() = playNotes(listOf(
        Note(1180.0, 0.032, 0.40, 1.8),
        Note(820.0, 0.030, 0.34, 1.5),
        Note(1560.0, 0.055, 0.44, 2.0)
    ))

    fun playTileDraw() = playNotes(listOf(
        Note(460.0, 0.035, 0.30, 1.2),
        Note(740.0, 0.045, 0.36, 1.5)
    ))

    fun playRackOrganize() = playNotes(listOf(
        Note(587.33, 0.030, 0.32, 1.5),
        Note(739.99, 0.030, 0.34, 1.5),
        Note(880.00, 0.035, 0.36, 1.5),
        Note(1174.66, 0.060, 0.40, 2.0)
    ))

    fun playTurnCommit() = playNotes(listOf(
        Note(659.25, 0.065, 0.44, 2.0),
        Note(783.99, 0.065, 0.46, 2.0),
        Note(1046.50, 0.160, 0.52, 2.0)
    ))

    fun playUndo() = playNotes(listOf(
        Note(784.0, 0.040, 0.32, 1.3),
        Note(523.25, 0.055, 0.30, 1.2)
    ))

    fun playRoundWin() = playNotes(listOf(
        Note(523.25, 0.09, 0.50, 2.0),
        Note(659.25, 0.09, 0.52, 2.0),
        Note(783.99, 0.09, 0.54, 2.0),
        Note(1046.50, 0.28, 0.60, 2.5)
    ))
}

class RummikubEngine(
    private val context: Context,
    private val audioManager: AudioPlayerManager
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("HTT_Rmk", Context.MODE_PRIVATE)
    private val httpClient = OkHttpClient()
    private val rmkBitmaps = HashMap<String, Bitmap>()

    private val _phase = MutableStateFlow(RmkGamePhase.LOBBY)
    val phase: StateFlow<RmkGamePhase> = _phase.asStateFlow()

    private val _roomPlayerCount = MutableStateFlow(4)
    val roomPlayerCount: StateFlow<Int> = _roomPlayerCount.asStateFlow()

    private val _seats = MutableStateFlow<List<RmkSeat>>(emptyList())
    val seats: StateFlow<List<RmkSeat>> = _seats.asStateFlow()

    private val _tableMelds = MutableStateFlow<List<RmkMeld>>(emptyList())
    val tableMelds: StateFlow<List<RmkMeld>> = _tableMelds.asStateFlow()

    private val _poolCount = MutableStateFlow(0)
    val poolCount: StateFlow<Int> = _poolCount.asStateFlow()

    private val _mySeatIndex = MutableStateFlow(0)
    val mySeatIndex: StateFlow<Int> = _mySeatIndex.asStateFlow()

    private val _currentTurnSeat = MutableStateFlow(0)
    val currentTurnSeat: StateFlow<Int> = _currentTurnSeat.asStateFlow()

    private val _selectedTileIds = MutableStateFlow<Set<String>>(emptySet())
    val selectedTileIds: StateFlow<Set<String>> = _selectedTileIds.asStateFlow()

    private val _lastTurnHighlightedTileIds = MutableStateFlow<Set<String>>(emptySet())
    val lastTurnHighlightedTileIds: StateFlow<Set<String>> = _lastTurnHighlightedTileIds.asStateFlow()

    private val _selectedTableTileSource = MutableStateFlow<Pair<String, String>?>(null)
    val selectedTableTileSource: StateFlow<Pair<String, String>?> = _selectedTableTileSource.asStateFlow()

    private val _turnRemainingSeconds = MutableStateFlow(60)
    val turnRemainingSeconds: StateFlow<Int> = _turnRemainingSeconds.asStateFlow()

    private val _statusBanner = MutableStateFlow("欢迎来到轻音拉密数字牌 (2~4人自由开房 · 30分破冰 · 60秒限时)")
    val statusBanner: StateFlow<String> = _statusBanner.asStateFlow()

    private val _sortByColor = MutableStateFlow(false)
    val sortByColor: StateFlow<Boolean> = _sortByColor.asStateFlow()

    private val _myNickname = MutableStateFlow(prefs.getString("nick", "轻音车友") ?: "轻音车友")
    val myNickname: StateFlow<String> = _myNickname.asStateFlow()

    private val _myCharacter = MutableStateFlow(CharacterFilter.YUI)
    val myCharacter: StateFlow<CharacterFilter> = _myCharacter.asStateFlow()

    private val _roomCode = MutableStateFlow("")
    val roomCode: StateFlow<String> = _roomCode.asStateFlow()

    private val _serverUrl = MutableStateFlow("wss://azusa.online/ddz")
    val serverUrl: StateFlow<String> = _serverUrl.asStateFlow()

    private val _networkMode = MutableStateFlow(RmkNetworkMode.ONLINE_SERVER)
    val networkMode: StateFlow<RmkNetworkMode> = _networkMode.asStateFlow()

    private val _isHostingRoom = MutableStateFlow(false)
    val isHostingRoom: StateFlow<Boolean> = _isHostingRoom.asStateFlow()

    private val _isScanningRooms = MutableStateFlow(false)
    val isScanningRooms: StateFlow<Boolean> = _isScanningRooms.asStateFlow()

    private val _discoveredRooms = MutableStateFlow<List<DiscoveredP2PRoom>>(emptyList())
    val discoveredRooms: StateFlow<List<DiscoveredP2PRoom>> = _discoveredRooms.asStateFlow()

    private val _directConnectIp = MutableStateFlow("")
    val directConnectIp: StateFlow<String> = _directConnectIp.asStateFlow()

    private val _localIpAddress = MutableStateFlow("192.168.43.1")
    val localIpAddress: StateFlow<String> = _localIpAddress.asStateFlow()

    private val _isServerConnected = MutableStateFlow(false)
    val isServerConnected: StateFlow<Boolean> = _isServerConnected.asStateFlow()

    private val _isRoomAuthority = MutableStateFlow(true)
    val isRoomAuthority: StateFlow<Boolean> = _isRoomAuthority.asStateFlow()

    private val tcpPort = 19193
    private val udpPort = 19194
    private var tcpServerSocket: ServerSocket? = null
    private var udpSocket: DatagramSocket? = null
    private val lanWriters = CopyOnWriteArrayList<BufferedWriter>()

    private val _connectedPeerNames = MutableStateFlow<List<String>>(emptyList())
    val connectedPeerNames: StateFlow<List<String>> = _connectedPeerNames.asStateFlow()

    private val _currentRound = MutableStateFlow(1)
    val currentRound: StateFlow<Int> = _currentRound.asStateFlow()

    private val _isEditingTable = MutableStateFlow(false)
    val isEditingTable: StateFlow<Boolean> = _isEditingTable.asStateFlow()

    private val _workingMelds = MutableStateFlow<List<RmkMeld>>(emptyList())
    val workingMelds: StateFlow<List<RmkMeld>> = _workingMelds.asStateFlow()

    private val _workingHand = MutableStateFlow<List<RmkTile>>(emptyList())
    val workingHand: StateFlow<List<RmkTile>> = _workingHand.asStateFlow()

    private val _rackCols = MutableStateFlow(10)
    val rackCols: StateFlow<Int> = _rackCols.asStateFlow()

    private val _rackSlots = MutableStateFlow<List<RmkTile?>>(List(20) { null })
    val rackSlots: StateFlow<List<RmkTile?>> = _rackSlots.asStateFlow()

    private val _liftedSlotIndex = MutableStateFlow<Int?>(null)
    val liftedSlotIndex: StateFlow<Int?> = _liftedSlotIndex.asStateFlow()

    private val _dealingVisibleCount = MutableStateFlow(99)
    val dealingVisibleCount: StateFlow<Int> = _dealingVisibleCount.asStateFlow()

    private val _isDealingAnimation = MutableStateFlow(false)
    val isDealingAnimation: StateFlow<Boolean> = _isDealingAnimation.asStateFlow()

    private val _isDrawingAnimation = MutableStateFlow(false)
    val isDrawingAnimation: StateFlow<Boolean> = _isDrawingAnimation.asStateFlow()

    private val _drawingAnimatedTile = MutableStateFlow<RmkTile?>(null)
    val drawingAnimatedTile: StateFlow<RmkTile?> = _drawingAnimatedTile.asStateFlow()

    private val _drawnTargetSlotIndex = MutableStateFlow(0)
    val drawnTargetSlotIndex: StateFlow<Int> = _drawnTargetSlotIndex.asStateFlow()

    private val _opponentDrawingSeatIndex = MutableStateFlow<Int?>(null)
    val opponentDrawingSeatIndex: StateFlow<Int?> = _opponentDrawingSeatIndex.asStateFlow()

    private val _opponentPlayingSeatIndex = MutableStateFlow<Int?>(null)
    val opponentPlayingSeatIndex: StateFlow<Int?> = _opponentPlayingSeatIndex.asStateFlow()

    private val _opponentPlayingTile = MutableStateFlow<RmkTile?>(null)
    val opponentPlayingTile: StateFlow<RmkTile?> = _opponentPlayingTile.asStateFlow()

    private val _opponentPlayingTargetMeldId = MutableStateFlow<String?>(null)
    val opponentPlayingTargetMeldId: StateFlow<String?> = _opponentPlayingTargetMeldId.asStateFlow()

    fun hasUncommittedTableChanges(): Boolean {
        if (!_isEditingTable.value) return false
        return _workingMelds.value != snapshotMelds || _workingHand.value.size != snapshotHand.size
    }

    fun syncEditingStateWithSnapshot() {
        if (_isEditingTable.value && _workingMelds.value == snapshotMelds && _workingHand.value.size == snapshotHand.size) {
            _isEditingTable.value = false
            _selectedTableTileSource.value = null
        }
    }

    private var snapshotMelds: List<RmkMeld> = emptyList()
    private var snapshotHand: List<RmkTile> = emptyList()
    private var snapshotRackSlots: List<RmkTile?> = emptyList()
    private val pool = ArrayList<RmkTile>()
    private var consecutiveEmptyPoolPasses = 0
    private var myPeerName: String = ""
    private var orderedRoomPeers = mutableListOf<Triple<String, Int, String>>()
    private var webSocket: WebSocket? = null
    private var aiRunnable: Runnable? = null
    private var timerRunnable: Runnable? = null

    init {
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        loadRmkAssets()
        rebuildLobbySeats()
    }

    private fun loadRmkAssets() {
        Thread {
            try {
                context.assets.open("doudizhu_cards.zip").use { fis ->
                    ZipInputStream(fis).use { zis ->
                        var entry = zis.nextEntry
                        while (entry != null) {
                            val name = entry.name.substringAfterLast("/")
                            if (name.startsWith("rmk_") || name == "icon_rummikub.png") {
                                val bytes = zis.readBytes()
                                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bmp ->
                                    synchronized(rmkBitmaps) { rmkBitmaps[name] = bmp }
                                }
                            }
                            zis.closeEntry()
                            entry = zis.nextEntry
                        }
                    }
                }
            } catch (_: Exception) {}
        }.start()
    }

    fun getAssetBitmap(name: String): Bitmap? = synchronized(rmkBitmaps) { rmkBitmaps[name] }

    private fun cleanNick(): String = _myNickname.value.trim().ifEmpty { "轻音车友" }
    private fun cleanPeer(raw: String): String = raw.substringBeforeLast("#").trim().ifEmpty { raw }
    fun wireRoomCode(): String = _roomCode.value.trim().let { if (it.isEmpty()) "" else "RMK_$it" }

    fun setNickname(n: String) { _myNickname.value = n; prefs.edit().putString("nick", n).apply(); rebuildLobbySeats() }
    fun setCharacter(c: CharacterFilter) { _myCharacter.value = c; rebuildLobbySeats() }
    fun setNetworkMode(m: RmkNetworkMode) { _networkMode.value = m }
    fun setDirectConnectIp(ip: String) { _directConnectIp.value = ip }
    fun setRoomCode(c: String) { _roomCode.value = c }
    fun setServerUrl(u: String) { _serverUrl.value = u }
    fun setRoomPlayerCount(cnt: Int) {
        val c = cnt.coerceIn(2, 4)
        if (_roomPlayerCount.value != c && _phase.value == RmkGamePhase.LOBBY) {
            _roomPlayerCount.value = c
            rebuildLobbySeats()
            if ((_isServerConnected.value || _isHostingRoom.value || lanWriters.isNotEmpty()) && _isRoomAuthority.value) {
                broadcastRoster()
                broadcastFullState()
            }
        }
    }

    private fun build106Deck(): List<RmkTile> {
        val deck = ArrayList<RmkTile>(106)
        for (copy in 1..2) {
            for (col in listOf(RmkColor.RED, RmkColor.BLUE, RmkColor.YELLOW, RmkColor.BLACK)) {
                for (num in 1..13) deck.add(RmkTile("${col.code}_${num}_$copy", col, num))
            }
        }
        deck.add(RmkTile("J_1", RmkColor.JOKER, 0))
        deck.add(RmkTile("J_2", RmkColor.JOKER, 0))
        deck.shuffle()
        return deck
    }

    private fun sortHand(tiles: List<RmkTile>): List<RmkTile> = tiles.sortedWith(Comparator { a, b ->
        if (a.isJoker != b.isJoker) return@Comparator if (a.isJoker) 1 else -1
        if (_sortByColor.value) {
            if (a.color != b.color) a.color.code.compareTo(b.color.code) else a.number - b.number
        } else {
            if (a.number != b.number) a.number - b.number else a.color.code.compareTo(b.color.code)
        }
    })

    private fun currentCanonicalHand(): List<RmkTile> {
        if (_isEditingTable.value) return _workingHand.value
        val s = _seats.value.getOrNull(_mySeatIndex.value)
        if (s != null && s.hand.isNotEmpty()) return s.hand
        return _rackSlots.value.filterNotNull()
    }

    // Strictly 10 columns per row (2 rows = 20 slots total); ONLY expands beyond 10 columns when > 20 tiles!
    fun syncRackFromHand(tiles: List<RmkTile>, preserveExistingPositions: Boolean = true) {
        val targetCols = if (tiles.size <= 20) 10 else ((tiles.size + 1) / 2)
        if (!preserveExistingPositions || _rackSlots.value.isEmpty()) {
            _rackCols.value = targetCols
            val next = MutableList<RmkTile?>(targetCols * 2) { null }
            val topCnt = minOf(targetCols, (tiles.size + 1) / 2)
            for (i in tiles.indices) {
                if (i < topCnt) next[i] = tiles[i]
                else {
                    val bIdx = targetCols + (i - topCnt)
                    if (bIdx < next.size) next[bIdx] = tiles[i]
                }
            }
            _rackSlots.value = next
            return
        }
        val handMap = tiles.associateBy { it.id }
        val placedIds = HashSet<String>()
        val oldCols = maxOf(1, _rackSlots.value.size / 2)
        val finalCols = maxOf(targetCols, if (tiles.size > 20) oldCols else 10)
        var updated = MutableList<RmkTile?>(finalCols * 2) { null }

        for (r in 0..1) {
            for (c in 0 until minOf(oldCols, finalCols)) {
                val oldIdx = r * oldCols + c
                val newIdx = r * finalCols + c
                val keep = _rackSlots.value.getOrNull(oldIdx)?.let { handMap[it.id] }
                if (keep != null && placedIds.add(keep.id)) {
                    updated[newIdx] = keep
                }
            }
        }
        for (slot in _rackSlots.value) {
            val keep = slot?.let { handMap[it.id] }
            if (keep != null && !placedIds.contains(keep.id)) {
                val emptyIdx = updated.indexOfFirst { it == null }
                if (emptyIdx >= 0) {
                    updated[emptyIdx] = keep
                    placedIds.add(keep.id)
                }
            }
        }
        val missing = tiles.filterNot { placedIds.contains(it.id) }
        for (m in missing) {
            var emptyIdx = updated.indexOfFirst { it == null }
            if (emptyIdx < 0) {
                updated = extendRackColumnsInternal(1, updated)
                emptyIdx = updated.indexOfFirst { it == null }
            }
            if (emptyIdx >= 0) {
                updated[emptyIdx] = m
                placedIds.add(m.id)
            }
        }
        _rackCols.value = maxOf(10, updated.size / 2)
        _rackSlots.value = updated
    }

    private fun extendRackColumnsInternal(extraCols: Int, cur: MutableList<RmkTile?>): MutableList<RmkTile?> {
        val oldCols = maxOf(1, cur.size / 2)
        val newCols = oldCols + extraCols
        val next = MutableList<RmkTile?>(newCols * 2) { null }
        for (c in 0 until oldCols) {
            next[c] = cur[c]
            next[newCols + c] = cur[oldCols + c]
        }
        _rackCols.value = newCols
        return next
    }

    fun setLiftedSlot(idx: Int?) { _liftedSlotIndex.value = idx }

    // Move or swap a tile on the fixed 2-row rack (NEVER stretches rack length unless > 20 tiles!)
    fun moveRackSlot(srcIdx: Int, dstIdx: Int) {
        val cur = _rackSlots.value.toMutableList()
        if (srcIdx !in cur.indices || dstIdx !in cur.indices || srcIdx == dstIdx) {
            _liftedSlotIndex.value = null
            return
        }
        val tmp = cur[dstIdx]
        cur[dstIdx] = cur[srcIdx]
        cur[srcIdx] = tmp
        _liftedSlotIndex.value = null
        _rackSlots.value = cur
        RmkSoundFX.playTileClick()
    }

    fun shuffleRackRandomly() {
        val active = currentCanonicalHand().shuffled()
        if (_isEditingTable.value) _workingHand.value = active
        syncRackFromHand(active, preserveExistingPositions = false)
        _selectedTileIds.value = emptySet()
        _selectedTableTileSource.value = null
        _liftedSlotIndex.value = null
        _statusBanner.value = "🎲 已随机打乱牌架顺序（可点击或拖拽任意牌自由移动位置）"
    }

    fun organizeRack(preferRuns: Boolean) {
        _sortByColor.value = preferRuns
        val active = currentCanonicalHand()
        val (rawMelds, leftovers) = RmkEvaluator.organizeHandIntoGroups(active, preferRuns)
        val melds = rawMelds.map { RmkEvaluator.sortMeldForDisplay(it) }
        val targetCols = if (active.size <= 20) 10 else ((active.size + 1) / 2)
        var spareGaps = maxOf(0, targetCols * 2 - active.size)
        val row0 = ArrayList<RmkTile?>()
        val row1 = ArrayList<RmkTile?>()

        for (meld in melds) {
            if (row0.size + meld.size <= targetCols) {
                row0.addAll(meld)
                if (spareGaps > 0 && row0.size < targetCols) { row0.add(null); spareGaps-- }
            } else if (row1.size + meld.size <= targetCols) {
                row1.addAll(meld)
                if (spareGaps > 0 && row1.size < targetCols) { row1.add(null); spareGaps-- }
            } else {
                for (t in meld) {
                    if (row0.size < targetCols) row0.add(t) else row1.add(t)
                }
                if (spareGaps > 0 && row1.size < targetCols) { row1.add(null); spareGaps-- }
            }
        }
        for (t in leftovers) {
            if (row0.size < targetCols) row0.add(t)
            else if (row1.size < targetCols) row1.add(t)
            else {
                val n0 = row0.lastIndexOf(null)
                val n1 = row1.lastIndexOf(null)
                if (n0 >= 0) row0[n0] = t
                else if (n1 >= 0) row1[n1] = t
                else row1.add(t)
            }
        }
        val finalCols = if (active.size <= 20) 10 else maxOf(targetCols, maxOf(row0.size, row1.size))
        _rackCols.value = finalCols
        val next = MutableList<RmkTile?>(finalCols * 2) { null }
        for (i in row0.indices) if (i < finalCols) next[i] = row0[i]
        for (i in row1.indices) if (i < finalCols) next[finalCols + i] = row1[i]
        _rackSlots.value = next
        _liftedSlotIndex.value = null
        _selectedTileIds.value = emptySet()
        RmkSoundFX.playRackOrganize()
        _statusBanner.value = if (melds.isNotEmpty()) {
            "✨ [${if (preferRuns) "789类型组合" else "777(888)类型组合"}] 共识别 ${melds.size} 组可出牌型（已自动留空隔开，不混入其他类型）"
        } else {
            if (preferRuns) "🔢 [789类型组合] 当前暂无可出顺子（未混入同数群组）" else "🔢 [777(888)类型组合] 当前暂无可出同数群组（未混入顺子）"
        }
    }

    fun toggleSortMode() {
        organizeRack(!_sortByColor.value)
    }

    fun rebuildLobbySeats() {
        val cap = _roomPlayerCount.value.coerceIn(2, 4)
        if (orderedRoomPeers.isEmpty()) orderedRoomPeers.add(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        else {
            val idx = orderedRoomPeers.indexOfFirst { it.first == myPeerName }
            if (idx >= 0) orderedRoomPeers[idx] = Triple(myPeerName, _myCharacter.value.charId, cleanNick())
        }
        _isRoomAuthority.value = (orderedRoomPeers.first().first == myPeerName)
        val used = HashSet<Int>()
        val list = ArrayList<RmkSeat>(cap)
        val old = _seats.value
        for (i in 0 until cap) {
            val ps = old.getOrNull(i)?.score ?: 1000
            if (i < orderedRoomPeers.size) {
                val rp = orderedRoomPeers[i]
                if (rp.first == myPeerName) _mySeatIndex.value = i
                used.add(rp.second)
                val tag = if (i == 0) "👑房主 " else "${i + 1}号 "
                list.add(RmkSeat(i, tag + cleanPeer(rp.third), rp.second, false, rp.first, emptyList(), false, ps))
            } else {
                val ac = CharacterFilter.fiveIndividuals.firstOrNull { !used.contains(it.charId) }?.charId ?: ((i % 5) + 1)
                used.add(ac)
                val an = CharacterFilter.fiveIndividuals.firstOrNull { it.charId == ac }?.displayName(audioManager.language.value) ?: "轻音AI"
                list.add(RmkSeat(i, "$an (AI)", ac, true, "AI_$i", emptyList(), false, ps))
            }
        }
        _seats.value = list
    }

    private fun refreshLocalIpAddress(): String {
        try {
            val ifaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in ifaces) {
                if (!intf.isUp || intf.isLoopback) continue
                for (addr in Collections.list(intf.inetAddresses)) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        _localIpAddress.value = ip
                        return ip
                    }
                }
            }
        } catch (_: Exception) {}
        return _localIpAddress.value
    }

    private fun sendPacketText(jsonStr: String) {
        if (_isServerConnected.value) {
            webSocket?.send(jsonStr)
        }
        if (lanWriters.isNotEmpty()) {
            Thread {
                for (w in lanWriters) {
                    try {
                        synchronized(w) { w.write(jsonStr); w.newLine(); w.flush() }
                    } catch (_: Exception) {
                        lanWriters.remove(w)
                    }
                }
            }.start()
        }
    }

    private fun attachLanSocket(sock: Socket) {
        Thread {
            try {
                val writer = BufferedWriter(OutputStreamWriter(sock.getOutputStream(), Charsets.UTF_8))
                lanWriters.add(writer)
                if (!_isRoomAuthority.value) {
                    val joinJson = JSONObject().apply {
                        put("kind", "joinRequest"); put("roomCode", wireRoomCode())
                        put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                        put("maxPlayers", _roomPlayerCount.value); put("gameType", "rummikub")
                    }.toString()
                    synchronized(writer) { writer.write(joinJson); writer.newLine(); writer.flush() }
                }
                val reader = BufferedReader(InputStreamReader(sock.getInputStream(), Charsets.UTF_8))
                while (!sock.isClosed) {
                    val line = reader.readLine() ?: break
                    if (line.isNotBlank()) mainHandler.post { handleIncomingJson(line) }
                }
            } catch (_: Exception) {
            } finally {
                try { sock.close() } catch (_: Exception) {}
            }
        }.start()
    }

    fun startHostingFaceToFaceRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号再创建面对面房间！"; return }
        stopNetworking()
        _roomCode.value = code
        _currentRound.value = 1
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        orderedRoomPeers = mutableListOf(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        val ip = refreshLocalIpAddress()
        _isHostingRoom.value = true
        _isRoomAuthority.value = true
        _isScanningRooms.value = false
        _mySeatIndex.value = 0
        rebuildLobbySeats()

        Thread {
            try {
                val srv = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(tcpPort)) }
                tcpServerSocket = srv
                while (_isHostingRoom.value && !srv.isClosed) {
                    val sock = srv.accept()
                    attachLanSocket(sock)
                }
            } catch (_: Exception) {}
        }.start()

        Thread {
            try {
                val ds = DatagramSocket().apply { broadcast = true }
                udpSocket = ds
                while (_isHostingRoom.value && !ds.isClosed) {
                    val payload = JSONObject().apply {
                        put("type", "kon_rmk_room")
                        put("code", _roomCode.value)
                        put("host", cleanNick())
                        put("char", _myCharacter.value.charId)
                        put("ip", refreshLocalIpAddress())
                        put("port", tcpPort)
                    }.toString().toByteArray(Charsets.UTF_8)
                    try { ds.send(DatagramPacket(payload, payload.size, InetAddress.getByName("255.255.255.255"), udpPort)) } catch (_: Exception) {}
                    Thread.sleep(1200)
                }
            } catch (_: Exception) {}
        }.start()

        _statusBanner.value = "🔢 面对面拉密房间 [$code] 已创建！本机IP: $ip (${_roomPlayerCount.value}人局 · 仅限安卓直连)"
        audioManager.playMascotVoice(_myCharacter.value)
    }

    fun startScanningFaceToFaceRooms() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号再扫描！"; return }
        stopNetworking()
        _roomCode.value = code
        _isHostingRoom.value = false
        _isScanningRooms.value = true
        _discoveredRooms.value = emptyList()
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"

        Thread {
            try {
                val ds = DatagramSocket(null).apply { reuseAddress = true; bind(InetSocketAddress(udpPort)); soTimeout = 1500 }
                udpSocket = ds
                val buf = ByteArray(2048)
                while (_isScanningRooms.value && !ds.isClosed) {
                    try {
                        val pkt = DatagramPacket(buf, buf.size)
                        ds.receive(pkt)
                        val json = JSONObject(String(pkt.data, 0, pkt.length, Charsets.UTF_8))
                        if (json.optString("type") == "kon_rmk_room" && json.optString("code").trim() == _roomCode.value.trim()) {
                            val ip = json.optString("ip").ifBlank { pkt.address.hostAddress ?: "" }
                            val r = DiscoveredP2PRoom("$ip:$tcpPort", json.optString("code"), "${json.optString("host")} ($ip)", json.optInt("char", 1), ip, tcpPort)
                            mainHandler.post {
                                val cur = _discoveredRooms.value.toMutableList()
                                if (cur.none { it.id == r.id }) { cur.add(r); _discoveredRooms.value = cur }
                            }
                        }
                    } catch (_: SocketTimeoutException) {}
                }
            } catch (_: Exception) {}
        }.start()
        _statusBanner.value = "🔍 正在扫描房号 [$code] 的面对面拉密房间..."
    }

    fun connectDirectToHostIp() {
        val raw = _directConnectIp.value.trim()
        if (raw.isEmpty()) { _statusBanner.value = "⚠️ 请输入房主 IP"; return }
        val host = raw.substringBefore(":")
        val port = raw.substringAfter(":", "$tcpPort").toIntOrNull() ?: tcpPort
        joinDiscoveredRoom(DiscoveredP2PRoom("$host:$port", _roomCode.value, "IP直连($host)", 1, host, port))
    }

    fun joinDiscoveredRoom(room: DiscoveredP2PRoom) {
        val code = _roomCode.value.trim()
        if (code.isEmpty() || room.roomCode != code) { _statusBanner.value = "⚠️ 房号不匹配！"; return }
        _isScanningRooms.value = false
        _isRoomAuthority.value = false
        Thread {
            try {
                val sock = Socket()
                sock.connect(InetSocketAddress(room.hostAddress, room.port), 5000)
                attachLanSocket(sock)
                mainHandler.post { _statusBanner.value = "✅ 已直连到 [${room.hostName}] 的面对面拉密房间" }
            } catch (e: Exception) {
                mainHandler.post { _statusBanner.value = "⚠️ 连接失败: ${e.message}" }
            }
        }.start()
    }

    fun connectOnlineServerRoom() {
        val code = _roomCode.value.trim()
        if (code.isEmpty()) { _statusBanner.value = "⚠️ 请先填写房号！"; return }
        stopNetworking()
        myPeerName = "${cleanNick()}#${Random.nextInt(100, 999)}"
        orderedRoomPeers = mutableListOf(Triple(myPeerName, _myCharacter.value.charId, cleanNick()))
        _isRoomAuthority.value = false
        _isServerConnected.value = true
        val req = Request.Builder().url(_serverUrl.value.trim()).build()
        webSocket = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) { mainHandler.post { sendJoinRequest() } }
            override fun onMessage(ws: WebSocket, text: String) { mainHandler.post { handleIncomingJson(text) } }
            override fun onMessage(ws: WebSocket, bytes: ByteString) { mainHandler.post { handleIncomingJson(bytes.utf8()) } }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { mainHandler.post { _isServerConnected.value = false } }
        })
    }

    private fun sendJoinRequest() {
        val wc = wireRoomCode()
        if (wc.isEmpty()) return
        sendPacketText(JSONObject().apply {
            put("kind", "joinRequest"); put("roomCode", wc)
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", _roomPlayerCount.value); put("gameType", "rummikub")
        }.toString())
        _statusBanner.value = "✅ 已连接拉密数字牌房间 [${_roomCode.value}] (${_roomPlayerCount.value}人局 · 真人进房自动替换AI)"
    }

    private fun broadcastRoster() {
        val inRoom = _isServerConnected.value || _isHostingRoom.value || lanWriters.isNotEmpty()
        if (!inRoom || !_isRoomAuthority.value || wireRoomCode().isEmpty()) return
        val peersArr = JSONArray()
        orderedRoomPeers.forEach { rp -> peersArr.put(JSONObject().apply { put("name", rp.first); put("charId", rp.second); put("displayName", rp.third) }) }
        sendPacketText(JSONObject().apply {
            put("kind", "roomRoster"); put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", _roomPlayerCount.value)
            put("hostPeerName", myPeerName); put("roomPeers", peersArr)
        }.toString())
    }

    fun leaveRoomAndResetLobby() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        val wc = wireRoomCode()
        if ((_isServerConnected.value || _isHostingRoom.value || lanWriters.isNotEmpty()) && wc.isNotEmpty()) {
            sendPacketText(JSONObject().apply {
                put("kind", "leaveRoom"); put("roomCode", wc)
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            }.toString())
        }
        stopNetworking()
        _phase.value = RmkGamePhase.LOBBY
        _currentRound.value = 1
        rebuildLobbySeats()
        _statusBanner.value = "已退出拉密数字牌房间"
    }

    private fun stopNetworking() {
        webSocket?.close(1000, "leave"); webSocket = null
        try { tcpServerSocket?.close() } catch (_: Exception) {}; tcpServerSocket = null
        try { udpSocket?.close() } catch (_: Exception) {}; udpSocket = null
        lanWriters.clear()
        _isServerConnected.value = false; _isHostingRoom.value = false; _isScanningRooms.value = false
        _discoveredRooms.value = emptyList(); _connectedPeerNames.value = emptyList(); orderedRoomPeers.clear()
    }

    private fun tileToJson(t: RmkTile) = JSONObject().apply { put("id", t.id); put("color", t.color.code); put("number", t.number) }
    private fun tileFromJson(o: JSONObject) = RmkTile(o.optString("id"), RmkColor.fromCode(o.optString("color", "R")), o.optInt("number", 1))

    private fun broadcastFullState() {
        if ((!_isServerConnected.value && !_isHostingRoom.value && lanWriters.isEmpty()) || !_isRoomAuthority.value || wireRoomCode().isEmpty()) return
        val peersArr = JSONArray()
        orderedRoomPeers.forEach { rp -> peersArr.put(JSONObject().apply { put("name", rp.first); put("charId", rp.second); put("displayName", rp.third) }) }
        val seatsArr = JSONArray()
        _seats.value.forEach { s ->
            val hArr = JSONArray()
            s.hand.forEach { hArr.put(tileToJson(it)) }
            seatsArr.put(JSONObject().apply {
                put("id", s.id); put("name", s.name); put("characterId", s.characterId); put("isAI", s.isAI)
                put("peerDisplayName", s.peerDisplayName); put("hand", hArr); put("hasBrokenIce", s.hasBrokenIce); put("score", s.score)
            })
        }
        val meldsArr = JSONArray()
        _tableMelds.value.forEach { m ->
            val tArr = JSONArray()
            m.tiles.forEach { tArr.put(tileToJson(it)) }
            meldsArr.put(JSONObject().apply { put("id", m.id); put("tiles", tArr) })
        }
        sendPacketText(JSONObject().apply {
            put("kind", "stateSync"); put("roomCode", wireRoomCode())
            put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
            put("maxPlayers", _roomPlayerCount.value); put("gameType", "rummikub")
            put("hostPeerName", myPeerName); put("roomPeers", peersArr); put("seats", seatsArr); put("tableMelds", meldsArr)
            put("poolCount", _poolCount.value)
            put("phase", when (_phase.value) { RmkGamePhase.LOBBY -> "lobby"; RmkGamePhase.PLAYING -> "playing"; RmkGamePhase.ROUND_OVER -> "roundOver" })
            put("currentTurnSeat", _currentTurnSeat.value); put("currentRound", _currentRound.value); put("statusBanner", _statusBanner.value)
        }.toString())
    }

    private fun handleIncomingJson(raw: String) {
        try {
            val obj = JSONObject(raw)
            if (obj.optString("roomCode") != wireRoomCode() || wireRoomCode().isEmpty()) return
            val kind = obj.optString("kind")
            val sender = obj.optString("senderPeerName")
            val sChar = obj.optInt("senderCharId", 1)
            when (kind) {
                "leaveRoom" -> {
                    val leftPeer = obj.optString("senderPeerName", "")
                    if (leftPeer.isBlank() || leftPeer == myPeerName) return
                    val cleanLeft = cleanPeer(leftPeer)
                    orderedRoomPeers.removeAll { it.first == leftPeer }
                    _connectedPeerNames.value = orderedRoomPeers.map { it.first }.filter { it != myPeerName }
                    val newAuth = orderedRoomPeers.isEmpty() || orderedRoomPeers.first().first == myPeerName
                    _isRoomAuthority.value = newAuth
                    if (_phase.value == RmkGamePhase.LOBBY) {
                        rebuildLobbySeats()
                        _statusBanner.value = "玩家 [$cleanLeft] 已离开拉密房间"
                    } else {
                        val list = _seats.value.toMutableList()
                        for (i in list.indices) {
                            if (list[i].peerDisplayName == leftPeer) {
                                val orig = cleanPeer(list[i].name)
                                val aiLabel = if (orig.contains("AI接管")) orig else "$orig (AI接管)"
                                list[i] = list[i].copy(isAI = true, name = aiLabel)
                            }
                        }
                        _seats.value = list
                        _statusBanner.value = "🤖 玩家 [$cleanLeft] 已退房，由 AI 自动接管出牌！"
                        if (newAuth) {
                            broadcastFullState()
                            scheduleAiTurnIfNeeded()
                        }
                    }
                }
                "roomRoster" -> {
                    val mp = obj.optInt("maxPlayers", 0)
                    if (mp in 2..4) _roomPlayerCount.value = mp
                    val rpArr = obj.optJSONArray("roomPeers") ?: return
                    val list = mutableListOf<Triple<String, Int, String>>()
                    for (i in 0 until rpArr.length()) {
                        val ro = rpArr.getJSONObject(i)
                        list.add(Triple(ro.getString("name"), ro.optInt("charId", 1), ro.optString("displayName", ro.getString("name"))))
                    }
                    if (list.isNotEmpty()) {
                        orderedRoomPeers = list; _connectedPeerNames.value = list.map { it.first }.filter { it != myPeerName }
                        _isRoomAuthority.value = (list.first().first == myPeerName)
                        if (_phase.value == RmkGamePhase.LOBBY) rebuildLobbySeats()
                    }
                }
                "joinRequest" -> {
                    if (sender == myPeerName) return
                    val cap = _roomPlayerCount.value.coerceIn(2, 4)
                    if (_isRoomAuthority.value && orderedRoomPeers.none { it.first == sender } && orderedRoomPeers.size < cap) {
                        orderedRoomPeers.add(Triple(sender, sChar, cleanPeer(sender)))
                        rebuildLobbySeats()
                        _statusBanner.value = "🎉 跨平台玩家 [${cleanPeer(sender)}] 加入房间 (已自动替换 AI 座位)"
                        broadcastRoster()
                        broadcastFullState()
                    }
                }
                "leaveRoom" -> {
                    orderedRoomPeers.removeAll { it.first == sender }
                    _connectedPeerNames.value = orderedRoomPeers.map { it.first }.filter { it != myPeerName }
                    _isRoomAuthority.value = orderedRoomPeers.isEmpty() || orderedRoomPeers.first().first == myPeerName
                    if (_phase.value == RmkGamePhase.LOBBY) rebuildLobbySeats()
                }
                "stateSync" -> {
                    if (sender == myPeerName) return
                    val mp = obj.optInt("maxPlayers", 0)
                    if (mp in 2..4) _roomPlayerCount.value = mp
                    _isRoomAuthority.value = (obj.optString("hostPeerName") == myPeerName)
                    val sArr = obj.optJSONArray("seats")
                    if (sArr != null) {
                        if (sArr.length() in 2..4) _roomPlayerCount.value = sArr.length()
                        val list = ArrayList<RmkSeat>()
                        for (i in 0 until sArr.length()) {
                            val so = sArr.getJSONObject(i)
                            val hArr = so.optJSONArray("hand")
                            val hand = ArrayList<RmkTile>()
                            if (hArr != null) for (k in 0 until hArr.length()) hand.add(tileFromJson(hArr.getJSONObject(k)))
                            val pd = so.optString("peerDisplayName", "")
                            if (pd == myPeerName) _mySeatIndex.value = i
                            list.add(RmkSeat(so.optInt("id", i), so.optString("name", ""), so.optInt("characterId", 1), so.optBoolean("isAI", false), pd, hand, so.optBoolean("hasBrokenIce", false), so.optInt("score", 1000)))
                        }
                        _seats.value = list
                    }
                    val mArr = obj.optJSONArray("tableMelds")
                    if (mArr != null) {
                        val ms = ArrayList<RmkMeld>()
                        for (i in 0 until mArr.length()) {
                            val mo = mArr.getJSONObject(i)
                            val tArr = mo.optJSONArray("tiles")
                            val ts = ArrayList<RmkTile>()
                            if (tArr != null) for (k in 0 until tArr.length()) ts.add(tileFromJson(tArr.getJSONObject(k)))
                            ms.add(RmkMeld(mo.optString("id"), ts))
                        }
                        _tableMelds.value = ms
                    }
                    _poolCount.value = obj.optInt("poolCount", _poolCount.value)
                    _phase.value = when (obj.optString("phase")) {
                        "playing" -> RmkGamePhase.PLAYING
                        "roundOver" -> RmkGamePhase.ROUND_OVER
                        else -> RmkGamePhase.LOBBY
                    }
                    val ct = obj.optInt("currentTurnSeat", _currentTurnSeat.value)
                    if (ct != _currentTurnSeat.value) resetWorkspaceForNewTurn()
                    _currentTurnSeat.value = ct
                    _currentRound.value = obj.optInt("currentRound", _currentRound.value)
                    obj.optString("statusBanner", "").takeIf { it.isNotEmpty() }?.let { _statusBanner.value = it }
                    if (_phase.value == RmkGamePhase.PLAYING) startTurnTimer()
                }
                "drawTileAction" -> {
                    if (_isRoomAuthority.value) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == sender }
                        if (idx == _currentTurnSeat.value) executeDrawAndAdvance(idx, "摸牌过")
                    }
                }
                "commitTurnAction" -> {
                    if (_isRoomAuthority.value) {
                        val idx = _seats.value.indexOfFirst { it.peerDisplayName == sender }
                        if (idx == _currentTurnSeat.value) {
                            val mArr = obj.optJSONArray("tableMelds") ?: return
                            val ms = ArrayList<RmkMeld>()
                            for (i in 0 until mArr.length()) {
                                val mo = mArr.getJSONObject(i)
                                val tArr = mo.optJSONArray("tiles")
                                val ts = ArrayList<RmkTile>()
                                if (tArr != null) for (k in 0 until tArr.length()) ts.add(tileFromJson(tArr.getJSONObject(k)))
                                ms.add(RmkMeld(mo.optString("id"), ts))
                            }
                            val pArr = obj.optJSONArray("committedHandIds") ?: return
                            val pids = HashSet<String>()
                            for (i in 0 until pArr.length()) pids.add(pArr.getString(i))
                            executeCommitTurn(idx, ms, pids)
                        }
                    }
                }
            }
        } catch (_: Exception) {}
    }

    fun startNewRound() {
        if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) return
        rebuildLobbySeats()
        val pCnt = _seats.value.size.coerceIn(2, 4)
        pool.clear()
        consecutiveEmptyPoolPasses = 0
        pool.addAll(build106Deck())
        val list = _seats.value.toMutableList()
        for (i in 0 until pCnt) {
            val dealt = pool.take(14)
            repeat(14) { pool.removeAt(0) }
            list[i] = list[i].copy(hand = dealt, hasBrokenIce = false)
        }
        _seats.value = list
        _poolCount.value = pool.size
        _tableMelds.value = emptyList()
        _lastTurnHighlightedTileIds.value = emptySet()
        _selectedTableTileSource.value = null
        _currentTurnSeat.value = (_currentRound.value - 1) % pCnt
        _phase.value = RmkGamePhase.PLAYING
        resetWorkspaceForNewTurn(preserveRackLayout = false)
        trigger15sDealAnimation()
        _statusBanner.value = "🔢 正在派发 14 张初始手牌 (1.5秒发牌动画)... 轮到 [${list[_currentTurnSeat.value].name}] 出牌 (需≥30分破冰)"
        startTurnTimer()
        broadcastFullState()
        scheduleAiTurnIfNeeded()
    }

    fun nextRound() {
        _currentRound.value += 1
        startNewRound()
    }

    private fun startTurnTimer() {
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        _turnRemainingSeconds.value = 60
        val r = object : Runnable {
            override fun run() {
                if (_phase.value != RmkGamePhase.PLAYING) return
                if (_turnRemainingSeconds.value > 0) {
                    _turnRemainingSeconds.value -= 1
                    mainHandler.postDelayed(this, 1000L)
                } else if (!_isServerConnected.value || _isRoomAuthority.value) {
                    restoreWorkspaceSnapshot()
                    executeDrawAndAdvance(_currentTurnSeat.value, "⏰ 60秒超时复原桌面并罚抽1张")
                }
            }
        }
        timerRunnable = r
        mainHandler.postDelayed(r, 1000L)
    }

    fun trigger15sDealAnimation() {
        _isDealingAnimation.value = true
        _dealingVisibleCount.value = 0
        val myDealt = _rackSlots.value.filterNotNull()
        for (step in 1..14) {
            mainHandler.postDelayed({
                _dealingVisibleCount.value = step
                val t = myDealt.getOrNull(step - 1)
                if (t?.isJoker == true) {
                    RmkSoundFX.playJokerAcquired()
                    _statusBanner.value = "🌟 恭喜拿到梓喵【百搭牌 (JOKER)】！百搭牌可替代任意颜色与数字"
                } else if (step % 2 == 1) {
                    RmkSoundFX.playTileClick()
                }
                if (step == 14) {
                    _dealingVisibleCount.value = 99
                    _isDealingAnimation.value = false
                }
            }, (step * 105).toLong())
        }
    }

    fun resetWorkspaceForNewTurn(preserveRackLayout: Boolean = true) {
        _selectedTileIds.value = emptySet()
        _selectedTableTileSource.value = null
        _liftedSlotIndex.value = null
        _isEditingTable.value = false
        val myHand = _seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList()
        snapshotHand = myHand
        _workingHand.value = myHand
        syncRackFromHand(myHand, preserveExistingPositions = preserveRackLayout)
        snapshotRackSlots = _rackSlots.value
        snapshotMelds = _tableMelds.value
        _workingMelds.value = _tableMelds.value
    }

    private fun ensureWorkspace() {
        if (!_isEditingTable.value) {
            val myHand = _seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList()
            snapshotHand = myHand
            _workingHand.value = myHand
            snapshotMelds = _tableMelds.value
            _workingMelds.value = _tableMelds.value
            snapshotRackSlots = _rackSlots.value
            _isEditingTable.value = true
        }
    }

    fun restoreWorkspaceSnapshot() {
        if (_isEditingTable.value) {
            _workingHand.value = snapshotHand
            _workingMelds.value = snapshotMelds
            _rackSlots.value = snapshotRackSlots
            _selectedTileIds.value = emptySet()
            _liftedSlotIndex.value = null
            _isEditingTable.value = false
            _statusBanner.value = "↩️ 已复原到本回合初始牌面与牌架位置"
        }
    }

    fun toggleSelectTile(id: String) {
        val cur = _selectedTileIds.value.toMutableSet()
        if (!cur.add(id)) cur.remove(id)
        _selectedTileIds.value = cur
    }

    fun placeSelectedAsNewMeld() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val sel = _selectedTileIds.value
        if (sel.isEmpty()) return
        ensureWorkspace()
        val picked = _workingHand.value.filter { sel.contains(it.id) }
        val pts = RmkEvaluator.evaluateMeld(picked)
        if (pts == null) {
            _statusBanner.value = "⚠️ 所选牌未能组成有效顺组或群组 (需≥3张)"
            return
        }
        val ordered = RmkEvaluator.sortMeldForDisplay(picked)
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        _rackSlots.value = _rackSlots.value.map { if (it != null && sel.contains(it.id)) null else it }
        _workingMelds.value = _workingMelds.value + RmkMeld(UUID.randomUUID().toString(), ordered)
        _selectedTileIds.value = emptySet()
        _selectedTableTileSource.value = null
        _liftedSlotIndex.value = null
        if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true) {
            var icePts = 0
            for (i in snapshotMelds.size until _workingMelds.value.size) {
                icePts += RmkEvaluator.evaluateMeld(_workingMelds.value[i].tiles) ?: 0
            }
            _statusBanner.value = if (icePts >= 30) {
                "✅ 已暂放牌组 (${pts}分，累计 ${icePts}分 ≥30分)，点【确认出牌】完成破冰！"
            } else {
                "ℹ️ 已暂放 ${pts} 分牌组（本回合累计 ${icePts}/30 分，点击该牌组可撤回牌架）"
            }
        } else {
            _statusBanner.value = "✅ 已暂放牌组到桌面（点击【确认出牌】完成回合，点击该牌组可撤回）"
        }
    }

    fun addSelectedToTableMeld(meldId: String, allowInvalidSplit: Boolean = false) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val sel = _selectedTileIds.value
        if (sel.isEmpty()) return
        ensureWorkspace()
        val idx = _workingMelds.value.indexOfFirst { it.id == meldId }
        if (idx < 0) return
        val brokenIce = _seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce == true
        if (!brokenIce && idx < snapshotMelds.size) {
            _statusBanner.value = "⚠️ 尚未破冰！首次出牌只能操作自己牌架摆出的牌组且总和 ≥30 分"
            return
        }
        val picked = _workingHand.value.filter { sel.contains(it.id) }
        val comb = _workingMelds.value[idx].tiles + picked
        val valid = (RmkEvaluator.evaluateMeld(comb) != null)
        if (!valid && !(allowInvalidSplit && brokenIce)) {
            _statusBanner.value = "⚠️ 添牌后该牌组不符合群组或顺组规则"
            return
        }
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        _rackSlots.value = _rackSlots.value.map { if (it != null && sel.contains(it.id)) null else it }
        val ms = _workingMelds.value.toMutableList()
        ms[idx] = ms[idx].copy(tiles = if (valid) RmkEvaluator.sortMeldForDisplay(comb) else comb)
        _workingMelds.value = ms
        _lastTurnHighlightedTileIds.value = _lastTurnHighlightedTileIds.value + picked.map { it.id }
        _selectedTileIds.value = emptySet()
        _liftedSlotIndex.value = null
        _statusBanner.value = if (valid) "✅ 已将选牌并入桌面牌组（点右侧绿色 ✓ 确认出牌）" else "🧩 已填入桌面牌组（红框表示待拆解，可拖动多余的牌到桌面其他位置重组！）"
    }

    fun splitMeldToWorkspace(meldId: String, tileId: String? = null) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        ensureWorkspace()
        val idx = _workingMelds.value.indexOfFirst { it.id == meldId }
        if (idx < 0) return
        if (idx >= snapshotMelds.size && tileId == null) {
            val ms = _workingMelds.value.toMutableList()
            val returned = ms.removeAt(idx).tiles
            _workingMelds.value = ms
            _workingHand.value = _workingHand.value + returned
            syncRackFromHand(_workingHand.value, preserveExistingPositions = true)
            _selectedTileIds.value = emptySet()
            _statusBanner.value = "↩️ 已将该组牌撤回牌架"
            return
        }
        if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true && idx < snapshotMelds.size) {
            _statusBanner.value = "⚠️ 尚未破冰，不能拆解其他玩家的桌面牌组！"
            return
        }
        val ms = _workingMelds.value.toMutableList()
        val tList = ms[idx].tiles.toMutableList()
        if (tList.isEmpty()) return
        val tPos = if (tileId != null) tList.indexOfFirst { it.id == tileId } else tList.lastIndex
        val popped = tList.removeAt(if (tPos >= 0) tPos else tList.lastIndex)
        if (tList.isEmpty()) ms.removeAt(idx) else ms[idx] = ms[idx].copy(tiles = tList)
        _workingMelds.value = ms
        _workingHand.value = _workingHand.value + popped
        syncRackFromHand(_workingHand.value, preserveExistingPositions = true)
        _selectedTileIds.value = _selectedTileIds.value + popped.id
        _statusBanner.value = "🔄 已从桌面取回 [${if (popped.isJoker) "百搭" else "${popped.color.labelZh}${popped.number}"}] 到牌架重组！"
    }

    fun handleTableTileTapOrMove(meldId: String, tileId: String) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val brokenIce = _seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce == true
        val isFromSnapshot = snapshotMelds.any { it.id == meldId }

        if (_selectedTileIds.value.isNotEmpty()) {
            if (!brokenIce && isFromSnapshot) {
                _statusBanner.value = "⚠️ 尚未破冰！首次出牌请先将牌拖到桌面空白处或自己本回合牌组上"
                return
            }
            addSelectedToTableMeld(meldId, allowInvalidSplit = true)
            return
        }

        val baseMelds = if (_isEditingTable.value) _workingMelds.value else _tableMelds.value
        val mIdx = baseMelds.indexOfFirst { it.id == meldId }
        if (mIdx < 0) return
        val tIdx = baseMelds[mIdx].tiles.indexOfFirst { it.id == tileId }
        if (tIdx < 0) return

        if (!brokenIce && isFromSnapshot) {
            _statusBanner.value = "⚠️ 尚未破冰！首次出牌需使用自己牌架摆出 ≥30 分牌组"
            return
        }

        val src = _selectedTableTileSource.value
        if (src != null) {
            if (src.first == meldId && src.second == tileId) {
                _selectedTableTileSource.value = null
                if (snapshotHand.any { it.id == tileId }) {
                    returnTableTileToRackIfFromThisTurn(meldId, tileId)
                } else {
                    moveTableTile(meldId, tileId, null)
                }
                return
            } else if (src.first != meldId) {
                moveTableTile(src.first, src.second, meldId)
                _selectedTableTileSource.value = null
                return
            }
        }

        _selectedTableTileSource.value = null
    }

    fun moveTableTile(
        fromMeldId: String,
        tileId: String,
        toMeldId: String?,
        preferLeading: Boolean = false,
        insertAtMeldIndex: Int? = null
    ) {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val brokenIce = _seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce == true
        val isFromSnapshot = snapshotMelds.any { it.id == fromMeldId }
        if (!brokenIce && isFromSnapshot) {
            _statusBanner.value = "⚠️ 尚未破冰！不能拆解其他玩家的桌面牌组"
            return
        }

        ensureWorkspace()
        if (toMeldId == fromMeldId) {
            val ms = _workingMelds.value.toMutableList()
            val idx = ms.indexOfFirst { it.id == fromMeldId }
            if (idx >= 0) {
                ms[idx] = ms[idx].copy(tiles = RmkEvaluator.sortMeldForDisplay(ms[idx].tiles, preferLeadingJoker = preferLeading))
                _workingMelds.value = ms
                syncEditingStateWithSnapshot()
            }
            return
        }
        val ms = _workingMelds.value.toMutableList()
        val srcMIdx = ms.indexOfFirst { it.id == fromMeldId }
        if (srcMIdx < 0) {
            syncEditingStateWithSnapshot()
            return
        }
        val origTiles = ms[srcMIdx].tiles
        val srcTIdx = origTiles.indexOfFirst { it.id == tileId }
        if (srcTIdx < 0) {
            syncEditingStateWithSnapshot()
            return
        }

        _selectedTableTileSource.value = null
        if (toMeldId == null && origTiles.size == 1) {
            val movingTile = origTiles[0]
            ms.removeAt(srcMIdx)
            val newMeld = RmkMeld(UUID.randomUUID().toString(), listOf(movingTile))
            if (insertAtMeldIndex != null) {
                val adj = if (srcMIdx < insertAtMeldIndex) insertAtMeldIndex - 1 else insertAtMeldIndex
                ms.add(adj.coerceIn(0, ms.size), newMeld)
            } else {
                ms.add(newMeld)
            }
            _workingMelds.value = ms
            RmkSoundFX.playTileClick()
            _statusBanner.value = "🧩 已将该牌移至桌面指定位置（本回合出的牌直接向下拉回牌架即可取消）"
            syncEditingStateWithSnapshot()
            return
        }

        val movingTile = origTiles[srcTIdx]
        val remList = origTiles.toMutableList().apply { removeAt(srcTIdx) }
        if (remList.isEmpty()) {
            ms.removeAt(srcMIdx)
        } else {
            val splitRem = RmkEvaluator.autoSplitMeldTiles(remList)
            ms[srcMIdx] = ms[srcMIdx].copy(tiles = splitRem[0])
            if (splitRem.size > 1) {
                for (k in 1 until splitRem.size) {
                    ms.add(srcMIdx + k, RmkMeld(UUID.randomUUID().toString(), splitRem[k]))
                }
            }
        }
        _lastTurnHighlightedTileIds.value = _lastTurnHighlightedTileIds.value + movingTile.id

        val dstIdx = if (toMeldId != null) ms.indexOfFirst { it.id == toMeldId } else -1
        if (dstIdx >= 0) {
            val rawComb = if (preferLeading) listOf(movingTile) + ms[dstIdx].tiles else ms[dstIdx].tiles + movingTile
            val splitGroups = RmkEvaluator.autoSplitMeldTiles(rawComb, preferLeadingJoker = preferLeading)
            ms[dstIdx] = ms[dstIdx].copy(tiles = splitGroups[0])
            if (splitGroups.size > 1) {
                for (k in 1 until splitGroups.size) {
                    ms.add(dstIdx + k, RmkMeld(UUID.randomUUID().toString(), splitGroups[k]))
                }
                RmkSoundFX.playMeldSplit()
                _statusBanner.value = "✨ 已插入牌并自动分裂为 ${splitGroups.size} 组牌！"
            } else {
                RmkSoundFX.playTileSnap()
                val pts = RmkEvaluator.evaluateMeld(splitGroups[0])
                _statusBanner.value = if (pts != null) "✅ 已将桌面牌并入目标牌组 (${pts}分)！" else "🧩 已将牌放入目标牌组（当前 ${splitGroups[0].size} 张，继续调整使其合法）"
            }
        } else {
            val newMeld = RmkMeld(UUID.randomUUID().toString(), listOf(movingTile))
            if (insertAtMeldIndex != null) {
                ms.add(insertAtMeldIndex.coerceIn(0, ms.size), newMeld)
            } else {
                ms.add(newMeld)
            }
            RmkSoundFX.playTileClick()
            _statusBanner.value = "🧩 已从牌组拆出单牌到指定位置（继续拖其他桌面牌或手牌至该牌处即可合并）"
        }
        _workingMelds.value = ms
        syncEditingStateWithSnapshot()
    }

    fun returnTableTileToRackIfFromThisTurn(meldId: String, tileId: String, preferredRackSlot: Int? = null): Boolean {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return false
        if (snapshotHand.none { it.id == tileId }) {
            RmkSoundFX.playUndo()
            _statusBanner.value = "⚠️ 桌面原有的牌不能放回牌架，请在桌面上拖动拆组！"
            return false
        }
        ensureWorkspace()
        val ms = _workingMelds.value.toMutableList()
        val mIdx = ms.indexOfFirst { it.id == meldId }
        if (mIdx < 0) {
            syncEditingStateWithSnapshot()
            return false
        }
        val tList = ms[mIdx].tiles.toMutableList()
        val tIdx = tList.indexOfFirst { it.id == tileId }
        if (tIdx < 0) {
            syncEditingStateWithSnapshot()
            return false
        }
        val tile = tList.removeAt(tIdx)
        if (tList.isEmpty()) {
            ms.removeAt(mIdx)
        } else {
            val splitRem = RmkEvaluator.autoSplitMeldTiles(tList)
            ms[mIdx] = ms[mIdx].copy(tiles = splitRem[0])
            if (splitRem.size > 1) {
                for (k in 1 until splitRem.size) {
                    ms.add(mIdx + k, RmkMeld(UUID.randomUUID().toString(), splitRem[k]))
                }
            }
        }
        _workingMelds.value = ms
        _workingHand.value = _workingHand.value + tile
        if (preferredRackSlot != null && preferredRackSlot in _rackSlots.value.indices && _rackSlots.value[preferredRackSlot] == null) {
            val nextSlots = _rackSlots.value.toMutableList()
            nextSlots[preferredRackSlot] = tile
            _rackSlots.value = nextSlots
        } else {
            syncRackFromHand(_workingHand.value, preserveExistingPositions = true)
        }
        _selectedTableTileSource.value = null
        _selectedTileIds.value = emptySet()
        _liftedSlotIndex.value = null
        RmkSoundFX.playUndo()
        syncEditingStateWithSnapshot()
        _statusBanner.value = "↩️ 已将本回合打出的牌拉回牌架"
        return true
    }

    fun combineSelectedRackTilesWithTableTile(): Boolean {
        val src = _selectedTableTileSource.value ?: return false
        val sel = _selectedTileIds.value
        if (sel.isEmpty()) return false
        val brokenIce = _seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce == true
        if (!brokenIce && snapshotMelds.any { it.id == src.first }) return false

        ensureWorkspace()
        val ms = _workingMelds.value.toMutableList()
        val srcMIdx = ms.indexOfFirst { it.id == src.first }
        if (srcMIdx < 0) {
            syncEditingStateWithSnapshot()
            return false
        }
        val srcTiles = ms[srcMIdx].tiles.toMutableList()
        val srcTIdx = srcTiles.indexOfFirst { it.id == src.second }
        if (srcTIdx < 0) {
            syncEditingStateWithSnapshot()
            return false
        }
        val tableTile = srcTiles.removeAt(srcTIdx)
        if (srcTiles.isEmpty()) ms.removeAt(srcMIdx) else ms[srcMIdx] = ms[srcMIdx].copy(tiles = srcTiles)

        val rackPicked = _workingHand.value.filter { sel.contains(it.id) }
        val newGroup = RmkEvaluator.sortMeldForDisplay(listOf(tableTile) + rackPicked)
        _workingHand.value = _workingHand.value.filterNot { sel.contains(it.id) }
        _rackSlots.value = _rackSlots.value.map { if (it != null && sel.contains(it.id)) null else it }
        ms.add(RmkMeld(UUID.randomUUID().toString(), newGroup))
        _workingMelds.value = ms
        _lastTurnHighlightedTileIds.value = _lastTurnHighlightedTileIds.value + newGroup.map { it.id }
        _selectedTileIds.value = emptySet()
        _selectedTableTileSource.value = null
        _liftedSlotIndex.value = null
        syncEditingStateWithSnapshot()
        _statusBanner.value = "✅ 已将牌架选牌与桌面拆出的牌组合成新牌组！"
        return true
    }

    fun dropRackTilesToTable(
        primaryTileId: String,
        targetMeldId: String? = null,
        preferLeading: Boolean = false,
        insertAtMeldIndex: Int? = null
    ) {
        val myIdx = _mySeatIndex.value
        if (_currentTurnSeat.value != myIdx || _phase.value != RmkGamePhase.PLAYING) {
            _statusBanner.value = "⏳ 当前不是您的回合，无法拖上桌面出牌"
            return
        }
        val activeHand = if (_isEditingTable.value) _workingHand.value else (_seats.value.getOrNull(myIdx)?.hand ?: emptyList())
        val targetIds = if (_selectedTileIds.value.contains(primaryTileId)) _selectedTileIds.value else (_selectedTileIds.value + primaryTileId)
        val picked = activeHand.filter { targetIds.contains(it.id) }
        if (picked.isEmpty()) {
            syncEditingStateWithSnapshot()
            return
        }

        ensureWorkspace()
        _selectedTileIds.value = targetIds
        _lastTurnHighlightedTileIds.value = _lastTurnHighlightedTileIds.value + picked.map { it.id }
        val brokenIce = _seats.value.getOrNull(myIdx)?.hasBrokenIce == true

        _selectedTableTileSource.value = null
        if (targetMeldId != null) {
            val ms = _workingMelds.value.toMutableList()
            val mIdx = ms.indexOfFirst { it.id == targetMeldId }
            val isFromSnapshot = snapshotMelds.any { it.id == targetMeldId }
            if (mIdx >= 0 && (brokenIce || !isFromSnapshot)) {
                _workingHand.value = _workingHand.value.filterNot { targetIds.contains(it.id) }
                _rackSlots.value = _rackSlots.value.map { if (it != null && targetIds.contains(it.id)) null else it }
                val rawComb = if (preferLeading) picked + ms[mIdx].tiles else ms[mIdx].tiles + picked
                val splitGroups = RmkEvaluator.autoSplitMeldTiles(rawComb, preferLeadingJoker = preferLeading)
                ms[mIdx] = ms[mIdx].copy(tiles = splitGroups[0])
                if (splitGroups.size > 1) {
                    for (k in 1 until splitGroups.size) {
                        ms.add(mIdx + k, RmkMeld(UUID.randomUUID().toString(), splitGroups[k]))
                    }
                    RmkSoundFX.playMeldSplit()
                    _statusBanner.value = "✨ 已插入牌组并自动分裂为 ${splitGroups.size} 组牌！"
                } else {
                    RmkSoundFX.playTileSnap()
                    _statusBanner.value = if (RmkEvaluator.evaluateMeld(splitGroups[0]) != null) "✅ 已并入桌面牌组（点击右侧绿色 ✓ 确认出牌，或向下拉回牌架取消）" else "🧩 已放入桌面牌组（满3张同色顺子或同数不同色群组后即可点 ✓ 确认）"
                }
                _workingMelds.value = ms
                _selectedTileIds.value = emptySet()
                _liftedSlotIndex.value = null
                syncEditingStateWithSnapshot()
                return
            }
        }

        val ms = _workingMelds.value.toMutableList()
        _workingHand.value = _workingHand.value.filterNot { targetIds.contains(it.id) }
        _rackSlots.value = _rackSlots.value.map { if (it != null && targetIds.contains(it.id)) null else it }
        val splitPicked = RmkEvaluator.autoSplitMeldTiles(picked, preferLeadingJoker = preferLeading)
        var insPos = (insertAtMeldIndex ?: ms.size).coerceIn(0, ms.size)
        for (grp in splitPicked) {
            ms.add(insPos, RmkMeld(UUID.randomUUID().toString(), grp))
            insPos += 1
        }
        _workingMelds.value = ms
        _selectedTileIds.value = emptySet()
        _liftedSlotIndex.value = null
        RmkSoundFX.playTileClick()
        val pts = RmkEvaluator.evaluateMeld(splitPicked[0])
        _statusBanner.value = if (pts != null) "✅ 已放置有效牌组 (${pts}分)！点击右侧绿色 ✓ 确认出牌，或向下拉回牌架取消" else "🧩 已放置在桌面指定位置（继续拖牌与它组合成 ≥3 张牌组，向下拉回牌架可取消）"
        syncEditingStateWithSnapshot()
    }

    fun startLongPressCascadeSelect(slotIdx: Int) {
        val anchor = _rackSlots.value.getOrNull(slotIdx) ?: return
        // 1. First check contiguous tiles placed side-by-side on the same rack row around slotIdx
        val cols = maxOf(10, _rackCols.value)
        val rowStart = (slotIdx / cols) * cols
        val rowEnd = minOf(_rackSlots.value.size - 1, rowStart + cols - 1)
        var leftIdx = slotIdx
        while (leftIdx > rowStart && _rackSlots.value[leftIdx - 1] != null) {
            leftIdx -= 1
        }
        var rightIdx = slotIdx
        while (rightIdx < rowEnd && _rackSlots.value[rightIdx + 1] != null) {
            rightIdx += 1
        }
        val contiguousBlock = (leftIdx..rightIdx).mapNotNull { _rackSlots.value[it] }
        if (contiguousBlock.size >= 3 && RmkEvaluator.evaluateMeld(contiguousBlock) != null) {
            _selectedTileIds.value = contiguousBlock.map { it.id }.toSet()
            _liftedSlotIndex.value = slotIdx
            val pts = RmkEvaluator.evaluateMeld(contiguousBlock) ?: 0
            _statusBanner.value = "✨ 已整组连选 ${contiguousBlock.size} 张牌 ($pts 分)，直接向上拖到桌面即可整组出牌！"
            return
        }
        val active = currentCanonicalHand()
        val jokers = active.filter { it.isJoker && it.id != anchor.id }
        var seq: List<RmkTile> = listOf(anchor)
        if (!anchor.isJoker) {
            val runTiles = mutableListOf(anchor)
            var nextN = anchor.number + 1
            while (nextN <= 13) {
                val nxt = active.firstOrNull { !it.isJoker && it.color == anchor.color && it.number == nextN }
                if (nxt != null) { runTiles.add(nxt); nextN++ } else break
            }
            var prevN = anchor.number - 1
            while (prevN >= 1) {
                val prv = active.firstOrNull { !it.isJoker && it.color == anchor.color && it.number == prevN }
                if (prv != null) { runTiles.add(0, prv); prevN-- } else break
            }
            val grp = mutableListOf(anchor)
            val seen = hashSetOf(anchor.color)
            for (t in active) {
                if (!t.isJoker && t.number == anchor.number && seen.add(t.color)) grp.add(t)
            }
            if (runTiles.size >= 3 || (runTiles.size == 2 && jokers.isNotEmpty()) || (runTiles.size >= 2 && runTiles.size >= grp.size)) {
                val base = runTiles.sortedBy { it.number }.toMutableList()
                if (base.size == 2 && jokers.isNotEmpty()) base.add(jokers.first())
                seq = base
            } else if (grp.size >= 2) {
                if (grp.size == 2 && jokers.isNotEmpty()) grp.add(jokers.first())
                seq = grp
            }
        } else {
            val best = RmkEvaluator.findBestMeld(active)
            if (best != null && best.any { it.id == anchor.id }) {
                seq = best
            } else {
                val nearby = active.filter { !it.isJoker && it.id != anchor.id }.take(2)
                if (nearby.size == 2) seq = nearby + anchor
            }
        }
        _selectedTileIds.value = seq.map { it.id }.toSet()
        _liftedSlotIndex.value = slotIdx
        _statusBanner.value = "✨ 已长按连选 ${seq.size} 张牌（含百搭），向上拖入桌面或点【出到桌面】即可出牌！"
    }

    fun smartHint() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        val activeHand = if (_isEditingTable.value) _workingHand.value else (_seats.value.getOrNull(_mySeatIndex.value)?.hand ?: emptyList())
        val (allMelds, _) = RmkEvaluator.organizeHandIntoGroups(activeHand, _sortByColor.value)
        val best = allMelds.maxByOrNull { RmkEvaluator.evaluateMeld(it) ?: 0 } ?: RmkEvaluator.findBestMeld(activeHand)
        if (best != null) {
            val bestPts = RmkEvaluator.evaluateMeld(best) ?: 0
            val totalPts = allMelds.sumOf { RmkEvaluator.evaluateMeld(it) ?: 0 }
            _selectedTileIds.value = best.map { it.id }.toSet()
            if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true && totalPts < 30 && bestPts < 30) {
                _statusBanner.value = "💡 当前牌架可出牌组最高 ${maxOf(bestPts, totalPts)} 分（首次破冰需满30分），建议点右侧【+】摸牌"
            } else {
                _statusBanner.value = "💡 已为您选中推荐牌组 (${bestPts}分，向上拖到桌面或点【出到桌面】即可出牌)"
            }
        } else {
            _statusBanner.value = "💡 暂无可直出牌组，建议点击右侧【+】摸牌"
        }
    }

    fun commitMyTurn() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING) return
        if (!hasUncommittedTableChanges()) {
            _statusBanner.value = "⚠️ 本回合尚未移动任何牌到桌面（若不出请点右侧【+】摸牌）"
            _isEditingTable.value = false
            return
        }
        val remIds = _workingHand.value.map { it.id }.toSet()
        val playedIds = snapshotHand.map { it.id }.filterNot { remIds.contains(it) }.toSet()
        if (playedIds.isEmpty()) {
            _statusBanner.value = "⚠️ 本回合尚未从牌架打出任何牌（若不出请点【复原】后点【+】摸牌）"
            return
        }
        val normalized = ArrayList<RmkMeld>()
        for (m in _workingMelds.value) {
            val sp = RmkEvaluator.autoSplitMeldTiles(m.tiles)
            if (sp.size == 1) normalized.add(m.copy(tiles = sp[0]))
            else sp.forEachIndexed { idx, g -> normalized.add(RmkMeld(if (idx == 0) m.id else UUID.randomUUID().toString(), g)) }
        }
        _workingMelds.value = normalized
        for (m in _workingMelds.value) {
            if (RmkEvaluator.evaluateMeld(m.tiles) == null) {
                _statusBanner.value = "⚠️ 桌面存在无效牌组，请继续补齐、向下拉回牌架或点【复原】"
                return
            }
        }
        RmkSoundFX.playTurnCommit()
        if (_seats.value.getOrNull(_mySeatIndex.value)?.hasBrokenIce != true) {
            if (_workingMelds.value.size <= snapshotMelds.size) {
                _statusBanner.value = "⚠️ 首次破冰只能出自己牌架的牌组！"
                return
            }
            var pts = 0
            for (i in snapshotMelds.size until _workingMelds.value.size) {
                pts += RmkEvaluator.evaluateMeld(_workingMelds.value[i].tiles) ?: 0
            }
            if (pts < 30) {
                _statusBanner.value = "⚠️ 破冰总分仅 $pts 分，必须 ≥30 分才能首次出牌！"
                return
            }
        }

        if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) {
            val mArr = JSONArray()
            _workingMelds.value.forEach { m ->
                val tArr = JSONArray()
                m.tiles.forEach { tArr.put(tileToJson(it)) }
                mArr.put(JSONObject().apply { put("id", m.id); put("tiles", tArr) })
            }
            val pArr = JSONArray()
            playedIds.forEach { pArr.put(it) }
            sendPacketText(JSONObject().apply {
                put("kind", "commitTurnAction"); put("roomCode", wireRoomCode())
                put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                put("tableMelds", mArr); put("committedHandIds", pArr)
            }.toString())
            _isEditingTable.value = false
            return
        }
        executeCommitTurn(_mySeatIndex.value, _workingMelds.value, playedIds)
    }

    fun drawTilePassTapped() {
        if (_currentTurnSeat.value != _mySeatIndex.value || _phase.value != RmkGamePhase.PLAYING || _isDrawingAnimation.value) return
        restoreWorkspaceSnapshot()
        val emptyIdx = _rackSlots.value.indexOfFirst { it == null }
        _drawnTargetSlotIndex.value = if (emptyIdx >= 0) emptyIdx else (_rackSlots.value.size - 1).coerceAtLeast(0)
        _isDrawingAnimation.value = true
        _drawingAnimatedTile.value = pool.firstOrNull() ?: RmkTile("anim_draw", RmkColor.RED, 7)
        _statusBanner.value = "🃏 正在从摸牌区抽取 1 张新牌飞入牌架空位..."
        mainHandler.postDelayed({
            _isDrawingAnimation.value = false
            _drawingAnimatedTile.value = null
            if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) {
                sendPacketText(JSONObject().apply {
                    put("kind", "drawTileAction"); put("roomCode", wireRoomCode())
                    put("senderPeerName", myPeerName); put("senderCharId", _myCharacter.value.charId)
                }.toString())
            } else {
                executeDrawAndAdvance(_mySeatIndex.value, "摸牌结束回合")
            }
        }, 460L)
    }

    private fun executeCommitTurn(seatIdx: Int, newMelds: List<RmkMeld>, playedIds: Set<String>) {
        consecutiveEmptyPoolPasses = 0
        val pCnt = _seats.value.size.coerceAtLeast(2)
        _tableMelds.value = newMelds
        if (seatIdx == _mySeatIndex.value || _lastTurnHighlightedTileIds.value.isEmpty()) {
            _lastTurnHighlightedTileIds.value = playedIds
        }
        val list = _seats.value.toMutableList()
        val remHand = list[seatIdx].hand.filterNot { playedIds.contains(it.id) }
        list[seatIdx] = list[seatIdx].copy(hand = remHand, hasBrokenIce = true)
        _seats.value = list
        _isEditingTable.value = false

        if (remHand.isEmpty()) {
            finishRound(seatIdx)
            return
        }
        _currentTurnSeat.value = (seatIdx + 1) % pCnt
        resetWorkspaceForNewTurn()
        _turnRemainingSeconds.value = 60
        _statusBanner.value = "✅ [${list[seatIdx].name}] 出牌 ${playedIds.size} 张！轮到 [${list[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAiTurnIfNeeded()
    }

    private fun executeDrawAndAdvance(seatIdx: Int, reason: String) {
        _isDealingAnimation.value = false
        _dealingVisibleCount.value = 999
        if (seatIdx != _mySeatIndex.value && pool.isNotEmpty()) {
            _opponentDrawingSeatIndex.value = seatIdx
            mainHandler.postDelayed({
                if (_opponentDrawingSeatIndex.value == seatIdx) {
                    _opponentDrawingSeatIndex.value = null
                }
            }, 460L)
        }
        val pCnt = _seats.value.size.coerceAtLeast(2)
        val list = _seats.value.toMutableList()
        if (seatIdx !in list.indices) return
        if (pool.isNotEmpty()) {
            val t = pool.removeAt(0)
            list[seatIdx] = list[seatIdx].copy(hand = list[seatIdx].hand + t)
            _seats.value = list
            _poolCount.value = pool.size
            consecutiveEmptyPoolPasses = 0
        } else {
            consecutiveEmptyPoolPasses += 1
            if (consecutiveEmptyPoolPasses >= pCnt) {
                finishRoundByFewestTiles()
                return
            }
        }
        _isEditingTable.value = false
        _currentTurnSeat.value = (seatIdx + 1) % pCnt
        resetWorkspaceForNewTurn()
        _turnRemainingSeconds.value = 60
        val passText = if (pool.isEmpty()) "牌堆已空跳过 ($consecutiveEmptyPoolPasses/$pCnt)" else reason
        _statusBanner.value = "[${list[seatIdx].name}] $passText · 轮到 [${list[_currentTurnSeat.value].name}]"
        broadcastFullState()
        scheduleAiTurnIfNeeded()
    }

    private fun finishRoundByFewestTiles() {
        val pCnt = _seats.value.size.coerceAtLeast(2)
        var bestIdx = 0
        var bestCount = Int.MAX_VALUE
        var bestPts = Int.MAX_VALUE
        val list = _seats.value.toMutableList()
        for (i in 0 until pCnt) {
            val cnt = list[i].hand.size
            val pts = list[i].hand.sumOf { if (it.isJoker) 30 else it.number }
            if (cnt < bestCount || (cnt == bestCount && pts < bestPts)) {
                bestCount = cnt
                bestPts = pts
                bestIdx = i
            }
        }
        _phase.value = RmkGamePhase.ROUND_OVER
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        var gain = 0
        for (i in 0 until pCnt) {
            if (i == bestIdx) continue
            val pen = list[i].hand.sumOf { if (it.isJoker) 30 else it.number }
            val diff = (pen - bestPts).coerceAtLeast(0)
            list[i] = list[i].copy(score = list[i].score - diff)
            gain += diff
        }
        list[bestIdx] = list[bestIdx].copy(score = list[bestIdx].score + gain)
        _seats.value = list
        RmkSoundFX.playRoundWin()
        _statusBanner.value = "🏆 牌堆已摸空！[${list[bestIdx].name}] 剩余手牌最少 (${bestCount}张) 获胜！(赢得 +$gain 分)"
        broadcastFullState()
    }

    private fun finishRound(winner: Int) {
        val pCnt = _seats.value.size.coerceAtLeast(2)
        _phase.value = RmkGamePhase.ROUND_OVER
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        val list = _seats.value.toMutableList()
        var gain = 0
        for (i in 0 until pCnt) {
            if (i == winner) continue
            val pen = list[i].hand.sumOf { if (it.isJoker) 30 else it.number }
            list[i] = list[i].copy(score = list[i].score - pen)
            gain += pen
        }
        list[winner] = list[winner].copy(score = list[winner].score + gain)
        _seats.value = list
        _statusBanner.value = "🏆 [${list[winner].name}] 清空牌架获胜！(赢得 +$gain 分)"
        broadcastFullState()
    }

    private fun scheduleAiTurnIfNeeded() {
        aiRunnable?.let { mainHandler.removeCallbacks(it) }
        if ((_isServerConnected.value || _connectedPeerNames.value.isNotEmpty() || lanWriters.isNotEmpty()) && !_isRoomAuthority.value) return
        val cur = _currentTurnSeat.value
        if (_phase.value == RmkGamePhase.PLAYING && _seats.value.getOrNull(cur)?.isAI == true) {
            val r = Runnable {
                if (_phase.value == RmkGamePhase.PLAYING && _currentTurnSeat.value == cur) {
                    val s = _seats.value[cur]
                    val aiMove = RmkEvaluator.findAITableCombinationMove(s.hand, _tableMelds.value, s.hasBrokenIce)
                    if (aiMove != null && aiMove.playedIds.isNotEmpty()) {
                        performAIStepByStepPlay(cur, aiMove)
                    } else {
                        executeDrawAndAdvance(cur, "从共用牌堆摸1张牌")
                    }
                }
            }
            aiRunnable = r
            mainHandler.postDelayed(r, 1150L)
        }
    }

    private data class AIStepPlacement(val tile: RmkTile, val targetMeldId: String)

    private fun performAIStepByStepPlay(seatIdx: Int, aiMove: RmkEvaluator.AITableMoveResult) {
        val oldMelds = _tableMelds.value
        val oldTileIdsByMeld = oldMelds.associate { m -> m.id to m.tiles.map { it.id }.toSet() }
        val steps = ArrayList<AIStepPlacement>()
        for (meld in aiMove.newMelds) {
            val prevIds = oldTileIdsByMeld[meld.id] ?: emptySet()
            for (tile in meld.tiles) {
                if (aiMove.playedIds.contains(tile.id) || !prevIds.contains(tile.id)) {
                    steps.add(AIStepPlacement(tile, meld.id))
                }
            }
        }
        if (steps.isEmpty()) {
            _lastTurnHighlightedTileIds.value = aiMove.highlightedIds
            executeCommitTurn(seatIdx, aiMove.newMelds, aiMove.playedIds)
            return
        }

        val initialHand = _seats.value[seatIdx].hand
        val revealedIds = HashSet<String>()
        val stepIntervalMs = 580L

        for ((idx, step) in steps.withIndex()) {
            mainHandler.postDelayed({
                if (_phase.value != RmkGamePhase.PLAYING || _currentTurnSeat.value != seatIdx) return@postDelayed
                _opponentPlayingSeatIndex.value = seatIdx
                _opponentPlayingTile.value = step.tile
                _opponentPlayingTargetMeldId.value = step.targetMeldId
                CharacterFilter.fiveIndividuals.firstOrNull { it.charId == _seats.value[seatIdx].characterId }?.let {
                    audioManager.playMascotVoice(it)
                }

                mainHandler.postDelayed({
                    if (_phase.value != RmkGamePhase.PLAYING || _currentTurnSeat.value != seatIdx) return@postDelayed
                    revealedIds.add(step.tile.id)
                    _opponentPlayingTile.value = null
                    _opponentPlayingSeatIndex.value = null
                    _opponentPlayingTargetMeldId.value = null

                    val partialMelds = ArrayList<RmkMeld>()
                    for (m in aiMove.newMelds) {
                        val visibleTiles = m.tiles.filter { t ->
                            !aiMove.playedIds.contains(t.id) || revealedIds.contains(t.id)
                        }
                        if (visibleTiles.isNotEmpty()) {
                            partialMelds.add(RmkMeld(m.id, visibleTiles))
                        }
                    }
                    _tableMelds.value = partialMelds
                    _lastTurnHighlightedTileIds.value = revealedIds.toSet()
                    val sList = _seats.value.toMutableList()
                    if (seatIdx in sList.indices) sList[seatIdx] = sList[seatIdx].copy(hand = initialHand.filterNot { revealedIds.contains(it.id) })
                    _seats.value = sList
                }, 360L)
            }, idx * stepIntervalMs)
        }

        val totalDelayMs = steps.size * stepIntervalMs + 180L
        mainHandler.postDelayed({
            if (_phase.value != RmkGamePhase.PLAYING || _currentTurnSeat.value != seatIdx) return@postDelayed
            _opponentPlayingTile.value = null
            _opponentPlayingSeatIndex.value = null
            _opponentPlayingTargetMeldId.value = null
            val sList = _seats.value.toMutableList()
            if (seatIdx in sList.indices) sList[seatIdx] = sList[seatIdx].copy(hand = initialHand)
            _seats.value = sList
            _lastTurnHighlightedTileIds.value = aiMove.highlightedIds
            executeCommitTurn(seatIdx, aiMove.newMelds, aiMove.playedIds)
        }, totalDelayMs)
    }
}
