#pragma once
#include <string>
#include <vector>
#include <algorithm>
#include <random>
#include <sstream>
#include <ctime>
#include <map>
#include <set>

// ============================================================================
// Lightweight JSON Builder & Field Extractor (Compatible with iOS & Android)
// ============================================================================
namespace MiniJson {
    inline std::string esc(const std::string& s) {
        std::string o;
        for (char c : s) {
            if (c == '"') o += "\\\"";
            else if (c == '\\') o += "\\\\";
            else if (c == '\n') o += "\\n";
            else o.push_back(c);
        }
        return o;
    }

    inline size_t findKeyValPos(const std::string& json, const std::string& key) {
        std::string pat = "\"" + key + "\"";
        size_t pos = 0;
        while ((pos = json.find(pat, pos)) != std::string::npos) {
            size_t p = pos + pat.size();
            while (p < json.size() && (json[p] == ' ' || json[p] == '\t' || json[p] == '\r' || json[p] == '\n')) p++;
            if (p < json.size() && json[p] == ':') {
                p++;
                while (p < json.size() && (json[p] == ' ' || json[p] == '\t' || json[p] == '\r' || json[p] == '\n')) p++;
                return p;
            }
            pos += pat.size();
        }
        return std::string::npos;
    }

    inline std::string getStr(const std::string& json, const std::string& key, const std::string& defVal = "") {
        size_t pos = findKeyValPos(json, key);
        if (pos == std::string::npos || pos >= json.size() || json[pos] != '"') return defVal;
        pos++;
        std::string out;
        while (pos < json.size() && json[pos] != '"') {
            if (json[pos] == '\\' && pos + 1 < json.size()) {
                pos++;
            }
            out.push_back(json[pos++]);
        }
        return out;
    }

    inline int getInt(const std::string& json, const std::string& key, int defVal = -1) {
        size_t pos = findKeyValPos(json, key);
        if (pos == std::string::npos) return defVal;
        if (pos < json.size() && json[pos] == '"') pos++;
        if (pos >= json.size() || (!isdigit((unsigned char)json[pos]) && json[pos] != '-')) return defVal;
        return std::atoi(json.c_str() + pos);
    }

    inline bool getBool(const std::string& json, const std::string& key, bool defVal = false) {
        size_t pos = findKeyValPos(json, key);
        if (pos == std::string::npos) return defVal;
        if (json.compare(pos, 4, "true") == 0) return true;
        if (json.compare(pos, 5, "false") == 0) return false;
        return defVal;
    }

    inline std::string extractObject(const std::string& json, const std::string& objKey) {
        size_t pos = findKeyValPos(json, objKey);
        if (pos == std::string::npos || pos >= json.size() || json[pos] != '{') return "";
        int depth = 0;
        bool inStr = false;
        for (size_t i = pos; i < json.size(); ++i) {
            char c = json[i];
            if (c == '"' && (i == 0 || json[i - 1] != '\\')) inStr = !inStr;
            if (inStr) continue;
            if (c == '{') depth++;
            else if (c == '}') {
                depth--;
                if (depth == 0) return json.substr(pos, i - pos + 1);
            }
        }
        return "";
    }

    // Splits a top-level JSON array `[{...},{...}]` into object strings
    inline std::vector<std::string> extractObjectsArray(const std::string& json, const std::string& arrayKey) {
        std::vector<std::string> items;
        size_t pos = findKeyValPos(json, arrayKey);
        if (pos == std::string::npos || pos >= json.size() || json[pos] != '[') return items;
        pos++;
        int depth = 0;
        size_t objStart = 0;
        bool inStr = false;
        for (size_t i = pos; i < json.size(); ++i) {
            char c = json[i];
            if (c == '"' && (i == 0 || json[i - 1] != '\\')) inStr = !inStr;
            if (inStr) continue;
            if (c == '{') {
                if (depth == 0) objStart = i;
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth == 0) {
                    items.push_back(json.substr(objStart, i - objStart + 1));
                }
            } else if (c == ']' && depth == 0) {
                break;
            }
        }
        return items;
    }
}

