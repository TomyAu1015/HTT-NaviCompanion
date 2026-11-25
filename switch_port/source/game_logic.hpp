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

    static DdzEvalHand fromJson(const std::string& j) {
        DdzEvalHand h;
        if (j.empty()) return h;
        h.category = MiniJson::getStr(j, "category", "invalid");
        h.primaryRank = MiniJson::getInt(j, "primaryRank", 0);
        h.length = MiniJson::getInt(j, "length", 0);
        auto cObjs = MiniJson::extractObjectsArray(j, "cards");
        for (const auto& co : cObjs) h.cards.push_back(DdzCard::fromJson(co));
        return h;
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
        std::string sUp = suit;
        for (auto& ch : sUp) ch = (char)toupper((unsigned char)ch);
        if (sUp != "W" && sUp != "T" && sUp != "D" && sUp != "H" && sUp != "Z") sUp = "W";
        int r = (sUp == "Z") ? 0 : std::max(1, std::min((sUp == "H" ? 6 : 9), rank));
        int copyIdx = 0;
        size_t pos = id.rfind('_');
        if (pos != std::string::npos && pos + 1 < id.size()) {
            int rawC = std::atoi(id.c_str() + pos + 1);
            copyIdx = (rawC >= 4) ? ((rawC - 1) % 4) : (rawC < 0 ? 0 : (rawC % 4));
        }
        return "romfs:/cards/mj_" + sUp + "_" + std::to_string(r) + "_" + std::to_string(copyIdx) + ".jpg";
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

        // 2. Sequence (顺子) across ALL 3 windows containing firstIdx
        if (firstIdx < 27) {
            int suitBase = (firstIdx / 9) * 9;
            for (int start = firstIdx - 2; start <= firstIdx; ++start) {
                if (start >= suitBase && start + 2 <= suitBase + 8) {
                    int miss = 0;
                    int used[3] = {0, 0, 0};
                    int usedCnt = 0;
                    for (int k = start; k <= start + 2; ++k) {
                        if (counts[k] > 0) {
                            counts[k]--;
                            used[usedCnt++] = k;
                        } else {
                            miss++;
                        }
                    }
                    bool ok = (laizi >= miss) && canFormMelds(counts, laizi - miss, meldsNeeded - 1);
                    for (int u = 0; u < usedCnt; ++u) counts[used[u]]++;
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

    inline MjTile bestAiDiscard(const std::vector<MjTile>& hand, int meldsCount, int difficulty) {
        std::vector<MjTile> nonLaizi;
        for (const auto& t : hand) if (!t.isLaizi()) nonLaizi.push_back(t);
        if (nonLaizi.empty()) return hand.back();
        int counts[33] = {0};
        for (const auto& t : nonLaizi) {
            int k = t.typeKey();
            if (k >= 0 && k < 33) counts[k]++;
        }
        if (difficulty == 0) {
            // Casual AI: discard isolated or terminal tiles simply
            MjTile best = nonLaizi[0];
            int lowest = 999999;
            for (const auto& t : nonLaizi) {
                int k = t.typeKey();
                int sc = (counts[k] - 1) * 10 + (rand() % 5);
                if (k < 27) {
                    int pos = k % 9;
                    if (pos > 0 && counts[k - 1] > 0) sc += 5;
                    if (pos < 8 && counts[k + 1] > 0) sc += 5;
                }
                if (sc < lowest) { lowest = sc; best = t; }
            }
            return best;
        }
        if (difficulty >= 2) {
            // Master AI: evaluate remaining-hand potential + ready-tile count
            int bestIdx = 0;
            int worstTileScore = 999999;
            for (size_t i = 0; i < nonLaizi.size(); ++i) {
                const auto& t = nonLaizi[i];
                int k = t.typeKey();
                int sc = (counts[k] - 1) * 18;
                if (counts[k] >= 3) sc += 20;
                if (k < 27) {
                    int pos = k % 9;
                    if (pos > 0 && counts[k - 1] > 0) sc += 10;
                    if (pos < 8 && counts[k + 1] > 0) sc += 10;
                    if (pos > 1 && counts[k - 2] > 0) sc += 4;
                    if (pos < 7 && counts[k + 2] > 0) sc += 4;
                    if (pos == 0 || pos == 8) sc -= 3;
                } else {
                    sc -= 5;
                }
                // Bonus if discarding this tile leaves us closer to tenpai
                if (sc < worstTileScore) { worstTileScore = sc; bestIdx = (int)i; }
            }
            return nonLaizi[bestIdx];
        }
        // Standard AI
        MjTile best = nonLaizi[0];
        int lowest = 999999;
        for (const auto& t : nonLaizi) {
            int k = t.typeKey();
            int sc = (counts[k] - 1) * 14;
            if (k < 27) {
                int pos = k % 9;
                if (pos > 0 && counts[k - 1] > 0) sc += 7;
                if (pos < 8 && counts[k + 1] > 0) sc += 7;
                if (pos > 1 && counts[k - 2] > 0) sc += 3;
                if (pos < 7 && counts[k + 2] > 0) sc += 3;
                if (pos == 0 || pos == 8) sc -= 2;
            } else {
                sc -= 3;
            }
            if (sc < lowest) { lowest = sc; best = t; }
        }
        return best;
    }
}


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
        if (color == "K") return "绿";
        return "百搭";
    }
    std::string romfsImagePath() const {
        if (isJoker()) return "romfs:/cards/rmk_joker.png";
        int cIdx = (color == "R") ? 1 : ((color == "B") ? 2 : ((color == "Y") ? 3 : 4));
        int n = std::max(1, std::min(13, number));
        return "romfs:/cards/rmk_" + std::to_string(cIdx) + "_" + std::to_string(n) + ".png";
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
    inline std::vector<RmkTile> sortMeldForDisplay(const std::vector<RmkTile>& tiles) {
        std::vector<RmkTile> jokers;
        std::vector<RmkTile> norms;
        for (const auto& t : tiles) {
            if (t.isJoker()) jokers.push_back(t);
            else norms.push_back(t);
        }
        if (norms.empty()) return tiles;
        std::sort(norms.begin(), norms.end(), [](const RmkTile& a, const RmkTile& b) {
            if (a.number != b.number) return a.number < b.number;
            return a.color < b.color;
        });
        bool sameNum = true;
        for (const auto& t : norms) if (t.number != norms[0].number) sameNum = false;
        if (sameNum) {
            norms.insert(norms.end(), jokers.begin(), jokers.end());
            return norms;
        }
        std::vector<RmkTile> res;
        size_t jIdx = 0;
        for (size_t i = 0; i < norms.size(); ++i) {
            res.push_back(norms[i]);
            if (i + 1 < norms.size()) {
                int gap = norms[i + 1].number - norms[i].number - 1;
                for (int g = 0; g < gap && jIdx < jokers.size(); ++g) {
                    res.push_back(jokers[jIdx++]);
                }
            }
        }
        int curLow = norms.front().number;
        int curHigh = norms.back().number;
        while (jIdx < jokers.size()) {
            RmkTile j = jokers[jIdx++];
            if (curHigh >= 13 && curLow > 1) {
                res.insert(res.begin(), j);
                curLow--;
            } else if (curHigh < 13) {
                res.push_back(j);
                curHigh++;
            } else {
                res.insert(res.begin(), j);
                curLow--;
            }
        }
        return res;
    }

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

    // Smart Auto-Splitter: e.g. 234567 + 4 -> 2344567 -> [234, 4567], or 12344567 -> [1234, 4567]
    inline std::vector<std::vector<RmkTile>> autoSplitMeldTiles(const std::vector<RmkTile>& tiles) {
        if (evaluateMeld(tiles) >= 0) {
            return {sortMeldForDisplay(tiles)};
        }
        if (tiles.size() < 4) {
            return {sortMeldForDisplay(tiles)};
        }
        std::vector<RmkTile> norms, jokers;
        for (const auto& t : tiles) {
            if (t.isJoker()) jokers.push_back(t);
            else norms.push_back(t);
        }
        if (norms.empty()) return {tiles};

        // Case 1: Same-color run with duplicate number (e.g. 2,3,4,4,5,6,7) or gap (e.g. 1,2,3,5,6,7)
        std::string firstCol = norms[0].color;
        bool allSameCol = true;
        for (const auto& t : norms) if (t.color != firstCol) allSameCol = false;
        if (allSameCol) {
            auto sortedNorms = norms;
            std::sort(sortedNorms.begin(), sortedNorms.end(), [](const RmkTile& a, const RmkTile& b) {
                if (a.number != b.number) return a.number < b.number;
                return a.id < b.id;
            });
            for (size_t i = 0; i + 1 < sortedNorms.size(); ++i) {
                if (sortedNorms[i].number == sortedNorms[i + 1].number) {
                    std::vector<RmkTile> leftNorms(sortedNorms.begin(), sortedNorms.begin() + i + 1);
                    std::vector<RmkTile> rightNorms(sortedNorms.begin() + i + 1, sortedNorms.end());
                    for (size_t jLeft = 0; jLeft <= jokers.size(); ++jLeft) {
                        std::vector<RmkTile> leftCand = leftNorms;
                        leftCand.insert(leftCand.end(), jokers.begin(), jokers.begin() + jLeft);
                        std::vector<RmkTile> rightCand = rightNorms;
                        rightCand.insert(rightCand.end(), jokers.begin() + jLeft, jokers.end());
                        if (evaluateMeld(leftCand) >= 0 && evaluateMeld(rightCand) >= 0) {
                            return {sortMeldForDisplay(leftCand), sortMeldForDisplay(rightCand)};
                        }
                    }
                    std::vector<RmkTile> leftFallback = leftNorms;
                    leftFallback.insert(leftFallback.end(), jokers.begin(), jokers.end());
                    if (evaluateMeld(leftFallback) >= 0 || evaluateMeld(rightNorms) >= 0) {
                        return {sortMeldForDisplay(leftFallback), sortMeldForDisplay(rightNorms)};
                    }
                }
            }
            for (size_t i = 0; i + 1 < sortedNorms.size(); ++i) {
                if (sortedNorms[i + 1].number - sortedNorms[i].number > 1) {
                    std::vector<RmkTile> leftNorms(sortedNorms.begin(), sortedNorms.begin() + i + 1);
                    std::vector<RmkTile> rightNorms(sortedNorms.begin() + i + 1, sortedNorms.end());
                    if (evaluateMeld(leftNorms) >= 0 && evaluateMeld(rightNorms) >= 0 && jokers.empty()) {
                        return {sortMeldForDisplay(leftNorms), sortMeldForDisplay(rightNorms)};
                    }
                }
            }
        }

        // Case 2: Same-number group with duplicate colors (>4 tiles)
        int firstNum = norms[0].number;
        bool allSameNum = true;
        for (const auto& t : norms) if (t.number != firstNum) allSameNum = false;
        if (allSameNum && tiles.size() >= 4) {
            std::set<std::string> seenCols;
            std::vector<RmkTile> g1, g2;
            for (const auto& t : norms) {
                if (seenCols.insert(t.color).second && g1.size() < 4) g1.push_back(t);
                else g2.push_back(t);
            }
            for (const auto& j : jokers) {
                if (g1.size() < 3) g1.push_back(j);
                else g2.push_back(j);
            }
            if (!g2.empty() && (evaluateMeld(g1) >= 0 || evaluateMeld(g2) >= 0)) {
                return {sortMeldForDisplay(g1), sortMeldForDisplay(g2)};
            }
        }
        return {sortMeldForDisplay(tiles)};
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

    inline void extractRunsFromPool(std::vector<RmkTile>& pool, std::vector<std::vector<RmkTile>>& extracted) {
        const char* cols[] = {"R", "B", "Y", "K"};
        for (int c = 0; c < 4; ++c) {
            std::string col = cols[c];
            bool found = true;
            while (found) {
                found = false;
                std::vector<RmkTile> colTiles;
                for (const auto& t : pool) if (t.color == col) colTiles.push_back(t);
                std::sort(colTiles.begin(), colTiles.end(), [](const RmkTile& a, const RmkTile& b) { return a.number < b.number; });
                std::vector<RmkTile> uniq;
                std::set<int> seen;
                for (const auto& t : colTiles) if (seen.insert(t.number).second) uniq.push_back(t);
                if (uniq.size() < 3) break;
                std::vector<RmkTile> bestRun;
                std::vector<RmkTile> cur;
                for (const auto& t : uniq) {
                    if (cur.empty() || t.number == cur.back().number + 1) {
                        cur.push_back(t);
                    } else {
                        if (cur.size() >= 3 && cur.size() > bestRun.size()) bestRun = cur;
                        cur = {t};
                    }
                }
                if (cur.size() >= 3 && cur.size() > bestRun.size()) bestRun = cur;
                if (bestRun.size() >= 3) {
                    extracted.push_back(bestRun);
                    std::set<std::string> usedIds;
                    for (const auto& t : bestRun) usedIds.insert(t.id);
                    pool.erase(std::remove_if(pool.begin(), pool.end(), [&](const RmkTile& t) { return usedIds.count(t.id) > 0; }), pool.end());
                    found = true;
                }
            }
        }
    }

    inline void extractGroupsFromPool(std::vector<RmkTile>& pool, std::vector<std::vector<RmkTile>>& extracted) {
        for (int num = 13; num >= 1; --num) {
            bool found = true;
            while (found) {
                found = false;
                std::vector<RmkTile> sameNum;
                for (const auto& t : pool) if (!t.isJoker() && t.number == num) sameNum.push_back(t);
                std::vector<RmkTile> uniq;
                std::set<std::string> seen;
                for (const auto& t : sameNum) if (seen.insert(t.color).second) uniq.push_back(t);
                if (uniq.size() >= 3) {
                    std::vector<RmkTile> grp(uniq.begin(), uniq.begin() + std::min((size_t)4, uniq.size()));
                    extracted.push_back(grp);
                    std::set<std::string> usedIds;
                    for (const auto& t : grp) usedIds.insert(t.id);
                    pool.erase(std::remove_if(pool.begin(), pool.end(), [&](const RmkTile& t) { return usedIds.count(t.id) > 0; }), pool.end());
                    found = true;
                }
            }
        }
    }

    // 789 (preferRuns=true) or 777 (preferRuns=false) smart organizer with empty-slot separation
    inline void organizeHandIntoGroups(
        const std::vector<RmkTile>& hand,
        bool preferRuns,
        std::vector<std::vector<RmkTile>>& outMelds,
        std::vector<RmkTile>& outLeftovers
    ) {
        outMelds.clear();
        outLeftovers.clear();
        std::vector<RmkTile> pool = hand;
        if (preferRuns) {
            extractRunsFromPool(pool, outMelds);
        } else {
            extractGroupsFromPool(pool, outMelds);
        }

        // Try pairing 1 Joker with a 2-tile near-meld
        while (true) {
            int jIdx = -1;
            for (size_t i = 0; i < pool.size(); ++i) if (pool[i].isJoker()) { jIdx = (int)i; break; }
            if (jIdx < 0) break;
            RmkTile joker = pool[jIdx];
            std::vector<RmkTile> bestPair;
            if (preferRuns) {
                const char* cols[] = {"R", "B", "Y", "K"};
                for (int c = 0; c < 4 && bestPair.empty(); ++c) {
                    std::string col = cols[c];
                    std::vector<RmkTile> ct;
                    for (const auto& t : pool) if (t.color == col) ct.push_back(t);
                    std::sort(ct.begin(), ct.end(), [](const RmkTile& a, const RmkTile& b) { return a.number < b.number; });
                    for (size_t i = 0; i + 1 < ct.size(); ++i) {
                        int diff = ct[i + 1].number - ct[i].number;
                        if (diff == 1 || diff == 2) {
                            bestPair = {ct[i], ct[i + 1], joker};
                            break;
                        }
                    }
                }
            }
            else {
                for (int num = 13; num >= 1; --num) {
                    std::vector<RmkTile> sn;
                    std::set<std::string> seen;
                    for (const auto& t : pool) {
                        if (!t.isJoker() && t.number == num && seen.insert(t.color).second) sn.push_back(t);
                    }
                    if (sn.size() >= 2) {
                        bestPair = {sn[0], sn[1], joker};
                        break;
                    }
                }
            }
            if (!bestPair.empty()) {
                outMelds.push_back(bestPair);
                std::set<std::string> usedIds;
                for (const auto& t : bestPair) usedIds.insert(t.id);
                pool.erase(std::remove_if(pool.begin(), pool.end(), [&](const RmkTile& t) { return usedIds.count(t.id) > 0; }), pool.end());
            } else {
                break;
            }
        }

        std::sort(pool.begin(), pool.end(), [preferRuns](const RmkTile& a, const RmkTile& b) {
            if (a.isJoker() != b.isJoker()) return !a.isJoker();
            if (preferRuns) {
                if (a.color != b.color) return a.color < b.color;
                return a.number < b.number;
            } else {
                if (a.number != b.number) return a.number < b.number;
                return a.color < b.color;
            }
        });
        outLeftovers = pool;
    }

    // Smart Rummikub AI (1:1 like video): plays hand melds AND extends/splits existing table melds after breaking ice!
    inline bool findAITableCombinationMove(
        const std::vector<RmkTile>& hand,
        const std::vector<RmkMeld>& tableMelds,
        bool hasBrokenIce,
        uint32_t seedTick,
        std::vector<RmkMeld>& outNewMelds,
        std::set<std::string>& outPlayedIds,
        std::set<std::string>& outHighlightedIds
    ) {
        outNewMelds = tableMelds;
        outPlayedIds.clear();
        outHighlightedIds.clear();

        std::vector<RmkTile> remHand = hand;
        std::vector<std::vector<RmkTile>> rMelds, gMelds;
        std::vector<RmkTile> afterRuns, afterBoth;
        organizeHandIntoGroups(remHand, true, rMelds, afterRuns);
        organizeHandIntoGroups(afterRuns, false, gMelds, afterBoth);

        std::vector<std::vector<RmkTile>> chosenHandMelds = rMelds;
        chosenHandMelds.insert(chosenHandMelds.end(), gMelds.begin(), gMelds.end());

        int totalHandPts = 0;
        for (const auto& m : chosenHandMelds) {
            int p = evaluateMeld(m);
            if (p > 0) totalHandPts += p;
        }

        if (!hasBrokenIce) {
            if (totalHandPts < 30) return false;
            std::sort(chosenHandMelds.begin(), chosenHandMelds.end(), [](const auto& a, const auto& b) {
                return evaluateMeld(a) > evaluateMeld(b);
            });
            std::vector<std::vector<RmkTile>> minMelds;
            int accPts = 0;
            for (const auto& m : chosenHandMelds) {
                minMelds.push_back(m);
                int p = evaluateMeld(m);
                if (p > 0) accPts += p;
                if (accPts >= 30) break;
            }
            chosenHandMelds = std::move(minMelds);
        } else if (chosenHandMelds.size() > 1) {
            size_t totalPlayed = 0;
            for (const auto& m : chosenHandMelds) totalPlayed += m.size();
            if (totalPlayed < hand.size()) {
                std::sort(chosenHandMelds.begin(), chosenHandMelds.end(), [](const auto& a, const auto& b) {
                    return evaluateMeld(a) > evaluateMeld(b);
                });
                if (chosenHandMelds.size() > 2) chosenHandMelds.resize(2);
            }
        }

        int mSeq = 1;
        if (hasBrokenIce || totalHandPts >= 30) {
            for (const auto& m : chosenHandMelds) {
                auto sortedM = sortMeldForDisplay(m);
                outNewMelds.push_back({"m_" + std::to_string(seedTick) + "_" + std::to_string(mSeq++), sortedM});
                for (const auto& t : sortedM) {
                    outPlayedIds.insert(t.id);
                    outHighlightedIds.insert(t.id);
                }
            }
            std::vector<RmkTile> nextRem;
            for (const auto& ht : hand) {
                if (!outPlayedIds.count(ht.id)) nextRem.push_back(ht);
            }
            remHand = std::move(nextRem);
        }

        if (hasBrokenIce) {
            bool changed = true;
            int tableActions = 0;
            int maxTableActions = (remHand.size() <= 3) ? 4 : (chosenHandMelds.empty() ? 2 : 1);
            while (changed && tableActions < maxTableActions) {
                changed = false;
                // 1-Joker. Combine hand Joker + 1 hand tile + 1 spare table tile before appending Joker!
                int jIdx = -1;
                for (size_t i = 0; i < remHand.size(); ++i) if (remHand[i].isJoker()) { jIdx = (int)i; break; }
                if (jIdx >= 0 && remHand.size() >= 2) {
                    RmkTile jTile = remHand[jIdx];
                    for (size_t hIdx = 0; hIdx < remHand.size() && !changed; ++hIdx) {
                        if ((int)hIdx == jIdx || remHand[hIdx].isJoker()) continue;
                        RmkTile ht = remHand[hIdx];
                        for (size_t mIdx = 0; mIdx < outNewMelds.size() && !changed; ++mIdx) {
                            const auto& mTiles = outNewMelds[mIdx].tiles;
                            if (mTiles.size() < 4) continue;
                            for (size_t cIdx = 0; cIdx < mTiles.size() && !changed; ++cIdx) {
                                RmkTile spareTile = mTiles[cIdx];
                                auto remainTable = mTiles;
                                remainTable.erase(remainTable.begin() + cIdx);
                                if (evaluateMeld(remainTable) < 0) continue;
                                std::vector<RmkTile> newTriad = {jTile, ht, spareTile};
                                if (evaluateMeld(newTriad) >= 0) {
                                    outNewMelds[mIdx].tiles = sortMeldForDisplay(remainTable);
                                    outNewMelds.push_back({"m_" + std::to_string(seedTick) + "_" + std::to_string(mSeq++), sortMeldForDisplay(newTriad)});
                                    outPlayedIds.insert(jTile.id);
                                    outPlayedIds.insert(ht.id);
                                    outHighlightedIds.insert(jTile.id);
                                    outHighlightedIds.insert(ht.id);
                                    outHighlightedIds.insert(spareTile.id);
                                    remHand.erase(std::remove_if(remHand.begin(), remHand.end(), [&](const RmkTile& t) {
                                        return t.id == jTile.id || t.id == ht.id;
                                    }), remHand.end());
                                    tableActions++;
                                    changed = true;
                                }
                            }
                        }
                    }
                    if (changed) continue;
                }

                // 1. Try appending/prepending any single NON-JOKER hand tile onto an existing table meld
                for (size_t hIdx = 0; hIdx < remHand.size() && !changed; ++hIdx) {
                    const auto& ht = remHand[hIdx];
                    if (ht.isJoker() && remHand.size() > 1) continue;
                    for (size_t mIdx = 0; mIdx < outNewMelds.size(); ++mIdx) {
                        auto cand = outNewMelds[mIdx].tiles;
                        cand.push_back(ht);
                        if (evaluateMeld(cand) >= 0) {
                            outNewMelds[mIdx].tiles = sortMeldForDisplay(cand);
                            outPlayedIds.insert(ht.id);
                            outHighlightedIds.insert(ht.id);
                            remHand.erase(remHand.begin() + hIdx);
                            tableActions++;
                            changed = true;
                            break;
                        }
                    }
                }
                if (changed) continue;

                // 2. Try splitting 1 tile from a 4-tile table group or 4+ tile table run to combine with 2 hand tiles!
                for (size_t mIdx = 0; mIdx < outNewMelds.size() && !changed; ++mIdx) {
                    const auto& mTiles = outNewMelds[mIdx].tiles;
                    if (mTiles.size() < 4) continue;
                    int candIndices[4] = {0, (int)mTiles.size() - 1, 1, (int)mTiles.size() - 2};
                    for (int ci = 0; ci < 4 && !changed; ++ci) {
                        int cIdx = candIndices[ci];
                        if (cIdx < 0 || cIdx >= (int)mTiles.size()) continue;
                        RmkTile spareTile = mTiles[cIdx];
                        std::vector<RmkTile> remainTable = mTiles;
                        remainTable.erase(remainTable.begin() + cIdx);
                        if (evaluateMeld(remainTable) < 0) continue;
                        if (remHand.size() >= 2) {
                            for (size_t i = 0; i + 1 < remHand.size() && !changed; ++i) {
                                for (size_t j = i + 1; j < remHand.size() && !changed; ++j) {
                                    std::vector<RmkTile> newTriad = {spareTile, remHand[i], remHand[j]};
                                    if (evaluateMeld(newTriad) >= 0) {
                                        std::string id1 = remHand[i].id;
                                        std::string id2 = remHand[j].id;
                                        outNewMelds[mIdx].tiles = sortMeldForDisplay(remainTable);
                                        auto sortedTriad = sortMeldForDisplay(newTriad);
                                        outNewMelds.push_back({"m_" + std::to_string(seedTick) + "_" + std::to_string(mSeq++), sortedTriad});
                                        outPlayedIds.insert(id1);
                                        outPlayedIds.insert(id2);
                                        outHighlightedIds.insert(spareTile.id);
                                        outHighlightedIds.insert(id1);
                                        outHighlightedIds.insert(id2);
                                        remHand.erase(std::remove_if(remHand.begin(), remHand.end(), [&](const RmkTile& t) {
                                            return t.id == id1 || t.id == id2;
                                        }), remHand.end());
                                        tableActions++;
                                        changed = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return !outPlayedIds.empty();
    }

}
