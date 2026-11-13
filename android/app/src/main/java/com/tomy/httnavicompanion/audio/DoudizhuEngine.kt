package com.tomy.httnavicompanion.audio

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class CardSuit(val symbol: String, val isRed: Boolean) {
    SPADE("♠", false),
    HEART("♥", true),
    CLUB("♣", false),
    DIAMOND("♦", true),
    JOKER("★", true)
}

data class DoudizhuCard(
    val id: String,
    val rank: Int, // 3..15 (11=J,12=Q,13=K,14=A,15=2), 16=SmallJoker, 17=BigJoker
    val suit: CardSuit
) {
    val rankLabel: String
        get() = when (rank) {
            11 -> "J"
            12 -> "Q"
            13 -> "K"
            14 -> "A"
            15 -> "2"
            16 -> "小王"
            17 -> "大王"
            else -> rank.toString()
        }
}

enum class DoudizhuHandType(val label: String) {
    INVALID("无效牌型"),
    SINGLE("单张"),
    PAIR("对子"),
    TRIPLE("三张"),
    TRIPLE_ONE("三带一"),
    TRIPLE_PAIR("三带二"),
    STRAIGHT("顺子"),
    DOUBLE_STRAIGHT("连对"),
    AIRPLANE("飞机"),
    BOMB("炸弹"),
    ROCKET("王炸")
}

data class EvaluatedDoudizhuHand(
    val type: DoudizhuHandType,
    val mainRank: Int,
    val length: Int,
    val cards: List<DoudizhuCard>
)

enum class DoudizhuGamePhase {
    LOBBY, BIDDING, PLAYING, FINISHED
}

data class DoudizhuPlayerSeat(
    val seatIndex: Int,
    val character: CharacterFilter,
    val isAI: Boolean,
    val isLandlord: Boolean = false,
    val hand: List<DoudizhuCard> = emptyList(),
    val lastPlayed: List<DoudizhuCard> = emptyList(),
    val passedLast: Boolean = false,
    val score: Int = 1000
)

class DoudizhuEngine(private val audioMgr: AudioPlayerManager) {
    private val _phase = MutableStateFlow(DoudizhuGamePhase.LOBBY)
    val phase: StateFlow<DoudizhuGamePhase> = _phase

    private val _seats = MutableStateFlow<List<DoudizhuPlayerSeat>>(emptyList())
    val seats: StateFlow<List<DoudizhuPlayerSeat>> = _seats

    private val _holeCards = MutableStateFlow<List<DoudizhuCard>>(emptyList())
    val holeCards: StateFlow<List<DoudizhuCard>> = _holeCards

    private val _selectedCardIds = MutableStateFlow<Set<String>>(emptySet())
    val selectedCardIds: StateFlow<Set<String>> = _selectedCardIds

    private val _currentTurnSeat = MutableStateFlow(0)
    val currentTurnSeat: StateFlow<Int> = _currentTurnSeat

    private val _highestBid = MutableStateFlow(0)
    val highestBid: StateFlow<Int> = _highestBid

    private val _highestBidderSeat = MutableStateFlow(-1)
    val highestBidderSeat: StateFlow<Int> = _highestBidderSeat

    private val _bidsCount = MutableStateFlow(0)
    val bidsCount: StateFlow<Int> = _bidsCount

    private val _multiplier = MutableStateFlow(1)
    val multiplier: StateFlow<Int> = _multiplier

    private val _lastValidHand = MutableStateFlow<EvaluatedDoudizhuHand?>(null)
    val lastValidHand: StateFlow<EvaluatedDoudizhuHand?> = _lastValidHand

    private val _lastPlaySeat = MutableStateFlow(-1)
    val lastPlaySeat: StateFlow<Int> = _lastPlaySeat

    private val _winnerSeat = MutableStateFlow<Int?>(null)
    val winnerSeat: StateFlow<Int?> = _winnerSeat

    private val _statusBanner = MutableStateFlow("欢迎来到放课后茶会斗地主！点击开始发牌")
    val statusBanner: StateFlow<String> = _statusBanner

    private val _myChar = MutableStateFlow(CharacterFilter.YUI)
    val myChar: StateFlow<CharacterFilter> = _myChar

    private val _playedCardsHistory = MutableStateFlow<List<DoudizhuCard>>(emptyList())
    val playedCardsHistory: StateFlow<List<DoudizhuCard>> = _playedCardsHistory

    fun setMyCharacter(char: CharacterFilter) {
        _myChar.value = if (char == CharacterFilter.ALL) CharacterFilter.YUI else char
    }