// ============================================================================
// K-ON! Character Roster
// ============================================================================
struct KOnCharacterInfo {
    int charId;
    const char* nameZh;
};
static const KOnCharacterInfo kCharacters[5] = {
    {1, "平泽唯"},
    {2, "秋山澪"},
    {3, "田井中律"},
    {4, "琴吹紬"},
    {5, "中野梓"}
};
inline std::string getCharacterName(int charId) {
    for (const auto& c : kCharacters) if (c.charId == charId) return c.nameZh;
    return "平泽唯";
}

struct RoomPeer {
    std::string name;
    int charId = 1;
    std::string displayName;
};

// ============================================================================
// 1. 放课后斗地主 (3P Doudizhu Engine & Evaluator)
// ============================================================================
struct DdzCard {
    std::string id;
    int rank;         // 3..15 (15=2), 16=小王, 17=大王
    std::string suit; // "♠", "♥", "♣", "♦", "🃏"
    bool selected = false;

    std::string rankLabel() const {
        if (rank >= 3 && rank <= 10) return std::to_string(rank);
        if (rank == 11) return "J";
        if (rank == 12) return "Q";
        if (rank == 13) return "K";
        if (rank == 14) return "A";
        if (rank == 15) return "2";
        if (rank == 16) return "小王";
        if (rank == 17) return "大王";
        return std::to_string(rank);
    }

    bool isRed() const {
        return rank == 17 || suit == "♥" || suit == "♦";
    }

    std::string romfsImagePath() const {
        if (rank == 16) return "romfs:/cards/joker_16.jpg";
        if (rank == 17) return "romfs:/cards/joker_17.jpg";
        std::string code = "S";
        if (suit == "♥") code = "H";
        else if (suit == "♣") code = "C";
        else if (suit == "♦") code = "D";
        return "romfs:/cards/poker_" + code + "_" + std::to_string(rank) + ".jpg";
    }

    std::string toJson() const {
        return "{\"id\":\"" + MiniJson::esc(id) + "\",\"rank\":" + std::to_string(rank) + ",\"suit\":\"" + MiniJson::esc(suit) + "\"}";
    }

    static DdzCard fromJson(const std::string& j) {
        DdzCard c;
        c.id = MiniJson::getStr(j, "id");
        c.rank = MiniJson::getInt(j, "rank", 3);
        c.suit = MiniJson::getStr(j, "suit", "♠");
        return c;
    }
};

struct DdzEvalHand {
    std::string category = "invalid"; // single, pair, triple, tripleWithOne, tripleWithPair, straight, consecutivePairs, airplane, fourWithTwo, bomb, rocket
    int primaryRank = 0;
    int length = 0;
    std::vector<DdzCard> cards;

    std::string labelZh() const {
        if (category == "single") return "单张";
        if (category == "pair") return "对子";
        if (category == "triple") return "三不带";
        if (category == "tripleWithOne") return "三带一";
        if (category == "tripleWithPair") return "三带二";
        if (category == "straight") return "顺子";
        if (category == "consecutivePairs") return "连对";
        if (category == "airplane") return "飞机";
        if (category == "fourWithTwo") return "四带二";
        if (category == "bomb") return "炸弹";
        if (category == "rocket") return "王炸";
        return "";
    }

    std::string toJson() const {
        std::string arr = "[";
        for (size_t i = 0; i < cards.size(); ++i) {
            if (i > 0) arr += ",";
            arr += cards[i].toJson();
        }
        arr += "]";
        return "{\"category\":\"" + category + "\",\"primaryRank\":" + std::to_string(primaryRank) +
               ",\"length\":" + std::to_string(length) + ",\"cards\":" + arr + "}";
    }
};

