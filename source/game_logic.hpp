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

    inline std::string getStr(const std::string& json, const std::string& key, const std::string& defVal = "") {
        std::string pat = "\"" + key + "\":\"";
        size_t pos = json.find(pat);
        if (pos == std::string::npos) return defVal;
        pos += pat.size();
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
        std::string pat = "\"" + key + "\":";
        size_t pos = json.find(pat);
        if (pos == std::string::npos) return defVal;
        pos += pat.size();
        while (pos < json.size() && (json[pos] == ' ' || json[pos] == '"')) pos++;
        if (pos >= json.size() || (!isdigit(json[pos]) && json[pos] != '-')) return defVal;
        return std::atoi(json.c_str() + pos);
    }

    inline bool getBool(const std::string& json, const std::string& key, bool defVal = false) {
        std::string pat = "\"" + key + "\":";
        size_t pos = json.find(pat);
        if (pos == std::string::npos) return defVal;
        pos += pat.size();
        while (pos < json.size() && json[pos] == ' ') pos++;
        if (json.compare(pos, 4, "true") == 0) return true;
        if (json.compare(pos, 5, "false") == 0) return false;
        return defVal;
    }

    // Splits a top-level JSON array `[{...},{...}]` into object strings
    inline std::vector<std::string> extractObjectsArray(const std::string& json, const std::string& arrayKey) {
        std::vector<std::string> items;
        std::string pat = "\"" + arrayKey + "\":[";
        size_t pos = json.find(pat);
        if (pos == std::string::npos) return items;
        pos += pat.size();
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
        if (category == "bomb") return "💣 炸弹";
        if (category == "rocket") return "🚀 王炸";
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