    fun startNewGame() {
        val deck = createShuffledDeck()
        val p0 = deck.subList(0, 17).sortedByDescending { it.rank * 10 + it.suit.ordinal }
        val p1 = deck.subList(17, 34).sortedByDescending { it.rank * 10 + it.suit.ordinal }
        val p2 = deck.subList(34, 51).sortedByDescending { it.rank * 10 + it.suit.ordinal }
        val hole = deck.subList(51, 54)

        val aiChars = CharacterFilter.fiveIndividuals.filter { it != _myChar.value }.shuffled()
        _seats.value = listOf(
            DoudizhuPlayerSeat(0, _myChar.value, isAI = false, hand = p0),
            DoudizhuPlayerSeat(1, aiChars[0], isAI = true, hand = p1),
            DoudizhuPlayerSeat(2, aiChars[1], isAI = true, hand = p2)
        )
        _holeCards.value = hole
        _selectedCardIds.value = emptySet()
        _highestBid.value = 0
        _highestBidderSeat.value = -1
        _bidsCount.value = 0
        _multiplier.value = 1
        _lastValidHand.value = null
        _lastPlaySeat.value = -1
        _winnerSeat.value = null
        _playedCardsHistory.value = emptyList()
        _currentTurnSeat.value = 0
        _phase.value = DoudizhuGamePhase.BIDDING
        _statusBanner.value = "叫地主阶段：请选择叫分 (1/2/3分) 或不叫"
    }

    fun submitBid(bid: Int) {
        if (_phase.value != DoudizhuGamePhase.BIDDING || _currentTurnSeat.value != 0) return
        processBid(0, bid)
    }

    private fun processBid(seatIdx: Int, bid: Int) {
        if (bid > _highestBid.value) {
            _highestBid.value = bid
            _highestBidderSeat.value = seatIdx
        }
        _bidsCount.value += 1

        if (_highestBid.value == 3 || _bidsCount.value >= 3) {
            val landlord = if (_highestBidderSeat.value >= 0) _highestBidderSeat.value else 0
            assignLandlord(landlord)
        } else {
            val next = (seatIdx + 1) % 3
            _currentTurnSeat.value = next
            val nextSeat = _seats.value[next]
            if (nextSeat.isAI) {
                val aiScore = evaluateHandStrength(nextSeat.hand)
                val aiBid = when {
                    aiScore >= 85 && _highestBid.value < 3 -> 3
                    aiScore >= 60 && _highestBid.value < 2 -> 2
                    aiScore >= 40 && _highestBid.value < 1 -> 1
                    else -> 0
                }
                processBid(next, aiBid)
            }
        }
    }

    private fun assignLandlord(landlordIdx: Int) {
        val updated = _seats.value.map { s ->
            if (s.seatIndex == landlordIdx) {
                val combined = (s.hand + _holeCards.value).sortedByDescending { it.rank * 10 + it.suit.ordinal }
                s.copy(isLandlord = true, hand = combined)
            } else {
                s.copy(isLandlord = false)
            }
        }
        _seats.value = updated
        _currentTurnSeat.value = landlordIdx
        _phase.value = DoudizhuGamePhase.PLAYING
        val landlordChar = updated[landlordIdx].character.displayName(audioMgr.language.value)
        _statusBanner.value = "地主产生：$landlordChar！请开始出牌"

        if (updated[landlordIdx].isAI) {
            runAITurnsIfNeeded()
        }
    }

    fun toggleSelectCard(cardId: String) {
        val cur = _selectedCardIds.value.toMutableSet()
        if (cur.contains(cardId)) cur.remove(cardId) else cur.add(cardId)
        _selectedCardIds.value = cur
    }