namespace DdzEvaluator {
    inline DdzEvalHand evaluate(std::vector<DdzCard> cards) {
        DdzEvalHand res;
        if (cards.empty()) return res;
        std::sort(cards.begin(), cards.end(), [](const DdzCard& a, const DdzCard& b) {
            return a.rank > b.rank;
        });
        res.cards = cards;
        int n = (int)cards.size();
        res.length = n;

        std::map<int, int> freq;
        for (const auto& c : cards) freq[c.rank]++;

        if (n == 1) {
            res.category = "single";
            res.primaryRank = cards[0].rank;
            return res;
        }
        if (n == 2) {
            if (cards[0].rank == 17 && cards[1].rank == 16) {
                res.category = "rocket";
                res.primaryRank = 17;
                return res;
            }
            if (cards[0].rank == cards[1].rank) {
                res.category = "pair";
                res.primaryRank = cards[0].rank;
                return res;
            }
            return res;
        }
        if (n == 3 && freq.size() == 1) {
            res.category = "triple";
            res.primaryRank = cards[0].rank;
            return res;
        }
        if (n == 4) {
            if (freq.size() == 1) {
                res.category = "bomb";
                res.primaryRank = cards[0].rank;
                return res;
            }
            for (auto& kv : freq) {
                if (kv.second == 3) {
                    res.category = "tripleWithOne";
                    res.primaryRank = kv.first;
                    return res;
                }
            }
        }
        if (n == 5) {
            bool has3 = false, has2 = false;
            int r3 = 0;
            for (auto& kv : freq) {
                if (kv.second == 3) { has3 = true; r3 = kv.first; }
                if (kv.second == 2) has2 = true;
            }
            if (has3 && has2) {
                res.category = "tripleWithPair";
                res.primaryRank = r3;
                return res;
            }
        }
        // Straight (>= 5, all count==1, max rank <= 14)
        if (n >= 5 && (int)freq.size() == n) {
            int maxR = cards.front().rank;
            int minR = cards.back().rank;
            if (maxR <= 14 && (maxR - minR == n - 1)) {
                res.category = "straight";
                res.primaryRank = maxR;
                return res;
            }
        }
        // Consecutive pairs (>= 6, even, all count==2, max rank <= 14)
        if (n >= 6 && n % 2 == 0 && (int)freq.size() == n / 2) {
            bool all2 = true;
            for (auto& kv : freq) if (kv.second != 2) all2 = false;
            int maxR = cards.front().rank;
            int minR = cards.back().rank;
            if (all2 && maxR <= 14 && (maxR - minR == n / 2 - 1)) {
                res.category = "consecutivePairs";
                res.primaryRank = maxR;
                return res;
            }
        }
        return res;
    }

    inline bool canBeat(const DdzEvalHand& cand, const DdzEvalHand& target) {
        if (cand.category == "invalid") return false;
        if (target.category == "invalid" || target.cards.empty()) return true;
        if (cand.category == "rocket") return true;
        if (target.category == "rocket") return false;
        if (cand.category == "bomb" && target.category != "bomb") return true;
        if (cand.category == target.category && cand.length == target.length) {
            return cand.primaryRank > target.primaryRank;
        }
        return false;
    }
}

struct DdzSeat {
    int id = 0;
    std::string name;
    int characterId = 1;
    bool isAI = true;
    std::string peerDisplayName;
    std::vector<DdzCard> hand;
    bool isLandlord = false;
    std::string lastActionText;
    std::vector<DdzCard> lastPlayedCards;
    int score = 1000;

    std::string toJson() const {
        std::string hArr = "[";
        for (size_t i = 0; i < hand.size(); ++i) { if (i > 0) hArr += ","; hArr += hand[i].toJson(); }
        hArr += "]";
        std::string lpArr = "[";
        for (size_t i = 0; i < lastPlayedCards.size(); ++i) { if (i > 0) lpArr += ","; lpArr += lastPlayedCards[i].toJson(); }
        lpArr += "]";
        return "{\"id\":" + std::to_string(id) +
               ",\"name\":\"" + MiniJson::esc(name) + "\"" +
               ",\"characterId\":" + std::to_string(characterId) +
               ",\"isAI\":" + std::string(isAI ? "true" : "false") +
               ",\"peerDisplayName\":\"" + MiniJson::esc(peerDisplayName) + "\"" +
               ",\"hand\":" + hArr +
               ",\"isLandlord\":" + std::string(isLandlord ? "true" : "false") +
               ",\"lastActionText\":\"" + MiniJson::esc(lastActionText) + "\"" +
               ",\"lastPlayedCards\":" + lpArr +
               ",\"score\":" + std::to_string(score) + "}";
    }
};

// ============================================================================
// 2. 广东红中赖子麻将 (4P 136-Tile Mahjong Engine & Evaluator)
// ============================================================================
struct MjTile {
    std::string id;
    std::string suit; // "W"=万, "T"=条, "D"=筒, "H"=风/发/白(1..6), "Z"=红中(0)
    int rank = 0;

    bool isLaizi() const { return suit == "Z"; }

    int sortOrder() const {
        if (suit == "Z") return 0;
        if (suit == "W") return 10 + rank;
        if (suit == "T") return 20 + rank;
        if (suit == "D") return 30 + rank;
        return 40 + rank;
    }

    int typeKey() const {
        if (suit == "W") return rank - 1;
        if (suit == "T") return 9 + rank - 1;
        if (suit == "D") return 18 + rank - 1;
        if (suit == "H") return 27 + rank - 1;
        return 33; // Z
    }

    std::string fullName() const {
        if (suit == "Z") return "红中";
        if (suit == "H") {
            const char* h[] = {"", "东", "南", "西", "北", "发", "白"};
            return (rank >= 1 && rank <= 6) ? h[rank] : "字";
        }
        std::string u = (suit == "W") ? "万" : ((suit == "T") ? "条" : "筒");
        return std::to_string(rank) + u;
    }

    std::string romfsImagePath() const {
        return "romfs:/cards/mj_" + id + ".jpg";
    }

    std::string toJson() const {
        return "{\"id\":\"" + MiniJson::esc(id) + "\",\"suit\":\"" + suit + "\",\"rank\":" + std::to_string(rank) + "}";
    }

    static MjTile fromJson(const std::string& j) {
        MjTile t;
        t.id = MiniJson::getStr(j, "id");
        t.suit = MiniJson::getStr(j, "suit", "W");
        t.rank = MiniJson::getInt(j, "rank", 1);
        return t;
    }
};

struct MjMeld {
    std::string id;
    std::string kind; // "碰", "明杠", "暗杠"
    MjTile tile;

    std::string toJson() const {
        return "{\"id\":\"" + MiniJson::esc(id) + "\",\"kind\":\"" + MiniJson::esc(kind) + "\",\"tile\":" + tile.toJson() + "}";
    }

    static MjMeld fromJson(const std::string& j) {
        MjMeld m;
        m.id = MiniJson::getStr(j, "id");
        m.kind = MiniJson::getStr(j, "kind", "碰");
        std::string tObj = MiniJson::extractObject(j, "tile");
        m.tile = MjTile::fromJson(tObj.empty() ? j : tObj);
        return m;
    }
};

struct MjSeat {
    int id = 0;
    std::string name;
    int characterId = 1;
    bool isAI = true;
    std::string peerDisplayName;
    std::vector<MjTile> hand;
    std::vector<MjMeld> melds;
    std::vector<MjTile> discards;
    int score = 1000;
    bool isDealer = false;
    std::string lastActionText;