    fun playSelectedCards() {
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != 0) return
        val mySeat = _seats.value[0]
        val chosen = mySeat.hand.filter { _selectedCardIds.value.contains(it.id) }
        val eval = evaluateHand(chosen)
        if (eval.type == DoudizhuHandType.INVALID) {
            _statusBanner.value = "牌型不合法，请重新选择！"
            return
        }
        val prev = if (_lastPlaySeat.value == 0) null else _lastValidHand.value
        if (prev != null && !canBeat(eval, prev)) {
            _statusBanner.value = "所选牌型打不过上家！"
            return
        }
        executePlay(0, eval)
    }

    fun passTurn() {
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != 0) return
        if (_lastPlaySeat.value == -1 || _lastPlaySeat.value == 0) {
            _statusBanner.value = "当前你是首家出牌，不能不出！"
            return
        }
        executePass(0)
    }

    fun hintCards() {
        if (_phase.value != DoudizhuGamePhase.PLAYING || _currentTurnSeat.value != 0) return
        val myHand = _seats.value[0].hand
        val target = if (_lastPlaySeat.value == 0 || _lastPlaySeat.value == -1) null else _lastValidHand.value
        val candidate = findBestPlayableHand(myHand, target)
        if (candidate != null) {
            _selectedCardIds.value = candidate.cards.map { it.id }.toSet()
        } else {
            _statusBanner.value = "没有能大过上家的牌，建议点击【不出】"
        }
    }

    private fun executePlay(seatIdx: Int, eval: EvaluatedDoudizhuHand) {
        if (eval.type == DoudizhuHandType.BOMB || eval.type == DoudizhuHandType.ROCKET) {
            _multiplier.value *= 2
        }
        _lastValidHand.value = eval
        _lastPlaySeat.value = seatIdx
        _playedCardsHistory.value = _playedCardsHistory.value + eval.cards

        val updated = _seats.value.map { s ->
            if (s.seatIndex == seatIdx) {
                val rem = s.hand.filterNot { c -> eval.cards.any { it.id == c.id } }
                s.copy(hand = rem, lastPlayed = eval.cards, passedLast = false)
            } else {
                s
            }
        }
        _seats.value = updated
        if (seatIdx == 0) _selectedCardIds.value = emptySet()

        val winner = updated[seatIdx]
        if (winner.hand.isEmpty()) {
            _winnerSeat.value = seatIdx
            _phase.value = DoudizhuGamePhase.FINISHED
            val name = winner.character.displayName(audioMgr.language.value)
            _statusBanner.value = "🎉 游戏结束！$name (${if (winner.isLandlord) "地主" else "农民"}) 获胜！"
            audioMgr.triggerBirthdaySpecialVoice()
            return
        }

        val next = (seatIdx + 1) % 3
        _currentTurnSeat.value = next
        runAITurnsIfNeeded()
    }

    private fun executePass(seatIdx: Int) {
        val updated = _seats.value.map { s ->
            if (s.seatIndex == seatIdx) s.copy(lastPlayed = emptyList(), passedLast = true) else s
        }
        _seats.value = updated
        val next = (seatIdx + 1) % 3
        _currentTurnSeat.value = next
        if (_lastPlaySeat.value == next) {
            _lastValidHand.value = null
            _seats.value = _seats.value.map { it.copy(lastPlayed = emptyList(), passedLast = false) }
        }
        runAITurnsIfNeeded()
    }

    private fun runAITurnsIfNeeded() {
        var safety = 0
        while (_phase.value == DoudizhuGamePhase.PLAYING && _currentTurnSeat.value != 0 && safety < 10) {
            safety++
            val cur = _currentTurnSeat.value
            val seat = _seats.value[cur]
            val target = if (_lastPlaySeat.value == cur || _lastPlaySeat.value == -1) null else _lastValidHand.value
            val play = findBestPlayableHand(seat.hand, target)
            if (play != null) {
                executePlay(cur, play)
            } else {
                executePass(cur)
            }
        }
    }

    private fun findBestPlayableHand(hand: List<DoudizhuCard>, target: EvaluatedDoudizhuHand?): EvaluatedDoudizhuHand? {
        val sorted = hand.sortedBy { it.rank }
        if (target == null) {
            // Play smallest single or pair
            val groups = sorted.groupBy { it.rank }
            val pair = groups.values.firstOrNull { it.size == 2 }
            if (pair != null) return evaluateHand(pair)
            return sorted.firstOrNull()?.let { evaluateHand(listOf(it)) }
        }

        val groups = sorted.groupBy { it.rank }
        when (target.type) {
            DoudizhuHandType.SINGLE -> {
                val card = sorted.firstOrNull { it.rank > target.mainRank }
                if (card != null) return evaluateHand(listOf(card))
            }
            DoudizhuHandType.PAIR -> {
                val pair = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 2 }?.value?.take(2)
                if (pair != null) return evaluateHand(pair)
            }
            DoudizhuHandType.TRIPLE -> {
                val tri = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 3 }?.value?.take(3)
                if (tri != null) return evaluateHand(tri)
            }
            DoudizhuHandType.TRIPLE_ONE -> {
                val tri = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 3 }?.value?.take(3)
                val kicker = sorted.firstOrNull { c -> tri != null && c.rank != tri[0].rank }
                if (tri != null && kicker != null) return evaluateHand(tri + kicker)
            }
            DoudizhuHandType.TRIPLE_PAIR -> {
                val tri = groups.entries.firstOrNull { it.key > target.mainRank && it.value.size >= 3 }?.value?.take(3)
                val kickerPair = groups.entries.firstOrNull { it.value.size >= 2 && (tri == null || it.key != tri[0].rank) }?.value?.take(2)
                if (tri != null && kickerPair != null) return evaluateHand(tri + kickerPair)
            }
            else -> {}
        }

        // Check bomb
        if (target.type != DoudizhuHandType.ROCKET) {
            val minBombRank = if (target.type == DoudizhuHandType.BOMB) target.mainRank else 0
            val bomb = groups.entries.firstOrNull { it.key > minBombRank && it.value.size == 4 }?.value
            if (bomb != null) return evaluateHand(bomb)
            // Check rocket
            val sj = sorted.firstOrNull { it.rank == 16 }
            val bj = sorted.firstOrNull { it.rank == 17 }
            if (sj != null && bj != null) return evaluateHand(listOf(sj, bj))
        }
        return null
    }

    private fun evaluateHandStrength(hand: List<DoudizhuCard>): Int {
        var s = 0
        hand.forEach {
            if (it.rank == 17) s += 20
            else if (it.rank == 16) s += 15
            else if (it.rank == 15) s += 10
            else if (it.rank == 14) s += 5
        }
        val bombs = hand.groupBy { it.rank }.count { it.value.size == 4 }
        s += bombs * 25
        return s
    }

    fun evaluateHand(cards: List<DoudizhuCard>): EvaluatedDoudizhuHand {
        if (cards.isEmpty()) return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, 0, cards)
        val sorted = cards.sortedBy { it.rank }
        val n = sorted.size
        val counts = sorted.groupingBy { it.rank }.eachCount()

        if (n == 2 && sorted[0].rank == 16 && sorted[1].rank == 17) {
            return EvaluatedDoudizhuHand(DoudizhuHandType.ROCKET, 17, 2, sorted)
        }
        if (n == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.SINGLE, sorted[0].rank, 1, sorted)
        if (n == 2 && counts.size == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.PAIR, sorted[0].rank, 2, sorted)
        if (n == 3 && counts.size == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE, sorted[0].rank, 3, sorted)
        if (n == 4 && counts.size == 1) return EvaluatedDoudizhuHand(DoudizhuHandType.BOMB, sorted[0].rank, 4, sorted)
        if (n == 4 && counts.containsValue(3)) {
            val main = counts.entries.first { it.value == 3 }.key
            return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE_ONE, main, 4, sorted)
        }
        if (n == 5 && counts.containsValue(3) && counts.containsValue(2)) {
            val main = counts.entries.first { it.value == 3 }.key
            return EvaluatedDoudizhuHand(DoudizhuHandType.TRIPLE_PAIR, main, 5, sorted)
        }
        // Straight >= 5
        if (n >= 5 && counts.size == n && sorted.last().rank <= 14) {
            val isSeq = (0 until n - 1).all { sorted[it + 1].rank == sorted[it].rank + 1 }
            if (isSeq) return EvaluatedDoudizhuHand(DoudizhuHandType.STRAIGHT, sorted.first().rank, n, sorted)
        }
        // Double straight >= 6 (3+ pairs)
        if (n >= 6 && n % 2 == 0 && counts.all { it.value == 2 }) {
            val ranks = counts.keys.sorted()
            if (ranks.last() <= 14 && (0 until ranks.size - 1).all { ranks[it + 1] == ranks[it] + 1 }) {
                return EvaluatedDoudizhuHand(DoudizhuHandType.DOUBLE_STRAIGHT, ranks.first(), n, sorted)
            }
        }
        return EvaluatedDoudizhuHand(DoudizhuHandType.INVALID, 0, n, sorted)
    }

    private fun canBeat(challenger: EvaluatedDoudizhuHand, prev: EvaluatedDoudizhuHand): Boolean {
        if (challenger.type == DoudizhuHandType.ROCKET) return true
        if (prev.type == DoudizhuHandType.ROCKET) return false
        if (challenger.type == DoudizhuHandType.BOMB && prev.type != DoudizhuHandType.BOMB) return true
        if (challenger.type == prev.type && challenger.length == prev.length) {
            return challenger.mainRank > prev.mainRank
        }
        return false
    }

    private fun createShuffledDeck(): List<DoudizhuCard> {
        val list = ArrayList<DoudizhuCard>(54)
        for (r in 3..15) {
            for (s in listOf(CardSuit.SPADE, CardSuit.HEART, CardSuit.CLUB, CardSuit.DIAMOND)) {
                list.add(DoudizhuCard("${s.name}_$r", r, s))
            }
        }
        list.add(DoudizhuCard("JOKER_16", 16, CardSuit.JOKER))
        list.add(DoudizhuCard("JOKER_17", 17, CardSuit.JOKER))
        list.shuffle()
        return list
    }
}