    std::string toJson() const {
        std::string hArr = "[";
        for (size_t i = 0; i < hand.size(); ++i) { if (i > 0) hArr += ","; hArr += hand[i].toJson(); }
        hArr += "]";
        std::string mArr = "[";
        for (size_t i = 0; i < melds.size(); ++i) { if (i > 0) mArr += ","; mArr += melds[i].toJson(); }
        mArr += "]";
        std::string dArr = "[";
        for (size_t i = 0; i < discards.size(); ++i) { if (i > 0) dArr += ","; dArr += discards[i].toJson(); }
        dArr += "]";
        return "{\"id\":" + std::to_string(id) +
               ",\"name\":\"" + MiniJson::esc(name) + "\"" +
               ",\"characterId\":" + std::to_string(characterId) +
               ",\"isAI\":" + std::string(isAI ? "true" : "false") +
               ",\"peerDisplayName\":\"" + MiniJson::esc(peerDisplayName) + "\"" +
               ",\"hand\":" + hArr +
               ",\"melds\":" + mArr +
               ",\"discards\":" + dArr +
               ",\"score\":" + std::to_string(score) +
               ",\"isDealer\":" + std::string(isDealer ? "true" : "false") +
               ",\"lastActionText\":\"" + MiniJson::esc(lastActionText) + "\"}";
    }
};

namespace MjEvaluator {
    inline void sortHand(std::vector<MjTile>& hand) {
        std::sort(hand.begin(), hand.end(), [](const MjTile& a, const MjTile& b) {
            if (a.sortOrder() != b.sortOrder()) return a.sortOrder() < b.sortOrder();
            return a.id < b.id;
        });
    }

    inline bool canFormMelds(std::vector<int>& counts, int laizi, int meldsNeeded) {
        if (meldsNeeded == 0) return true;
        int firstIdx = -1;
        for (int i = 0; i < 33; ++i) {
            if (counts[i] > 0) { firstIdx = i; break; }
        }
        if (firstIdx == -1) return laizi >= meldsNeeded * 3;

        // 1. Triplet (刻子)
        if (counts[firstIdx] >= 3) {
            counts[firstIdx] -= 3;
            if (canFormMelds(counts, laizi, meldsNeeded - 1)) { counts[firstIdx] += 3; return true; }
            counts[firstIdx] += 3;
        }
        if (counts[firstIdx] >= 2 && laizi >= 1) {
            counts[firstIdx] -= 2;
            if (canFormMelds(counts, laizi - 1, meldsNeeded - 1)) { counts[firstIdx] += 2; return true; }
            counts[firstIdx] += 2;
        }
        if (counts[firstIdx] >= 1 && laizi >= 2) {
            counts[firstIdx] -= 1;
            if (canFormMelds(counts, laizi - 2, meldsNeeded - 1)) { counts[firstIdx] += 1; return true; }
            counts[firstIdx] += 1;
        }

        // 2. Sequence (顺子) ONLY for W/T/D (0..26)
        if (firstIdx < 27) {
            int rankInSuit = firstIdx % 9;
            if (rankInSuit <= 6) {
                int i1 = firstIdx + 1, i2 = firstIdx + 2;
                int miss = (counts[i1] > 0 ? 0 : 1) + (counts[i2] > 0 ? 0 : 1);
                if (laizi >= miss) {
                    counts[firstIdx]--;
                    if (counts[i1] > 0) counts[i1]--;
                    if (counts[i2] > 0) counts[i2]--;
                    if (canFormMelds(counts, laizi - miss, meldsNeeded - 1)) {
                        counts[firstIdx]++;
                        if (miss == 0 || (counts[i1] >= 0)) {} // restore properly below
                    }
                }
            }
            // Clean backtracking sequence check
            if (rankInSuit <= 6) {
                int i1 = firstIdx + 1, i2 = firstIdx + 2;
                bool has1 = counts[i1] > 0, has2 = counts[i2] > 0;
                int miss = (has1 ? 0 : 1) + (has2 ? 0 : 1);
                if (laizi >= miss) {
                    counts[firstIdx]--;
                    if (has1) counts[i1]--;
                    if (has2) counts[i2]--;
                    bool ok = canFormMelds(counts, laizi - miss, meldsNeeded - 1);
                    counts[firstIdx]++;
                    if (has1) counts[i1]++;
                    if (has2) counts[i2]++;
                    if (ok) return true;
                }
            }
        }
        return false;
    }

    inline bool canHu(const std::vector<MjTile>& hand, int meldsCount) {
        int totalTiles = (int)hand.size() + meldsCount * 3;
        if (totalTiles != 14) return false;
        int laizi = 0;
        std::vector<int> counts(33, 0);
        for (const auto& t : hand) {
            if (t.isLaizi()) laizi++;
            else counts[t.typeKey()]++;
        }
        if (laizi == 4) return true; // 四红中直接胡

        // 7 Pairs check
        if (meldsCount == 0 && hand.size() == 14) {
            int singles = 0;
            for (int c : counts) singles += (c % 2);
            if (laizi >= singles) return true;
        }

        int meldsNeeded = 4 - meldsCount;
        for (int i = 0; i < 33; ++i) {
            if (counts[i] >= 2) {
                counts[i] -= 2;
                if (canFormMelds(counts, laizi, meldsNeeded)) return true;
                counts[i] += 2;
            }
            if (counts[i] >= 1 && laizi >= 1) {
                counts[i] -= 1;
                if (canFormMelds(counts, laizi - 1, meldsNeeded)) return true;
                counts[i] += 1;
            }
        }
        if (laizi >= 2 && canFormMelds(counts, laizi - 2, meldsNeeded)) return true;
        return false;
    }
}


// ============================================================================
// 3. 3D 轻音部五人飞行棋 (Extensible 2P/3P/4P/5P Board Config, Tsumugi = Pink)
// ============================================================================
struct LudoBoardConfig {
    std::string mapId = "kon_5p_pentagon";
    int playerCount = 5;       // 5 ready; 2, 3, 4 reserved for future maps
    int outerRingCount = 55;
    int sectorLength = 11;
    int outerTravelSteps = 53;
    int homeStretchSteps = 7;
    int totalStepsToFinish = 60;
};

struct LudoPt { float x; float y; };
static const LudoPt kLudoOuterCoords[55] = {{0.5f, 0.1767f}, {0.5369f, 0.1788f}, {0.5719f, 0.1906f}, {0.6025f, 0.2128f}, {0.631f, 0.2336f}, {0.6584f, 0.2535f}, {0.6855f, 0.2732f}, {0.7129f, 0.2931f}, {0.7415f, 0.3138f}, {0.772f, 0.336f}, {0.7941f, 0.3657f}, {0.8075f, 0.4001f}, {0.8169f, 0.4358f}, {0.8164f, 0.4728f}, {0.8048f, 0.5087f}, {0.7939f, 0.5423f}, {0.7834f, 0.5745f}, {0.7731f, 0.6063f}, {0.7626f, 0.6386f}, {0.7517f, 0.6721f}, {0.74f, 0.708f}, {0.7186f, 0.7382f}, {0.6901f, 0.7616f}, {0.659f, 0.7815f}, {0.6236f, 0.7926f}, {0.5859f, 0.7926f}, {0.5506f, 0.7926f}, {0.5167f, 0.7926f}, {0.4833f, 0.7926f}, {0.4494f, 0.7926f}, {0.4141f, 0.7926f}, {0.3764f, 0.7926f}, {0.341f, 0.7815f}, {0.3099f, 0.7616f}, {0.2814f, 0.7382f}, {0.26f, 0.708f}, {0.2483f, 0.6721f}, {0.2374f, 0.6386f}, {0.2269f, 0.6063f}, {0.2166f, 0.5745f}, {0.2061f, 0.5423f}, {0.1952f, 0.5087f}, {0.1836f, 0.4728f}, {0.1831f, 0.4358f}, {0.1925f, 0.4001f}, {0.2059f, 0.3657f}, {0.228f, 0.336f}, {0.2585f, 0.3138f}, {0.2871f, 0.2931f}, {0.3145f, 0.2732f}, {0.3416f, 0.2535f}, {0.369f, 0.2336f}, {0.3975f, 0.2128f}, {0.4281f, 0.1906f}, {0.4631f, 0.1788f}};
static const LudoPt kLudoHomeCoords[5][7] = {
    {{0.4083f, 0.2388f}, {0.4192f, 0.2647f}, {0.43f, 0.2907f}, {0.4408f, 0.3166f}, {0.4516f, 0.3426f}, {0.4624f, 0.3685f}, {0.4732f, 0.3945f}},
    {{0.7201f, 0.3321f}, {0.6988f, 0.3504f}, {0.6774f, 0.3687f}, {0.6561f, 0.387f}, {0.6348f, 0.4053f}, {0.6134f, 0.4236f}, {0.5921f, 0.4419f}},
    {{0.7277f, 0.6575f}, {0.7037f, 0.6428f}, {0.6797f, 0.6282f}, {0.6557f, 0.6136f}, {0.6317f, 0.5989f}, {0.6077f, 0.5843f}, {0.5837f, 0.5696f}},
    {{0.4206f, 0.7652f}, {0.4271f, 0.7379f}, {0.4336f, 0.7105f}, {0.4401f, 0.6832f}, {0.4466f, 0.6558f}, {0.4531f, 0.6285f}, {0.4596f, 0.6011f}},
    {{0.2232f, 0.5064f}, {0.2513f, 0.5042f}, {0.2793f, 0.5019f}, {0.3073f, 0.4996f}, {0.3353f, 0.4974f}, {0.3633f, 0.4951f}, {0.3914f, 0.4929f}}
};
static const LudoPt kLudoHangarCoords[5][4] = {
    {{0.6032f, 0.0803f}, {0.6532f, 0.0803f}, {0.6032f, 0.127f}, {0.6532f, 0.127f}},
    {{0.89f, 0.475f}, {0.94f, 0.475f}, {0.89f, 0.5217f}, {0.94f, 0.5217f}},
    {{0.6032f, 0.8697f}, {0.6532f, 0.8697f}, {0.6032f, 0.9164f}, {0.6532f, 0.9164f}},
    {{0.1393f, 0.7189f}, {0.1893f, 0.7189f}, {0.1393f, 0.7656f}, {0.1893f, 0.7656f}},
    {{0.1393f, 0.2311f}, {0.1893f, 0.2311f}, {0.1393f, 0.2777f}, {0.1893f, 0.2777f}}
};

struct LudoSeat {
    int id = 0;
    std::string name;
    int characterId = 1; // 1=Yui(Red), 2=Mio(Blue), 3=Ritsu(Yellow), 4=Mugi(Pink), 5=Azusa(Mint)
    bool isAI = true;
    std::string peerDisplayName;
    int planes[4] = {-1, -1, -1, -1};
    int score = 1000;
    std::string colorName = "樱桃红";
};


// ============================================================================
// 4. 拉密数字牌 (Rummikub · 106 Tiles · 30-Pt Icebreak · Table Rearrange)
// ============================================================================
struct RmkTile {
    std::string id;
    std::string color; // "R", "B", "Y", "K", "J"
    int number = 0;    // 1..13, 0 = Joker
    bool selected = false;

    bool isJoker() const { return color == "J"; }
    std::string colorZh() const {
        if (color == "R") return "红";
        if (color == "B") return "蓝";
        if (color == "Y") return "黄";
        if (color == "K") return "黑";
        return "鬼";
    }
    std::string toJson() const {
        return "{\"id\":\"" + MiniJson::esc(id) + "\",\"color\":\"" + color + "\",\"number\":" + std::to_string(number) + "}";
    }
    static RmkTile fromJson(const std::string& j) {
        RmkTile t;
        t.id = MiniJson::getStr(j, "id");
        t.color = MiniJson::getStr(j, "color", "R");
        t.number = MiniJson::getInt(j, "number", 1);
        return t;
    }
};

struct RmkMeld {
    std::string id;
    std::vector<RmkTile> tiles;

    std::string toJson() const {
        std::string arr = "[";
        for (size_t i = 0; i < tiles.size(); ++i) { if (i > 0) arr += ","; arr += tiles[i].toJson(); }
        arr += "]";
        return "{\"id\":\"" + MiniJson::esc(id) + "\",\"tiles\":" + arr + "}";
    }
};

struct RmkSeat {
    int id = 0;
    std::string name;
    int characterId = 1;
    bool isAI = true;
    std::string peerDisplayName;
    std::vector<RmkTile> hand;
    bool hasBrokenIce = false;
    int score = 1000;
};

namespace RmkEvaluator {
    inline int evaluateMeld(const std::vector<RmkTile>& tiles) {
        if (tiles.size() < 3) return -1;
        int jokers = 0;
        std::vector<RmkTile> norms;
        for (const auto& t : tiles) {
            if (t.isJoker()) jokers++;
            else norms.push_back(t);
        }
        if (norms.empty()) return -1;

        // Group (max 4, same number, distinct colors)
        if (tiles.size() <= 4) {
            int num = norms[0].number;
            bool sameNum = true;
            std::set<std::string> cols;
            for (const auto& t : norms) {
                if (t.number != num) sameNum = false;
                cols.insert(t.color);
            }
            if (sameNum && cols.size() == norms.size()) return num * (int)tiles.size();
        }

        // Run (same color, strictly consecutive 1..13)
        std::string col = norms[0].color;
        bool sameCol = true;
        std::vector<int> nums;
        std::set<int> uniqN;
        for (const auto& t : norms) {
            if (t.color != col) sameCol = false;
            nums.push_back(t.number);
            uniqN.insert(t.number);
        }
        if (sameCol && uniqN.size() == norms.size() && tiles.size() <= 13) {
            std::sort(nums.begin(), nums.end());
            int span = nums.back() - nums.front() + 1;
            int gaps = span - (int)nums.size();
            if (gaps <= jokers) {
                int remJ = jokers - gaps;
                int low = nums.front(), high = nums.back();
                while (remJ > 0 && high < 13) { high++; remJ--; }
                while (remJ > 0 && low > 1) { low--; remJ--; }
                if ((high - low + 1) == (int)tiles.size() && low >= 1 && high <= 13) {
                    return (low + high) * (int)tiles.size() / 2;
                }
            }
        }
        return -1;
    }

    inline std::vector<RmkTile> findBestMeld(const std::vector<RmkTile>& hand) {
        std::vector<RmkTile> jokers;
        std::map<int, std::vector<RmkTile>> byNum;
        std::map<std::string, std::vector<RmkTile>> byCol;
        for (const auto& t : hand) {
            if (t.isJoker()) jokers.push_back(t);
            else { byNum[t.number].push_back(t); byCol[t.color].push_back(t); }
        }
        std::vector<RmkTile> best;
        int bestPts = 0;

        for (auto& kv : byNum) {
            std::vector<RmkTile> uniq;
            std::set<std::string> seen;
            for (const auto& t : kv.second) if (seen.insert(t.color).second) uniq.push_back(t);
            if (uniq.size() >= 3) {
                int pts = evaluateMeld(uniq);
                if (pts > bestPts) { bestPts = pts; best = uniq; }
            } else if (uniq.size() == 2 && !jokers.empty()) {
                auto cand = uniq; cand.push_back(jokers[0]);
                int pts = evaluateMeld(cand);
                if (pts > bestPts) { bestPts = pts; best = cand; }
            }
        }

        for (auto& kv : byCol) {
            auto vec = kv.second;
            std::sort(vec.begin(), vec.end(), [](const RmkTile& a, const RmkTile& b) { return a.number < b.number; });
            std::vector<RmkTile> uniq;
            std::set<int> seen;
            for (const auto& t : vec) if (seen.insert(t.number).second) uniq.push_back(t);
            std::vector<RmkTile> cur;
            for (const auto& t : uniq) {
                if (cur.empty() || t.number == cur.back().number + 1) cur.push_back(t);
                else {
                    if (cur.size() >= 3) { int pts = evaluateMeld(cur); if (pts > bestPts) { bestPts = pts; best = cur; } }
                    cur = {t};
                }
            }
            if (cur.size() >= 3) { int pts = evaluateMeld(cur); if (pts > bestPts) { bestPts = pts; best = cur; } }
        }
        return best;
    }
}
