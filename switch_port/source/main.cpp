#include <switch.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>

#include <string>
#include <vector>
#include <map>
#include <ctime>
#include <cstdlib>
#include <algorithm>
#include <random>

#include "ws_client.hpp"
#include "game_logic.hpp"

// ============================================================================
// Constants & Theme Palette (1:1 K-ON! Ho-kago Game Room)
// ============================================================================
static const int SCREEN_W = 1280;
static const int SCREEN_H = 720;

static const SDL_Color COL_BG_DDZ    = {16, 75, 44, 255};
static const SDL_Color COL_BG_MJ     = {12, 60, 38, 255};
static const SDL_Color COL_PANEL     = {8, 36, 22, 220};
static const SDL_Color COL_GOLD      = {224, 173, 61, 255};
static const SDL_Color COL_CRIMSON   = {199, 46, 56, 255};
static const SDL_Color COL_GREEN_BTN = {46, 125, 50, 255};
static const SDL_Color COL_BLUE_BTN  = {25, 118, 210, 255};
static const SDL_Color COL_WHITE     = {255, 255, 255, 255};
static const SDL_Color COL_CREAM     = {252, 245, 230, 255};
static const SDL_Color COL_GRAY      = {150, 150, 150, 255};
static const SDL_Color COL_BLACK     = {20, 20, 20, 255};

// ============================================================================
// Global App State
// ============================================================================
enum AppScreenMode {
    MODE_LOBBY = 0,
    MODE_DDZ_TABLE = 1,
    MODE_MJ_TABLE = 2
};

static SDL_Window*   gWindow = nullptr;
static SDL_Renderer* gRenderer = nullptr;
static TTF_Font*     gFontSmall = nullptr;
static TTF_Font*     gFontMed = nullptr;
static TTF_Font*     gFontLarge = nullptr;
static TTF_Font*     gFontHuge = nullptr;

static std::map<std::string, SDL_Texture*> gTexCache;
static SwitchWsClient gWs;

static AppScreenMode gScreen = MODE_LOBBY;
static int gSelectedGame = 0; // 0 = 放课后斗地主(3P), 1 = 广东红中麻将(4P)
static int gMyCharId = 1;     // 1..5
static std::string gRoomCode = "888";
static std::string gMyPeerName = "Switch#101";
static std::string gStatusBanner = "🎮 欢迎来到 Switch 放课后棋牌室！按 [L/R] 切换斗地主/麻将，按 [Y] 输入房号，按 [X] 连接跨平台房间";

static bool gIsOnlineRoom = false;
static bool gIsRoomAuthority = true;
static std::vector<RoomPeer> gRoomPeers;

// Lobby focus index for D-Pad navigation
// 0..4: Character selection, 5: Room Code input, 6: Connect/Leave Server, 7: Start Game
static int gLobbyFocus = 7;

// ============================================================================
// Doudizhu Runtime State
// ============================================================================
static std::string gDdzPhase = "lobby"; // lobby, bidding, playing, roundOver
static std::vector<DdzSeat> gDdzSeats(3);
static std::vector<DdzCard> gDdzHoleCards;
static int gDdzMySeat = 0;
static int gDdzTurnSeat = 0;
static int gDdzHighestBid = 0;
static int gDdzHighestBidder = -1;
static int gDdzBidsCount = 0;
static int gDdzMultiplier = 1;
static int gDdzBaseScore = 100;
static int gDdzRound = 1;
static int gDdzWinnerSeat = -1;
static DdzEvalHand gDdzLastValid;
static int gDdzLastPlaySeat = -1;
static int gDdzCursor = 0;
static bool gDdzShowCounter = true;
static uint32_t gDdzDealStartTick = 0;
static uint32_t gDdzAiNextTick = 0;

// ============================================================================
// Mahjong Runtime State
// ============================================================================
static std::string gMjPhase = "lobby"; // lobby, playing, claimWindow, roundOver
static std::vector<MjSeat> gMjSeats(4);
static std::vector<MjTile> gMjWall;
static int gMjWallCount = 0;
static int gMjMySeat = 0;
static int gMjTurnSeat = 0;
static int gMjBaseScore = 100;
static int gMjRound = 1;
static int gMjWinnerSeat = -1;
static std::string gMjWinReason;
static std::string gMjDrawnTileId;
static int gMjCursor = 0;
static int gMjSelectedIdx = -1;
static bool gMjHasClaim = false;
static int gMjClaimFromSeat = -1;
static MjTile gMjClaimTile;
static bool gMjCanHu = false, gMjCanKong = false, gMjCanPong = false;
static uint32_t gMjDealStartTick = 0;
static uint32_t gMjAiNextTick = 0;

// ============================================================================
// Helper: Texture & Text Rendering
// ============================================================================
static SDL_Texture* getTexture(const std::string& path) {
    auto it = gTexCache.find(path);
    if (it != gTexCache.end()) return it->second;
    SDL_Surface* surf = IMG_Load(path.c_str());
    if (!surf) {
        gTexCache[path] = nullptr;
        return nullptr;
    }
    SDL_Texture* tex = SDL_CreateTextureFromSurface(gRenderer, surf);
    SDL_FreeSurface(surf);
    gTexCache[path] = tex;
    return tex;
}

static void drawRectFill(int x, int y, int w, int h, SDL_Color c) {
    SDL_SetRenderDrawBlendMode(gRenderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(gRenderer, c.r, c.g, c.b, c.a);
    SDL_Rect r = {x, y, w, h};
    SDL_RenderFillRect(gRenderer, &r);
}

static void drawRectOutline(int x, int y, int w, int h, SDL_Color c, int thickness = 2) {
    SDL_SetRenderDrawBlendMode(gRenderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(gRenderer, c.r, c.g, c.b, c.a);
    for (int i = 0; i < thickness; ++i) {
        SDL_Rect r = {x + i, y + i, w - i * 2, h - i * 2};
        SDL_RenderDrawRect(gRenderer, &r);
    }
}

static void drawText(TTF_Font* font, const std::string& text, int x, int y, SDL_Color col, bool center = false, bool rightAlign = false) {
    if (!font || text.empty()) return;
    SDL_Surface* surf = TTF_RenderUTF8_Blended(font, text.c_str(), col);
    if (!surf) return;
    SDL_Texture* tex = SDL_CreateTextureFromSurface(gRenderer, surf);
    if (tex) {
        SDL_Rect dst = {x, y, surf->w, surf->h};
        if (center) dst.x -= surf->w / 2;
        else if (rightAlign) dst.x -= surf->w;
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
        SDL_DestroyTexture(tex);
    }
    SDL_FreeSurface(surf);
}

// ============================================================================
// Switch System On-Screen Keyboard (Swkbd) for Room Code Input
// ============================================================================
static void openSwitchRoomCodeKeyboard() {
    SwkbdConfig kbd;
    Result rc = swkbdCreate(&kbd, 0);
    if (R_SUCCEEDED(rc)) {
        swkbdConfigMakePresetDefault(&kbd);
        swkbdConfigSetHeaderText(&kbd, "请输入放课后棋牌室房间号 (与 iOS / Android 相同)");
        swkbdConfigSetSubText(&kbd, "例如: 888 或 1015");
        swkbdConfigSetInitialText(&kbd, gRoomCode.c_str());
        swkbdConfigSetStringLenMax(&kbd, 12);
        char outBuf[32] = {0};
        if (R_SUCCEEDED(swkbdShow(&kbd, outBuf, sizeof(outBuf)))) {
            if (strlen(outBuf) > 0) {
                gRoomCode = outBuf;
                gStatusBanner = "✅ 已设置房间号: " + gRoomCode;
            }
        }
        swkbdClose(&kbd);
    }
}

// ============================================================================
// Cross-Platform WebSocket Sync (wss://azusa.online/ddz)
// ============================================================================
static std::string wireRoomCode() {
    return (gSelectedGame == 1) ? ("MJ_" + gRoomCode) : gRoomCode;
}

static void sendJoinRequestPacket() {
    if (!gWs.isConnected()) return;
    std::string kind = "joinRequest";
    std::string rc = wireRoomCode();
    std::string j = "{\"kind\":\"joinRequest\",\"roomCode\":\"" + MiniJson::esc(rc) +
                    "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                    "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                    (gSelectedGame == 1 ? ",\"maxPlayers\":4,\"gameType\":\"mahjong\"" : "") + "}";
    gWs.sendText(j);
}

static void broadcastDdzState() {
    if (!gIsOnlineRoom || !gIsRoomAuthority || !gWs.isConnected()) return;
    std::string peersArr = "[";
    for (size_t i = 0; i < gRoomPeers.size(); ++i) {
        if (i > 0) peersArr += ",";
        peersArr += "{\"name\":\"" + MiniJson::esc(gRoomPeers[i].name) + "\",\"charId\":" +
                    std::to_string(gRoomPeers[i].charId) + ",\"displayName\":\"" + MiniJson::esc(gRoomPeers[i].displayName) + "\"}";
    }
    peersArr += "]";

    std::string seatsArr = "[";
    for (size_t i = 0; i < gDdzSeats.size(); ++i) {
        if (i > 0) seatsArr += ",";
        seatsArr += gDdzSeats[i].toJson();
    }
    seatsArr += "]";

    std::string holeArr = "[";
    for (size_t i = 0; i < gDdzHoleCards.size(); ++i) {
        if (i > 0) holeArr += ",";
        holeArr += gDdzHoleCards[i].toJson();
    }
    holeArr += "]";

    std::string pkt = "{\"kind\":\"stateSync\",\"roomCode\":\"" + MiniJson::esc(gRoomCode) +
                      "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                      "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                      ",\"hostPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                      "\",\"roomPeers\":" + peersArr +
                      ",\"seats\":" + seatsArr +
                      ",\"holeCards\":" + holeArr +
                      ",\"phase\":\"" + gDdzPhase + "\"" +
                      ",\"currentTurnSeat\":" + std::to_string(gDdzTurnSeat) +
                      ",\"highestBid\":" + std::to_string(gDdzHighestBid) +
                      ",\"highestBidderSeat\":" + std::to_string(gDdzHighestBidder) +
                      ",\"multiplier\":" + std::to_string(gDdzMultiplier) +
                      ",\"lastPlaySeat\":" + std::to_string(gDdzLastPlaySeat) +
                      ",\"winnerSeat\":" + std::to_string(gDdzWinnerSeat) +
                      ",\"currentRound\":" + std::to_string(gDdzRound) +
                      ",\"baseScore\":" + std::to_string(gDdzBaseScore) +
                      ",\"statusBanner\":\"" + MiniJson::esc(gStatusBanner) + "\"" +
                      (gDdzLastValid.category != "invalid" ? (",\"lastValidHand\":" + gDdzLastValid.toJson()) : "") +
                      "}";
    gWs.sendText(pkt);
}

static void broadcastMjState() {
    if (!gIsOnlineRoom || !gIsRoomAuthority || !gWs.isConnected()) return;
    std::string peersArr = "[";
    for (size_t i = 0; i < gRoomPeers.size(); ++i) {
        if (i > 0) peersArr += ",";
        peersArr += "{\"name\":\"" + MiniJson::esc(gRoomPeers[i].name) + "\",\"charId\":" +
                    std::to_string(gRoomPeers[i].charId) + ",\"displayName\":\"" + MiniJson::esc(gRoomPeers[i].displayName) + "\"}";
    }
    peersArr += "]";

    std::string seatsArr = "[";
    for (size_t i = 0; i < gMjSeats.size(); ++i) {
        if (i > 0) seatsArr += ",";
        seatsArr += gMjSeats[i].toJson();
    }
    seatsArr += "]";

    std::string pkt = "{\"kind\":\"stateSync\",\"roomCode\":\"MJ_" + MiniJson::esc(gRoomCode) +
                      "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                      "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                      ",\"maxPlayers\":4,\"gameType\":\"mahjong\"" +
                      ",\"hostPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                      "\",\"roomPeers\":" + peersArr +
                      ",\"seats\":" + seatsArr +
                      ",\"wallCount\":" + std::to_string(gMjWallCount) +
                      ",\"phase\":\"" + gMjPhase + "\"" +
                      ",\"currentTurnSeat\":" + std::to_string(gMjTurnSeat) +
                      ",\"winnerSeat\":" + std::to_string(gMjWinnerSeat) +
                      ",\"winReason\":\"" + MiniJson::esc(gMjWinReason) + "\"" +
                      ",\"currentRound\":" + std::to_string(gMjRound) +
                      ",\"baseScore\":" + std::to_string(gMjBaseScore) +
                      ",\"statusBanner\":\"" + MiniJson::esc(gStatusBanner) + "\"}";
    gWs.sendText(pkt);
}

// ============================================================================
// Doudizhu Game Flow
// ============================================================================
static void rebuildLobbySeats() {
    if (gRoomPeers.empty()) {
        gRoomPeers.push_back({gMyPeerName, gMyCharId, gMyPeerName});
    } else {
        for (auto& rp : gRoomPeers) {
            if (rp.name == gMyPeerName) rp.charId = gMyCharId;
        }
    }
    gIsRoomAuthority = (gRoomPeers.front().name == gMyPeerName);

    // Doudizhu 3 seats
    std::set<int> usedChars;
    for (int i = 0; i < 3; ++i) {
        int prevScore = (i < (int)gDdzSeats.size()) ? gDdzSeats[i].score : 1000;
        if (i < (int)gRoomPeers.size()) {
            bool isMe = (gRoomPeers[i].name == gMyPeerName);
            if (isMe) gDdzMySeat = i;
            usedChars.insert(gRoomPeers[i].charId);
            std::string roleTag = (i == 0) ? "👑房主 " : ("#" + std::to_string(i + 1) + " ");
            gDdzSeats[i] = {i, roleTag + gRoomPeers[i].name + " (" + getCharacterName(gRoomPeers[i].charId) + ")",
                            gRoomPeers[i].charId, false, gRoomPeers[i].name, {}, false, "", {}, prevScore};
        } else {
            int aiChar = 1;
            for (int c = 1; c <= 5; ++c) if (!usedChars.count(c)) { aiChar = c; usedChars.insert(c); break; }
            gDdzSeats[i] = {i, getCharacterName(aiChar) + " (AI)", aiChar, true, "AI_" + std::to_string(i), {}, false, "", {}, prevScore};
        }
    }

    // Mahjong 4 seats
    usedChars.clear();
    for (int i = 0; i < 4; ++i) {
        int prevScore = (i < (int)gMjSeats.size()) ? gMjSeats[i].score : 1000;
        if (i < (int)gRoomPeers.size()) {
            bool isMe = (gRoomPeers[i].name == gMyPeerName);
            if (isMe) gMjMySeat = i;
            usedChars.insert(gRoomPeers[i].charId);
            std::string roleTag = (i == 0) ? "👑房主 " : ("#" + std::to_string(i + 1) + " ");
            gMjSeats[i] = {i, roleTag + gRoomPeers[i].name, gRoomPeers[i].charId, false, gRoomPeers[i].name, {}, {}, {}, prevScore, (i == 0), ""};
        } else {
            int aiChar = 1;
            for (int c = 1; c <= 5; ++c) if (!usedChars.count(c)) { aiChar = c; usedChars.insert(c); break; }
            gMjSeats[i] = {i, getCharacterName(aiChar) + " (AI)", aiChar, true, "AI_" + std::to_string(i), {}, {}, {}, prevScore, (i == 0), ""};
        }
    }
}

static void startNewDoudizhuRound() {
    if (gIsOnlineRoom && !gIsRoomAuthority) return;
    rebuildLobbySeats();

    std::vector<DdzCard> deck;
    const char* suits[] = {"♠", "♥", "♣", "♦"};
    for (int r = 3; r <= 15; ++r) {
        for (int s = 0; s < 4; ++s) {
            deck.push_back({std::string(suits[s]) + "_" + std::to_string(r), r, suits[s], false});
        }
    }
    deck.push_back({"joker_16", 16, "🃏", false});
    deck.push_back({"joker_17", 17, "🃏", false});

    std::mt19937 rng((unsigned int)time(nullptr) ^ SDL_GetTicks());
    std::shuffle(deck.begin(), deck.end(), rng);

    for (int i = 0; i < 3; ++i) {
        gDdzSeats[i].hand.assign(deck.begin() + i * 17, deck.begin() + (i + 1) * 17);
        std::sort(gDdzSeats[i].hand.begin(), gDdzSeats[i].hand.end(), [](const DdzCard& a, const DdzCard& b) {
            return a.rank > b.rank;
        });
        gDdzSeats[i].isLandlord = false;
        gDdzSeats[i].lastActionText = "";
        gDdzSeats[i].lastPlayedCards.clear();
    }
    gDdzHoleCards.assign(deck.begin() + 51, deck.end());

    gDdzPhase = "bidding";
    gDdzTurnSeat = rand() % 3; // Random first bidder
    gDdzHighestBid = 0;
    gDdzHighestBidder = -1;
    gDdzBidsCount = 0;
    gDdzMultiplier = 1;
    gDdzWinnerSeat = -1;
    gDdzLastValid = DdzEvalHand();
    gDdzLastPlaySeat = -1;
    gDdzCursor = 0;
    gDdzDealStartTick = SDL_GetTicks();
    gDdzAiNextTick = SDL_GetTicks() + 1100;
    gScreen = MODE_DDZ_TABLE;
    gStatusBanner = "🃏 发牌完成！轮到 [" + gDdzSeats[gDdzTurnSeat].name + "] 叫地主";
    broadcastDdzState();
}

static void finalizeDdzLandlord(int landlordIdx) {
    for (int i = 0; i < 3; ++i) {
        gDdzSeats[i].isLandlord = (i == landlordIdx);
        gDdzSeats[i].lastActionText = (i == landlordIdx) ? "🎩 地主" : "🌾 农民";
    }
    for (const auto& hc : gDdzHoleCards) gDdzSeats[landlordIdx].hand.push_back(hc);
    std::sort(gDdzSeats[landlordIdx].hand.begin(), gDdzSeats[landlordIdx].hand.end(), [](const DdzCard& a, const DdzCard& b) {
        return a.rank > b.rank;
    });
    gDdzPhase = "playing";
    gDdzTurnSeat = landlordIdx;
    gDdzLastPlaySeat = landlordIdx;
    gDdzLastValid = DdzEvalHand();
    gDdzAiNextTick = SDL_GetTicks() + 1000;
    gStatusBanner = "🎩 [" + gDdzSeats[landlordIdx].name + "] 成为地主！获得三张底牌并优先出牌";
    broadcastDdzState();
}

static void handleDdzBid(int seatIdx, int score) {
    if (gDdzPhase != "bidding" || seatIdx != gDdzTurnSeat) return;
    if (gIsOnlineRoom && !gIsRoomAuthority && seatIdx == gDdzMySeat) {
        std::string pkt = "{\"kind\":\"bidAction\",\"roomCode\":\"" + MiniJson::esc(gRoomCode) +
                          "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                          "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                          ",\"bidScore\":" + std::to_string(score) + "}";
        gWs.sendText(pkt);
        return;
    }
    if (score > gDdzHighestBid) {
        gDdzHighestBid = score;
        gDdzHighestBidder = seatIdx;
        gDdzMultiplier = score;
        gDdzSeats[seatIdx].lastActionText = "叫 " + std::to_string(score) + " 分";
    } else {
        gDdzSeats[seatIdx].lastActionText = "不叫";
    }
    gDdzBidsCount++;
    if (gDdzHighestBid == 3 || gDdzBidsCount >= 3) {
        int landlord = (gDdzHighestBidder >= 0) ? gDdzHighestBidder : (rand() % 3);
        if (gDdzHighestBid == 0) gDdzMultiplier = 1;
        finalizeDdzLandlord(landlord);
    } else {
        gDdzTurnSeat = (gDdzTurnSeat + 1) % 3;
        gDdzAiNextTick = SDL_GetTicks() + 950;
        gStatusBanner = "📢 轮到 [" + gDdzSeats[gDdzTurnSeat].name + "] 叫分 (当前最高: " + std::to_string(gDdzHighestBid) + "分)";
        broadcastDdzState();
    }
}

static void executeDdzPlay(int seatIdx, const DdzEvalHand& eval) {
    for (const auto& pc : eval.cards) {
        auto& h = gDdzSeats[seatIdx].hand;
        h.erase(std::remove_if(h.begin(), h.end(), [&](const DdzCard& c) { return c.id == pc.id; }), h.end());
    }
    for (auto& c : gDdzSeats[seatIdx].hand) c.selected = false;
    gDdzSeats[seatIdx].lastPlayedCards = eval.cards;
    gDdzSeats[seatIdx].lastActionText = eval.labelZh();
    if (eval.category == "bomb" || eval.category == "rocket") gDdzMultiplier *= 2;
    gDdzLastValid = eval;
    gDdzLastPlaySeat = seatIdx;
    if (gDdzCursor >= (int)gDdzSeats[gDdzMySeat].hand.size()) {
        gDdzCursor = std::max(0, (int)gDdzSeats[gDdzMySeat].hand.size() - 1);
    }

    if (gDdzSeats[seatIdx].hand.empty()) {
        gDdzWinnerSeat = seatIdx;
        gDdzPhase = "roundOver";
        bool landlordWon = gDdzSeats[seatIdx].isLandlord;
        int delta = gDdzBaseScore * gDdzMultiplier;
        for (int i = 0; i < 3; ++i) {
            if (gDdzSeats[i].isLandlord) gDdzSeats[i].score += landlordWon ? (delta * 2) : (-delta * 2);
            else gDdzSeats[i].score += landlordWon ? (-delta) : delta;
        }
        gStatusBanner = "🎉 [" + gDdzSeats[seatIdx].name + "] 获胜！按 [A] 再来一局，按 [-] 退出房间";
        broadcastDdzState();
        return;
    }

    gDdzTurnSeat = (seatIdx + 1) % 3;
    gDdzSeats[gDdzTurnSeat].lastPlayedCards.clear();
    gDdzSeats[gDdzTurnSeat].lastActionText = "";
    gDdzAiNextTick = SDL_GetTicks() + 950;
    gStatusBanner = "🃏 [" + gDdzSeats[seatIdx].name + "] 打出 " + eval.labelZh() + "，轮到 [" + gDdzSeats[gDdzTurnSeat].name + "]";
    broadcastDdzState();
}

static void handleDdzPass(int seatIdx) {
    if (gDdzPhase != "playing" || seatIdx != gDdzTurnSeat) return;
    if (gDdzLastPlaySeat == seatIdx || gDdzLastPlaySeat == -1) {
        gStatusBanner = "⚠️ 当前由您首发控牌，不能选择不出！";
        return;
    }
    if (gIsOnlineRoom && !gIsRoomAuthority && seatIdx == gDdzMySeat) {
        std::string pkt = "{\"kind\":\"passAction\",\"roomCode\":\"" + MiniJson::esc(gRoomCode) +
                          "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                          "\",\"senderCharId\":" + std::to_string(gMyCharId) + "}";
        gWs.sendText(pkt);
        return;
    }
    gDdzSeats[seatIdx].lastPlayedCards.clear();
    gDdzSeats[seatIdx].lastActionText = "不出";
    gDdzTurnSeat = (seatIdx + 1) % 3;
    if (gDdzTurnSeat == gDdzLastPlaySeat) {
        for (int i = 0; i < 3; ++i) {
            gDdzSeats[i].lastPlayedCards.clear();
            gDdzSeats[i].lastActionText = "";
        }
    } else {
        gDdzSeats[gDdzTurnSeat].lastPlayedCards.clear();
        gDdzSeats[gDdzTurnSeat].lastActionText = "";
    }
    gDdzAiNextTick = SDL_GetTicks() + 950;
    gStatusBanner = "⏭ [" + gDdzSeats[seatIdx].name + "] 不出，轮到 [" + gDdzSeats[gDdzTurnSeat].name + "]";
    broadcastDdzState();
}

static void selectDdzHintForMe() {
    auto& myHand = gDdzSeats[gDdzMySeat].hand;
    for (auto& c : myHand) c.selected = false;
    bool freeLead = (gDdzLastPlaySeat == gDdzMySeat || gDdzLastPlaySeat == -1);
    if (freeLead) {
        if (!myHand.empty()) myHand.back().selected = true;
        return;
    }
    // Search single/pair/triple/bomb that beats gDdzLastValid
    if (gDdzLastValid.category == "single") {
        for (int i = (int)myHand.size() - 1; i >= 0; --i) {
            if (myHand[i].rank > gDdzLastValid.primaryRank) {
                myHand[i].selected = true;
                return;
            }
        }
    } else if (gDdzLastValid.category == "pair") {
        for (int i = (int)myHand.size() - 1; i >= 1; --i) {
            if (myHand[i].rank == myHand[i - 1].rank && myHand[i].rank > gDdzLastValid.primaryRank) {
                myHand[i].selected = true;
                myHand[i - 1].selected = true;
                return;
            }
        }
    } else if (gDdzLastValid.category == "triple") {
        for (int i = (int)myHand.size() - 1; i >= 2; --i) {
            if (myHand[i].rank == myHand[i - 2].rank && myHand[i].rank > gDdzLastValid.primaryRank) {
                myHand[i].selected = myHand[i - 1].selected = myHand[i - 2].selected = true;
                return;
            }
        }
    }
    // Check Bomb
    for (int i = (int)myHand.size() - 1; i >= 3; --i) {
        if (myHand[i].rank == myHand[i - 3].rank) {
            if (gDdzLastValid.category != "bomb" || myHand[i].rank > gDdzLastValid.primaryRank) {
                myHand[i].selected = myHand[i - 1].selected = myHand[i - 2].selected = myHand[i - 3].selected = true;
                return;
            }
        }
    }
    gStatusBanner = "💡 没有能大过上家的牌，请按 [B] 不出";
}

// ============================================================================
// Mahjong Game Flow (136-Tile Guangdong Hongzhong Laizi)
// ============================================================================
static void startNewMahjongRound() {
    if (gIsOnlineRoom && !gIsRoomAuthority) return;
    rebuildLobbySeats();

    gMjWall.clear();
    const char* suits[] = {"W", "T", "D"};
    for (int s = 0; s < 3; ++s) {
        for (int r = 1; r <= 9; ++r) {
            for (int c = 0; c < 4; ++c) {
                gMjWall.push_back({std::string(suits[s]) + "_" + std::to_string(r) + "_" + std::to_string(c), suits[s], r});
            }
        }
    }
    for (int r = 1; r <= 6; ++r) {
        for (int c = 0; c < 4; ++c) {
            gMjWall.push_back({"H_" + std::to_string(r) + "_" + std::to_string(c), "H", r});
        }
    }
    for (int c = 0; c < 4; ++c) {
        gMjWall.push_back({"Z_0_" + std::to_string(c), "Z", 0});
    }

    std::mt19937 rng((unsigned int)time(nullptr) ^ SDL_GetTicks());
    std::shuffle(gMjWall.begin(), gMjWall.end(), rng);

    int dealer = (gMjRound - 1) % 4;
    for (int i = 0; i < 4; ++i) {
        gMjSeats[i].hand.clear();
        gMjSeats[i].melds.clear();
        gMjSeats[i].discards.clear();
        gMjSeats[i].isDealer = (i == dealer);
        gMjSeats[i].lastActionText = "";
        for (int k = 0; k < 13; ++k) {
            gMjSeats[i].hand.push_back(gMjWall.back());
            gMjWall.pop_back();
        }
        MjEvaluator::sortHand(gMjSeats[i].hand);
    }
    // Dealer draws 14th tile
    MjTile drawn = gMjWall.back();
    gMjWall.pop_back();
    gMjSeats[dealer].hand.push_back(drawn);
    gMjDrawnTileId = drawn.id;
    gMjWallCount = (int)gMjWall.size();

    gMjPhase = "playing";
    gMjTurnSeat = dealer;
    gMjWinnerSeat = -1;
    gMjWinReason = "";
    gMjHasClaim = false;
    gMjCursor = 0;
    gMjSelectedIdx = -1;
    gMjDealStartTick = SDL_GetTicks();
    gMjAiNextTick = SDL_GetTicks() + 1100;
    gScreen = MODE_MJ_TABLE;
    gStatusBanner = "🀄 广东红中麻将开局！庄家 [" + gMjSeats[dealer].name + "] 先出牌";
    broadcastMjState();
}

static void executeMjWin(int winner, int loser, const std::string& reason) {
    gMjWinnerSeat = winner;
    gMjWinReason = reason;
    gMjPhase = "roundOver";
    gMjHasClaim = false;
    int delta = gMjBaseScore * 2;
    if (loser < 0) {
        for (int i = 0; i < 4; ++i) {
            if (i == winner) gMjSeats[i].score += delta * 3;
            else gMjSeats[i].score -= delta;
        }
    } else {
        gMjSeats[winner].score += delta * 2;
        gMjSeats[loser].score -= delta * 2;
    }
    gStatusBanner = "🎉 [" + gMjSeats[winner].name + "] " + reason + "！按 [A] 再来一局";
    broadcastMjState();
}

static void drawMjTileForSeat(int seatIdx) {
    if (gMjWall.empty()) {
        gMjPhase = "roundOver";
        gMjWinnerSeat = -1;
        gMjWinReason = "荒庄流局";
        gStatusBanner = "🌊 牌山摸空，本局荒庄流局！按 [A] 再来一局";
        broadcastMjState();
        return;
    }
    MjTile t = gMjWall.back();
    gMjWall.pop_back();
    gMjWallCount = (int)gMjWall.size();
    gMjSeats[seatIdx].hand.push_back(t);
    gMjDrawnTileId = t.id;
    gMjTurnSeat = seatIdx;
    gMjPhase = "playing";
    gMjHasClaim = false;
    gMjAiNextTick = SDL_GetTicks() + 950;
    gStatusBanner = "🀄 轮到 [" + gMjSeats[seatIdx].name + "] 摸牌出牌 (余 " + std::to_string(gMjWallCount) + " 张)";
    broadcastMjState();
}

static void executeMjDiscard(int seatIdx, const std::string& tileId) {
    auto& hand = gMjSeats[seatIdx].hand;
    auto it = std::find_if(hand.begin(), hand.end(), [&](const MjTile& t) { return t.id == tileId; });
    if (it == hand.end() && !hand.empty()) it = hand.end() - 1;
    if (it == hand.end()) return;
    MjTile discarded = *it;
    hand.erase(it);
    MjEvaluator::sortHand(hand);
    gMjSeats[seatIdx].discards.push_back(discarded);
    gMjSeats[seatIdx].lastActionText = "打出 " + discarded.fullName();
    gMjSelectedIdx = -1;
    if (gMjCursor >= (int)gMjSeats[gMjMySeat].hand.size()) {
        gMjCursor = std::max(0, (int)gMjSeats[gMjMySeat].hand.size() - 1);
    }

    // Check if human player (gMjMySeat) can Hu/Kong/Pong on this discard (if not discarded by me and not Laizi)
    if (seatIdx != gMjMySeat && !discarded.isLaizi()) {
        auto myCopy = gMjSeats[gMjMySeat].hand;
        myCopy.push_back(discarded);
        gMjCanHu = MjEvaluator::canHu(myCopy, (int)gMjSeats[gMjMySeat].melds.size());
        int sameCnt = 0;
        for (const auto& mt : gMjSeats[gMjMySeat].hand) {
            if (mt.suit == discarded.suit && mt.rank == discarded.rank) sameCnt++;
        }
        gMjCanKong = (sameCnt >= 3);
        gMjCanPong = (sameCnt >= 2);
        if (gMjCanHu || gMjCanKong || gMjCanPong) {
            gMjPhase = "claimWindow";
            gMjHasClaim = true;
            gMjClaimFromSeat = seatIdx;
            gMjClaimTile = discarded;
            gStatusBanner = "⚡ 响应 [" + discarded.fullName() + "]：按 [X]胡 / [Y]碰杠 / [B]过";
            broadcastMjState();
            return;
        }
    }

    // Check AI claims
    if (!discarded.isLaizi()) {
        for (int step = 1; step <= 3; ++step) {
            int idx = (seatIdx + step) % 4;
            if (!gMjSeats[idx].isAI) continue;
            auto copy = gMjSeats[idx].hand;
            copy.push_back(discarded);
            if (MjEvaluator::canHu(copy, (int)gMjSeats[idx].melds.size())) {
                executeMjWin(idx, seatIdx, "点炮胡 (" + discarded.fullName() + ")");
                return;
            }
        }
        for (int step = 1; step <= 3; ++step) {
            int idx = (seatIdx + step) % 4;
            if (!gMjSeats[idx].isAI) continue;
            int sameCnt = 0;
            for (const auto& mt : gMjSeats[idx].hand) if (mt.suit == discarded.suit && mt.rank == discarded.rank) sameCnt++;
            if (sameCnt >= 2) {
                gMjSeats[seatIdx].discards.pop_back();
                int rem = 0;
                auto& ah = gMjSeats[idx].hand;
                for (auto ait = ah.begin(); ait != ah.end() && rem < 2;) {
                    if (ait->suit == discarded.suit && ait->rank == discarded.rank) { ait = ah.erase(ait); rem++; }
                    else ++ait;
                }
                gMjSeats[idx].melds.push_back({discarded.id, "碰", discarded});
                gMjSeats[idx].lastActionText = "碰 " + discarded.fullName();
                gMjTurnSeat = idx;
                gMjAiNextTick = SDL_GetTicks() + 900;
                broadcastMjState();
                return;
            }
        }
    }

    drawMjTileForSeat((seatIdx + 1) % 4);
}

// ============================================================================
// Network Message Polling (Handles iOS & Android Packets)
// ============================================================================
static void processIncomingNetworkMessages() {
    auto msgs = gWs.pollMessages();
    for (const auto& raw : msgs) {
        std::string kind = MiniJson::getStr(raw, "kind");
        std::string rc = MiniJson::getStr(raw, "roomCode");
        std::string sender = MiniJson::getStr(raw, "senderPeerName");
        int senderChar = MiniJson::getInt(raw, "senderCharId", 1);
        if (sender == gMyPeerName) continue;

        bool isMjPkt = (rc.rfind("MJ_", 0) == 0);
        std::string cleanRc = isMjPkt ? rc.substr(3) : rc;
        if (cleanRc != gRoomCode) continue;

        if (kind == "joinRequest") {
            if (gIsRoomAuthority) {
                int maxP = isMjPkt ? 4 : 3;
                bool exists = false;
                for (auto& rp : gRoomPeers) if (rp.name == sender) { rp.charId = senderChar; exists = true; }
                if (!exists && (int)gRoomPeers.size() < maxP) {
                    gRoomPeers.push_back({sender, senderChar, sender});
                }
                rebuildLobbySeats();
                gStatusBanner = "🎉 跨平台玩家 [" + sender + "] 已加入房间 " + gRoomCode + "！";
                if (gSelectedGame == 0) broadcastDdzState();
                else broadcastMjState();
            }
        } else if (kind == "leaveRoom") {
            gRoomPeers.erase(std::remove_if(gRoomPeers.begin(), gRoomPeers.end(), [&](const RoomPeer& p) {
                return p.name == sender;
            }), gRoomPeers.end());
            rebuildLobbySeats();
            gStatusBanner = "👋 玩家 [" + sender + "] 已离开房间";
        } else if (kind == "bidAction" && gIsRoomAuthority && !isMjPkt) {
            int bid = MiniJson::getInt(raw, "bidScore", 0);
            handleDdzBid(gDdzTurnSeat, bid);
        } else if (kind == "passAction" && gIsRoomAuthority && !isMjPkt) {
            handleDdzPass(gDdzTurnSeat);
        } else if (kind == "playCardsAction" && gIsRoomAuthority && !isMjPkt) {
            auto cardObjs = MiniJson::extractObjectsArray(raw, "playedCards");
            std::vector<DdzCard> played;
            for (const auto& co : cardObjs) played.push_back(DdzCard::fromJson(co));
            DdzEvalHand ev = DdzEvaluator::evaluate(played);
            if (ev.category != "invalid") executeDdzPlay(gDdzTurnSeat, ev);
        } else if (kind == "discardAction" && gIsRoomAuthority && isMjPkt) {
            std::string tid = MiniJson::getStr(raw, "tileId");
            executeMjDiscard(gMjTurnSeat, tid);
        } else if (kind == "stateSync") {
            std::string hostName = MiniJson::getStr(raw, "hostPeerName");
            gIsRoomAuthority = (hostName == gMyPeerName);
            std::string banner = MiniJson::getStr(raw, "statusBanner");
            if (!banner.empty()) gStatusBanner = banner;

            if (!isMjPkt) {
                gDdzPhase = MiniJson::getStr(raw, "phase", gDdzPhase);
                gDdzTurnSeat = MiniJson::getInt(raw, "currentTurnSeat", gDdzTurnSeat);
                gDdzHighestBid = MiniJson::getInt(raw, "highestBid", gDdzHighestBid);
                gDdzMultiplier = MiniJson::getInt(raw, "multiplier", gDdzMultiplier);
                gDdzLastPlaySeat = MiniJson::getInt(raw, "lastPlaySeat", gDdzLastPlaySeat);
                gDdzWinnerSeat = MiniJson::getInt(raw, "winnerSeat", gDdzWinnerSeat);

                auto hcObjs = MiniJson::extractObjectsArray(raw, "holeCards");
                if (!hcObjs.empty()) {
                    gDdzHoleCards.clear();
                    for (const auto& ho : hcObjs) gDdzHoleCards.push_back(DdzCard::fromJson(ho));
                }
                auto seatObjs = MiniJson::extractObjectsArray(raw, "seats");
                if (seatObjs.size() == 3) {
                    for (int i = 0; i < 3; ++i) {
                        gDdzSeats[i].name = MiniJson::getStr(seatObjs[i], "name", gDdzSeats[i].name);
                        gDdzSeats[i].characterId = MiniJson::getInt(seatObjs[i], "characterId", 1);
                        gDdzSeats[i].isAI = MiniJson::getBool(seatObjs[i], "isAI", false);
                        gDdzSeats[i].peerDisplayName = MiniJson::getStr(seatObjs[i], "peerDisplayName");
                        gDdzSeats[i].isLandlord = MiniJson::getBool(seatObjs[i], "isLandlord", false);
                        gDdzSeats[i].lastActionText = MiniJson::getStr(seatObjs[i], "lastActionText");
                        gDdzSeats[i].score = MiniJson::getInt(seatObjs[i], "score", 1000);
                        if (gDdzSeats[i].peerDisplayName == gMyPeerName) gDdzMySeat = i;

                        auto hObjs = MiniJson::extractObjectsArray(seatObjs[i], "hand");
                        gDdzSeats[i].hand.clear();
                        for (const auto& co : hObjs) gDdzSeats[i].hand.push_back(DdzCard::fromJson(co));

                        auto lpObjs = MiniJson::extractObjectsArray(seatObjs[i], "lastPlayedCards");
                        gDdzSeats[i].lastPlayedCards.clear();
                        for (const auto& co : lpObjs) gDdzSeats[i].lastPlayedCards.push_back(DdzCard::fromJson(co));
                    }
                }
                if (gDdzPhase != "lobby") gScreen = MODE_DDZ_TABLE;
            } else {
                gMjPhase = MiniJson::getStr(raw, "phase", gMjPhase);
                gMjTurnSeat = MiniJson::getInt(raw, "currentTurnSeat", gMjTurnSeat);
                gMjWallCount = MiniJson::getInt(raw, "wallCount", gMjWallCount);
                gMjWinnerSeat = MiniJson::getInt(raw, "winnerSeat", gMjWinnerSeat);
                gMjWinReason = MiniJson::getStr(raw, "winReason", gMjWinReason);

                auto seatObjs = MiniJson::extractObjectsArray(raw, "seats");
                if (seatObjs.size() == 4) {
                    for (int i = 0; i < 4; ++i) {
                        gMjSeats[i].name = MiniJson::getStr(seatObjs[i], "name", gMjSeats[i].name);
                        gMjSeats[i].characterId = MiniJson::getInt(seatObjs[i], "characterId", 1);
                        gMjSeats[i].isAI = MiniJson::getBool(seatObjs[i], "isAI", false);
                        gMjSeats[i].peerDisplayName = MiniJson::getStr(seatObjs[i], "peerDisplayName");
                        gMjSeats[i].score = MiniJson::getInt(seatObjs[i], "score", 1000);
                        gMjSeats[i].isDealer = MiniJson::getBool(seatObjs[i], "isDealer", false);
                        gMjSeats[i].lastActionText = MiniJson::getStr(seatObjs[i], "lastActionText");
                        if (gMjSeats[i].peerDisplayName == gMyPeerName) gMjMySeat = i;

                        auto hObjs = MiniJson::extractObjectsArray(seatObjs[i], "hand");
                        gMjSeats[i].hand.clear();
                        for (const auto& to : hObjs) gMjSeats[i].hand.push_back(MjTile::fromJson(to));

                        auto dObjs = MiniJson::extractObjectsArray(seatObjs[i], "discards");
                        gMjSeats[i].discards.clear();
                        for (const auto& to : dObjs) gMjSeats[i].discards.push_back(MjTile::fromJson(to));
                    }
                }
                if (gMjPhase != "lobby") gScreen = MODE_MJ_TABLE;
            }
        }
    }
}

// ============================================================================
// Rendering Helpers for Cards & Tiles (Same Visual Style as iOS/Android v1.9.4)
// ============================================================================
static void drawPokerCard(const DdzCard& c, int x, int y, int w, int h, bool isCursor, bool isSelected) {
    int drawY = y - (isSelected ? 18 : 0);
    drawRectFill(x, drawY, w, h, COL_WHITE);

    // Top White Header Strip (Rank + Suit never cover K-ON! character face!)
    int headerH = std::max(18, h / 5);
    SDL_Color idxCol = c.isRed() ? SDL_Color{215, 25, 35, 255} : COL_BLACK;
    std::string badge = c.rankLabel() + (c.rank < 16 ? c.suit : "");
    drawText(gFontSmall, badge, x + 5, drawY + 2, idxCol);

    // Character Illustration below header
    SDL_Texture* tex = getTexture(c.romfsImagePath());
    if (tex) {
        SDL_Rect dst = {x + 2, drawY + headerH, w - 4, h - headerH - 2};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    }

    if (isCursor) {
        drawRectOutline(x - 2, drawY - 2, w + 4, h + 4, COL_GOLD, 3);
        drawText(gFontSmall, "▲", x + w / 2, drawY + h + 2, COL_GOLD, true);
    } else if (isSelected) {
        drawRectOutline(x, drawY, w, h, COL_CRIMSON, 2);
    } else {
        drawRectOutline(x, drawY, w, h, {210, 210, 210, 255}, 1);
    }
}

static void drawPokerBack(int x, int y, int w, int h) {
    drawRectFill(x, y, w, h, COL_WHITE);
    SDL_Texture* tex = getTexture("romfs:/cards/back.jpg");
    if (tex) {
        SDL_Rect dst = {x + 1, y + 1, w - 2, h - 2};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    }
    drawRectOutline(x, y, w, h, COL_GOLD, 1);
}

static void drawMahjongTile(const MjTile& t, int x, int y, int w, int h, bool isCursor, bool isSelected, bool isHighlight) {
    int drawY = y - (isSelected ? 16 : 0);
    // 3D Ivory Tile Base
    drawRectFill(x, drawY, w, h, {250, 247, 237, 255});
    SDL_Texture* tex = getTexture(t.romfsImagePath());
    if (tex) {
        SDL_Rect dst = {x + 2, drawY + 2, w - 4, h - 4};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    } else {
        drawText(gFontSmall, t.fullName(), x + w / 2, drawY + h / 3, COL_BLACK, true);
    }
    if (t.isLaizi()) {
        drawRectFill(x + w - 16, drawY + 1, 15, 14, COL_GOLD);
        drawText(gFontSmall, "赖", x + w - 8, drawY, COL_BLACK, true);
    }
    if (isCursor) {
        drawRectOutline(x - 2, drawY - 2, w + 4, h + 4, COL_GOLD, 3);
        drawText(gFontSmall, "▲", x + w / 2, drawY + h + 2, COL_GOLD, true);
    } else if (isHighlight) {
        drawRectOutline(x, drawY, w, h, {0, 230, 118, 255}, 2);
    } else {
        drawRectOutline(x, drawY, w, h, {180, 165, 140, 255}, 1);
    }
}

static void drawMahjongBack(int x, int y, int w, int h) {
    drawRectFill(x, y, w, h, {230, 238, 232, 255});
    drawRectFill(x + 1, y + 1, w - 2, std::max(4, h - 4), {20, 145, 85, 255});
    drawRectOutline(x, y, w, h, {255, 255, 255, 180}, 1);
}

// ============================================================================
// Render Screens
// ============================================================================
static void renderTopBar() {
    drawRectFill(0, 0, SCREEN_W, 52, {6, 28, 17, 240});
    if (gScreen != MODE_LOBBY) {
        drawRectFill(16, 10, 145, 32, COL_PANEL);
        drawRectOutline(16, 10, 145, 32, COL_GOLD, 1);
        drawText(gFontSmall, "[-] < 退出房间", 88, 16, COL_GOLD, true);
    }
    drawText(gFontLarge, "放课后茶会 · 放课后棋牌室 (Switch 跨平台联机版)", SCREEN_W / 2, 12, COL_WHITE, true);
    if (gScreen == MODE_LOBBY) {
        drawRectFill(SCREEN_W - 140, 10, 124, 32, COL_PANEL);
        drawRectOutline(SCREEN_W - 140, 10, 124, 32, COL_GOLD, 1);
        drawText(gFontSmall, "[+] 退出软件", SCREEN_W - 78, 16, COL_GOLD, true);
    }
}

static void renderLobbyScreen() {
    bool inJoinedRoom = gIsOnlineRoom && gWs.isConnected();
    // Game Switcher Bar (Hidden once user connects to a room, matching v1.8.7 requirement!)
    if (!inJoinedRoom) {
        drawRectFill(40, 64, 590, 44, gSelectedGame == 0 ? COL_CRIMSON : COL_PANEL);
        drawRectOutline(40, 64, 590, 44, COL_GOLD, gSelectedGame == 0 ? 2 : 1);
        drawText(gFontMed, "[L] 放课后斗地主 (3人)", 335, 74, COL_WHITE, true);

        drawRectFill(650, 64, 590, 44, gSelectedGame == 1 ? COL_GREEN_BTN : COL_PANEL);
        drawRectOutline(650, 64, 590, 44, COL_GOLD, gSelectedGame == 1 ? 2 : 1);
        drawText(gFontMed, "[R] 广东红中麻将 (4人 · 136张)", 945, 74, COL_WHITE, true);
    }

    // Status Banner
    drawRectFill(40, 118, 1200, 36, COL_PANEL);
    drawRectOutline(40, 118, 1200, 36, COL_GOLD, 1);
    drawText(gFontSmall, gStatusBanner, 56, 126, COL_GOLD);

    // 1. Character Selector
    drawRectFill(40, 166, 1200, 125, COL_PANEL);
    drawText(gFontMed, "1. 选择轻音部角色 (方向键左右 + [A] 确认)    本机标识: " + gMyPeerName, 58, 174, COL_GOLD);
    for (int i = 0; i < 5; ++i) {
        int bx = 58 + i * 232;
        int by = 208;
        bool isSel = (gMyCharId == kCharacters[i].charId);
        bool isFoc = (gLobbyFocus == i);
        drawRectFill(bx, by, 216, 68, isSel ? COL_CRIMSON : SDL_Color{15, 52, 34, 255});
        drawRectOutline(bx, by, 216, 68, isFoc ? COL_WHITE : COL_GOLD, isFoc ? 3 : (isSel ? 2 : 1));
        drawText(gFontMed, kCharacters[i].nameZh, bx + 108, by + 22, COL_WHITE, true);
    }

    // 2. Cross-Platform Online Server Card (wss://azusa.online/ddz)
    drawRectFill(40, 304, 1200, 120, COL_PANEL);
    drawText(gFontMed, "2. 跨平台在线服务器联机 (Switch / iOS / Android 互通 · wss://azusa.online/ddz)", 58, 314, COL_GOLD);

    // Room Code Box
    drawRectFill(58, 352, 360, 54, {15, 52, 34, 255});
    drawRectOutline(58, 352, 360, 54, gLobbyFocus == 5 ? COL_WHITE : COL_GOLD, gLobbyFocus == 5 ? 3 : 1);
    drawText(gFontMed, "[Y] 房间号: " + gRoomCode, 238, 366, COL_WHITE, true);

    // Connect / Disconnect Button
    bool wsConn = gWs.isConnected();
    drawRectFill(440, 352, 380, 54, wsConn ? COL_BLUE_BTN : COL_GREEN_BTN);
    drawRectOutline(440, 352, 380, 54, gLobbyFocus == 6 ? COL_WHITE : COL_GOLD, gLobbyFocus == 6 ? 3 : 1);
    drawText(gFontMed, wsConn ? ("[X] 已连(" + gRoomCode + ") · 按[X]退出房间") : "[X] 连接跨平台联机房间", 630, 366, COL_WHITE, true);

    drawText(gFontSmall, "提示: 手机与 Switch 输入相同房间号即可同桌对局，不足人数由轻音 AI 自动补位", 840, 368, COL_CREAM);

    // 3. Seat Preview
    drawRectFill(40, 436, 1200, 156, COL_PANEL);
    int seatCnt = (gSelectedGame == 0) ? 3 : 4;
    drawText(gFontMed, std::string("3. 牌桌座位预览 (") + (gSelectedGame == 0 ? "3人斗地主" : "4人广东红中麻将") + ")", 58, 446, COL_GOLD);
    int sw = (1160 - (seatCnt - 1) * 16) / seatCnt;
    for (int i = 0; i < seatCnt; ++i) {
        int sx = 58 + i * (sw + 16);
        int sy = 482;
        std::string sName = (gSelectedGame == 0) ? gDdzSeats[i].name : gMjSeats[i].name;
        bool isAI = (gSelectedGame == 0) ? gDdzSeats[i].isAI : gMjSeats[i].isAI;
        int sc = (gSelectedGame == 0) ? gDdzSeats[i].score : gMjSeats[i].score;
        drawRectFill(sx, sy, sw, 94, {14, 54, 34, 255});
        drawRectOutline(sx, sy, sw, 94, isAI ? COL_GRAY : COL_GOLD, isAI ? 1 : 2);
        drawText(gFontMed, sName, sx + sw / 2, sy + 16, COL_WHITE, true);
        drawText(gFontSmall, std::string(isAI ? "🤖 轻音AI补位" : "🎮 真人玩家") + " · 积分: " + std::to_string(sc), sx + sw / 2, sy + 54, COL_GOLD, true);
    }

    // 4. Start Button
    bool canStart = !wsConn || gIsRoomAuthority;
    drawRectFill(40, 610, 1200, 68, canStart ? COL_CRIMSON : COL_GRAY);
    drawRectOutline(40, 610, 1200, 68, COL_GOLD, 2);
    std::string startTxt = canStart
        ? (std::string("[A] 立即开始") + (gSelectedGame == 0 ? "放课后斗地主" : "广东红中麻将 (136张)"))
        : "⏳ 等待 1 号房主开始对局...";
    drawText(gFontLarge, startTxt, SCREEN_W / 2, 628, COL_WHITE, true);
}

static void renderDoudizhuTable() {
    // Status Banner
    drawRectFill(20, 58, 1240, 32, COL_PANEL);
    drawRectOutline(20, 58, 1240, 32, COL_GOLD, 1);
    drawText(gFontSmall, gStatusBanner, 34, 65, COL_GOLD);

    // Hole Cards + Multiplier + Counter Toggle
    drawRectFill(20, 96, 250, 56, COL_PANEL);
    drawText(gFontSmall, "底牌:", 30, 114, COL_CREAM);
    for (size_t i = 0; i < gDdzHoleCards.size(); ++i) {
        if (gDdzPhase == "bidding") drawPokerBack(80 + (int)i * 44, 100, 36, 48);
        else drawPokerCard(gDdzHoleCards[i], 80 + (int)i * 44, 100, 36, 48, false, false);
    }
    drawRectFill(282, 104, 80, 40, COL_CRIMSON);
    drawText(gFontMed, "x" + std::to_string(gDdzMultiplier), 322, 112, COL_GOLD, true);

    drawRectFill(1110, 104, 150, 40, gDdzShowCounter ? COL_GOLD : COL_PANEL);
    drawText(gFontSmall, "[R] 记牌器", 1185, 114, gDdzShowCounter ? COL_BLACK : COL_WHITE, true);

    // Card Counter Strip (17..3)
    if (gDdzShowCounter) {
        const int ranks[] = {17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3};
        const char* labels[] = {"大王", "小王", "2", "A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3"};
        for (int idx = 0; idx < 15; ++idx) {
            int r = ranks[idx];
            int rem = 0;
            for (int s = 0; s < 3; ++s) {
                if (s != gDdzMySeat) {
                    for (const auto& c : gDdzSeats[s].hand) if (c.rank == r) rem++;
                }
            }
            if (gDdzPhase == "bidding") {
                for (const auto& hc : gDdzHoleCards) if (hc.rank == r) rem++;
            }
            int bx = 20 + idx * 83;
            drawRectFill(bx, 158, 78, 38, COL_PANEL);
            drawText(gFontSmall, labels[idx], bx + 39, 160, idx <= 2 ? COL_GOLD : COL_CREAM, true);
            drawText(gFontSmall, std::to_string(rem), bx + 39, 177, rem == 4 ? COL_CRIMSON : (rem == 0 ? COL_GRAY : COL_WHITE), true);
        }
    }

    // Left (上家) & Right (下家) Opponent Boxes + 3-Seat Non-Overlapping Played Piles
    int leftIdx = (gDdzMySeat + 2) % 3;
    int rightIdx = (gDdzMySeat + 1) % 3;
    const auto& lSeat = gDdzSeats[leftIdx];
    const auto& rSeat = gDdzSeats[rightIdx];
    const auto& me = gDdzSeats[gDdzMySeat];

    // Left Opponent
    drawRectFill(20, 210, 220, 190, COL_PANEL);
    drawRectOutline(20, 210, 220, 190, gDdzTurnSeat == leftIdx ? COL_GOLD : COL_GRAY, 2);
    drawText(gFontSmall, lSeat.name, 32, 220, COL_WHITE);
    drawText(gFontSmall, std::string(lSeat.isLandlord ? "🎩 地主" : "🌾 农民") + " · 积分:" + std::to_string(lSeat.score), 32, 244, COL_GOLD);
    for (int k = 0; k < std::min(6, std::max(1, (int)lSeat.hand.size() / 3)); ++k) {
        drawPokerBack(32 + k * 12, 274, 46, 64);
    }
    drawText(gFontMed, "余 " + std::to_string(lSeat.hand.size()) + " 张", 145, 294, COL_GOLD);

    // Right Opponent
    drawRectFill(1040, 210, 220, 190, COL_PANEL);
    drawRectOutline(1040, 210, 220, 190, gDdzTurnSeat == rightIdx ? COL_GOLD : COL_GRAY, 2);
    drawText(gFontSmall, rSeat.name, 1052, 220, COL_WHITE);
    drawText(gFontSmall, std::string(rSeat.isLandlord ? "🎩 地主" : "🌾 农民") + " · 积分:" + std::to_string(rSeat.score), 1052, 244, COL_GOLD);
    for (int k = 0; k < std::min(6, std::max(1, (int)rSeat.hand.size() / 3)); ++k) {
        drawPokerBack(1052 + k * 12, 274, 46, 64);
    }
    drawText(gFontMed, "余 " + std::to_string(rSeat.hand.size()) + " 张", 1165, 294, COL_GOLD);

    // Center 3-Seat Played Cards Area (上家 | 我方 | 下家)
    if (!lSeat.lastPlayedCards.empty()) {
        for (size_t i = 0; i < lSeat.lastPlayedCards.size(); ++i) {
            drawPokerCard(lSeat.lastPlayedCards[i], 265 + (int)i * 28, 225, 62, 86, false, false);
        }
    } else if (!lSeat.lastActionText.empty()) {
        drawText(gFontMed, "上家: " + lSeat.lastActionText, 270, 250, COL_GOLD);
    }

    if (!rSeat.lastPlayedCards.empty()) {
        int startX = 960 - (int)rSeat.lastPlayedCards.size() * 28;
        for (size_t i = 0; i < rSeat.lastPlayedCards.size(); ++i) {
            drawPokerCard(rSeat.lastPlayedCards[i], startX + (int)i * 28, 225, 62, 86, false, false);
        }
    } else if (!rSeat.lastActionText.empty()) {
        drawText(gFontMed, "下家: " + rSeat.lastActionText, 860, 250, COL_GOLD);
    }

    if (!me.lastPlayedCards.empty()) {
        int startX = SCREEN_W / 2 - ((int)me.lastPlayedCards.size() * 30) / 2;
        for (size_t i = 0; i < me.lastPlayedCards.size(); ++i) {
            drawPokerCard(me.lastPlayedCards[i], startX + (int)i * 30, 325, 64, 88, false, false);
        }
    } else if (!me.lastActionText.empty()) {
        drawText(gFontMed, "我方: " + me.lastActionText, SCREEN_W / 2, 355, COL_GOLD, true);
    }

    // Action Bar
    drawRectFill(20, 432, 430, 44, COL_PANEL);
    drawRectOutline(20, 432, 430, 44, gDdzTurnSeat == gDdzMySeat ? COL_GOLD : COL_GRAY, 2);
    drawText(gFontSmall, me.name + (me.isLandlord ? " [🎩地主]" : " [🌾农民]") + " · 手牌:" + std::to_string(me.hand.size()) + " · 积分:" + std::to_string(me.score), 34, 444, COL_WHITE);

    if (gDdzPhase == "bidding" && gDdzTurnSeat == gDdzMySeat) {
        drawRectFill(470, 432, 790, 44, COL_CRIMSON);
        drawText(gFontMed, "叫地主阶段:  [B] 不叫    [Y] 叫1分    [X] 叫2分    [A] 叫3分", 865, 442, COL_WHITE, true);
    } else if (gDdzPhase == "playing" && gDdzTurnSeat == gDdzMySeat) {
        drawRectFill(470, 432, 790, 44, COL_GREEN_BTN);
        drawText(gFontMed, "[方向键] 移光标   [A] 选牌/取消   [Y] 智能提示   [B] 不出   [X] 确认出牌", 865, 442, COL_WHITE, true);
    } else if (gDdzPhase == "roundOver") {
        drawRectFill(470, 432, 790, 44, COL_CRIMSON);
        drawText(gFontMed, "本局结束！按 [A] 再来一局，按 [-] 退出房间返回大厅", 865, 442, COL_WHITE, true);
    } else {
        drawRectFill(470, 432, 790, 44, COL_PANEL);
        drawText(gFontMed, "⏳ 等待其他玩家操作...", 865, 442, COL_GOLD, true);
    }

    // Dealing Animation: 1-by-1 reveal over 700ms
    uint32_t elapsed = SDL_GetTicks() - gDdzDealStartTick;
    int visCount = std::min((int)me.hand.size(), std::max(1, (int)(elapsed / 38)));
    if (elapsed > 850) visCount = (int)me.hand.size();

    // Bottom Large Hand Cards (cardW=84, cardH=120)
    int cardW = 84, cardH = 120;
    int step = (visCount > 1) ? std::min(52, (1160 - cardW) / (visCount - 1)) : 0;
    int totalW = cardW + std::max(0, visCount - 1) * step;
    int startX = (SCREEN_W - totalW) / 2;
    for (int i = 0; i < visCount; ++i) {
        drawPokerCard(me.hand[i], startX + i * step, 512, cardW, cardH, (i == gDdzCursor), me.hand[i].selected);
    }
}

static void renderMahjongTable() {
    int oppIdx = (gMjMySeat + 2) % 4;
    int leftIdx = (gMjMySeat + 3) % 4;
    int rightIdx = (gMjMySeat + 1) % 4;

    // Status Banner
    drawRectFill(20, 56, 1240, 30, COL_PANEL);
    drawRectOutline(20, 56, 1240, 30, COL_GOLD, 1);
    drawText(gFontSmall, gStatusBanner, 34, 61, COL_GOLD);

    // Opposite Seat + 3D Standing Tile Wall + Un-drawn Wall Stack
    const auto& opp = gMjSeats[oppIdx];
    drawRectFill(20, 92, 260, 36, COL_PANEL);
    drawText(gFontSmall, opp.name + " · " + std::to_string(opp.score) + "分", 32, 100, COL_WHITE);
    for (int i = 0; i < std::min(14, (int)opp.hand.size()); ++i) {
        drawMahjongBack(292 + i * 24, 94, 22, 32);
    }

    // Visual Un-drawn Wall Stack (牌山)
    drawRectFill(880, 92, 380, 36, COL_PANEL);
    for (int i = 0; i < std::min(8, std::max(1, (gMjWallCount + 14) / 15)); ++i) {
        drawMahjongBack(892 + i * 16, 98, 14, 22);
    }
    drawText(gFontSmall, "牌山余 " + std::to_string(gMjWallCount) + " 张 · 第" + std::to_string(gMjRound) + "局", 1035, 100, COL_GOLD);

    // Opposite Discards & Melds
    for (size_t i = 0; i < opp.discards.size(); ++i) {
        drawMahjongTile(opp.discards[i], 340 + (int)(i % 12) * 34, 134 + (int)(i / 12) * 44, 32, 42, false, false, i + 1 == opp.discards.size());
    }

    // Left Seat + Vertical Standing Wall + Discards
    const auto& lSeat = gMjSeats[leftIdx];
    drawRectFill(20, 145, 185, 36, COL_PANEL);
    drawText(gFontSmall, lSeat.name + " · " + std::to_string(lSeat.score) + "分", 28, 154, COL_WHITE);
    for (int i = 0; i < std::min(11, (int)lSeat.hand.size()); ++i) {
        drawMahjongBack(24, 188 + i * 18, 30, 16);
    }
    for (size_t i = 0; i < lSeat.discards.size(); ++i) {
        drawMahjongTile(lSeat.discards[i], 68 + (int)(i % 6) * 34, 190 + (int)(i / 6) * 44, 32, 42, false, false, i + 1 == lSeat.discards.size());
    }

    // Center 4-Direction Wind Compass
    drawRectFill(490, 215, 300, 130, {7, 43, 51, 240});
    drawRectOutline(490, 215, 300, 130, COL_GOLD, 2);
    drawText(gFontMed, "北", 640, 222, gMjTurnSeat == oppIdx ? COL_GOLD : COL_GRAY, true);
    drawText(gFontMed, "西", 520, 268, gMjTurnSeat == leftIdx ? COL_GOLD : COL_GRAY, true);
    drawText(gFontMed, "东", 760, 268, gMjTurnSeat == rightIdx ? COL_GOLD : COL_GRAY, true);
    drawText(gFontMed, "南", 640, 314, gMjTurnSeat == gMjMySeat ? COL_GOLD : COL_GRAY, true);
    drawText(gFontMed, gMjPhase == "roundOver" ? ("🀄 " + gMjWinReason) : "红中=赖子·可碰杠", 640, 268, COL_WHITE, true);

    // Right Seat + Vertical Standing Wall + Discards
    const auto& rSeat = gMjSeats[rightIdx];
    drawRectFill(1075, 145, 185, 36, COL_PANEL);
    drawText(gFontSmall, rSeat.name + " · " + std::to_string(rSeat.score) + "分", 1083, 154, COL_WHITE);
    for (int i = 0; i < std::min(11, (int)rSeat.hand.size()); ++i) {
        drawMahjongBack(1226, 188 + i * 18, 30, 16);
    }
    for (size_t i = 0; i < rSeat.discards.size(); ++i) {
        drawMahjongTile(rSeat.discards[i], 990 + (int)(i % 6) * 34, 190 + (int)(i / 6) * 44, 32, 42, false, false, i + 1 == rSeat.discards.size());
    }

    // My Own Discards River
    const auto& me = gMjSeats[gMjMySeat];
    for (size_t i = 0; i < me.discards.size(); ++i) {
        drawMahjongTile(me.discards[i], 360 + (int)(i % 14) * 34, 366 + (int)(i / 14) * 44, 32, 42, false, false, i + 1 == me.discards.size());
    }

    // Action Bar
    drawRectFill(20, 464, 360, 42, COL_PANEL);
    drawText(gFontSmall, me.name + (me.isDealer ? " [庄]" : "") + " · 积分:" + std::to_string(me.score), 34, 475, COL_WHITE);

    if (gMjPhase == "claimWindow" && gMjHasClaim) {
        drawRectFill(396, 464, 864, 42, COL_CRIMSON);
        drawText(gFontMed, "⚡ 响应 [" + gMjClaimTile.fullName() + "]： [X] 胡牌!    [Y] 碰/明杠    [B] 过", 828, 473, COL_WHITE, true);
    } else if (gMjPhase == "playing" && gMjTurnSeat == gMjMySeat) {
        drawRectFill(396, 464, 864, 42, COL_GREEN_BTN);
        std::string selTxt = (gMjSelectedIdx >= 0 && gMjSelectedIdx < (int)me.hand.size())
            ? ("已选 [" + me.hand[gMjSelectedIdx].fullName() + "] · 按[Y]打出 / 再按[A]取消")
            : "[方向键] 选牌   [A] 选中/取消选中   [Y] 打出选中牌   [X] 自摸胡牌";
        drawText(gFontMed, selTxt, 828, 473, COL_WHITE, true);
    } else if (gMjPhase == "roundOver") {
        drawRectFill(396, 464, 864, 42, COL_CRIMSON);
        drawText(gFontMed, "本局结束！按 [A] 再来一局，按 [-] 退出房间返回大厅", 828, 473, COL_WHITE, true);
    } else {
        drawRectFill(396, 464, 864, 42, COL_PANEL);
        drawText(gFontMed, "⏳ 等待其他家摸牌出牌...", 828, 473, COL_GOLD, true);
    }

    // Bottom Row: Visual Melds (碰/明杠/暗杠) + Hand Tiles (with dealing animation)
    int curX = 28;
    for (const auto& m : me.melds) {
        int cnt = (m.kind == "碰") ? 3 : 4;
        for (int k = 0; k < cnt; ++k) {
            if (m.kind == "暗杠" && k != 2) drawMahjongBack(curX, 548, 48, 68);
            else drawMahjongTile(m.tile, curX, 548, 48, 68, false, false, false);
            curX += 50;
        }
        curX += 14;
    }

    uint32_t elapsed = SDL_GetTicks() - gMjDealStartTick;
    int visCount = std::min((int)me.hand.size(), std::max(1, (int)(elapsed / 40)));
    if (elapsed > 750) visCount = (int)me.hand.size();

    int tileW = 64, tileH = 92;
    for (int i = 0; i < visCount; ++i) {
        bool isDrawn = (me.hand[i].id == gMjDrawnTileId);
        int extraGap = (isDrawn && i + 1 == visCount) ? 14 : 0;
        drawMahjongTile(me.hand[i], curX + i * (tileW + 4) + extraGap, 534, tileW, tileH,
                        (i == gMjCursor), (i == gMjSelectedIdx), isDrawn);
    }
}

// ============================================================================
// AI Turn Scheduler (When Switch is Room Authority / Offline)
// ============================================================================
static void updateAiTurns() {
    if (gIsOnlineRoom && !gIsRoomAuthority) return;
    uint32_t now = SDL_GetTicks();

    if (gScreen == MODE_DDZ_TABLE && now >= gDdzAiNextTick) {
        if (gDdzPhase == "bidding" && gDdzSeats[gDdzTurnSeat].isAI) {
            int score = (gDdzHighestBid < 2 && (rand() % 2 == 0)) ? (gDdzHighestBid + 1) : 0;
            handleDdzBid(gDdzTurnSeat, score);
        } else if (gDdzPhase == "playing" && gDdzSeats[gDdzTurnSeat].isAI) {
            auto& aiHand = gDdzSeats[gDdzTurnSeat].hand;
            bool freeLead = (gDdzLastPlaySeat == gDdzTurnSeat || gDdzLastPlaySeat == -1);
            if (freeLead && !aiHand.empty()) {
                DdzEvalHand ev = DdzEvaluator::evaluate({aiHand.back()});
                executeDdzPlay(gDdzTurnSeat, ev);
            } else {
                bool played = false;
                if (gDdzLastValid.category == "single") {
                    for (int i = (int)aiHand.size() - 1; i >= 0; --i) {
                        if (aiHand[i].rank > gDdzLastValid.primaryRank) {
                            executeDdzPlay(gDdzTurnSeat, DdzEvaluator::evaluate({aiHand[i]}));
                            played = true;
                            break;
                        }
                    }
                } else if (gDdzLastValid.category == "pair") {
                    for (int i = (int)aiHand.size() - 1; i >= 1; --i) {
                        if (aiHand[i].rank == aiHand[i - 1].rank && aiHand[i].rank > gDdzLastValid.primaryRank) {
                            executeDdzPlay(gDdzTurnSeat, DdzEvaluator::evaluate({aiHand[i], aiHand[i - 1]}));
                            played = true;
                            break;
                        }
                    }
                }
                if (!played) handleDdzPass(gDdzTurnSeat);
            }
        }
    }

    if (gScreen == MODE_MJ_TABLE && now >= gMjAiNextTick) {
        if (gMjPhase == "playing" && gMjSeats[gMjTurnSeat].isAI) {
            auto& ai = gMjSeats[gMjTurnSeat];
            if (MjEvaluator::canHu(ai.hand, (int)ai.melds.size())) {
                executeMjWin(gMjTurnSeat, -1, "自摸胡牌");
                return;
            }
            // Discard first non-Laizi tile from end
            std::string discardId = ai.hand.back().id;
            for (int i = (int)ai.hand.size() - 1; i >= 0; --i) {
                if (!ai.hand[i].isLaizi()) { discardId = ai.hand[i].id; break; }
            }
            executeMjDiscard(gMjTurnSeat, discardId);
        }
    }
}

// ============================================================================
// Main Entry Point
// ============================================================================
int main(int argc, char* argv[]) {
    romfsInit();
    socketInitializeDefault();
    srand((unsigned int)time(nullptr));
    gMyPeerName = "Switch#" + std::to_string(100 + (rand() % 900));

    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_TIMER);
    IMG_Init(IMG_INIT_JPG | IMG_INIT_PNG);
    TTF_Init();

    gWindow = SDL_CreateWindow("HTT_GameRoom_Switch", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, SCREEN_W, SCREEN_H, SDL_WINDOW_SHOWN);
    gRenderer = SDL_CreateRenderer(gWindow, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    // Load Nintendo Switch Shared Chinese System Font (PlSharedFontType_ChineseSimplified)
    plInitialize(PlServiceType_User);
    PlFontData fontData;
    if (R_SUCCEEDED(plGetSharedFontByType(&fontData, PlSharedFontType_ChineseSimplified))) {
        gFontSmall = TTF_OpenFontRW(SDL_RWFromConstMem(fontData.address, fontData.size), 1, 18);
        gFontMed   = TTF_OpenFontRW(SDL_RWFromConstMem(fontData.address, fontData.size), 1, 22);
        gFontLarge = TTF_OpenFontRW(SDL_RWFromConstMem(fontData.address, fontData.size), 1, 28);
        gFontHuge  = TTF_OpenFontRW(SDL_RWFromConstMem(fontData.address, fontData.size), 1, 38);
    }

    rebuildLobbySeats();

    PadState pad;
    padConfigureInput(1, HidNpadStyleSet_NpadStandard);
    padInitializeDefault(&pad);

    bool running = true;
    while (running && appletMainLoop()) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) running = false;
        }

        padUpdate(&pad);
        u64 kDown = padGetButtonsDown(&pad);

        processIncomingNetworkMessages();
        updateAiTurns();

        if (gScreen == MODE_LOBBY) {
            if (kDown & HidNpadButton_Plus) {
                running = false;
            }
            if (!gIsOnlineRoom || !gWs.isConnected()) {
                if (kDown & HidNpadButton_L) { gSelectedGame = 0; rebuildLobbySeats(); }
                if (kDown & HidNpadButton_R) { gSelectedGame = 1; rebuildLobbySeats(); }
            }
            if (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) {
                if (gLobbyFocus <= 4) {
                    gLobbyFocus = (gLobbyFocus + 4) % 5;
                    gMyCharId = kCharacters[gLobbyFocus].charId;
                    rebuildLobbySeats();
                }
            }
            if (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) {
                if (gLobbyFocus <= 4) {
                    gLobbyFocus = (gLobbyFocus + 1) % 5;
                    gMyCharId = kCharacters[gLobbyFocus].charId;
                    rebuildLobbySeats();
                }
            }
            if (kDown & (HidNpadButton_Up | HidNpadButton_StickLUp)) {
                gLobbyFocus = 0;
            }
            if (kDown & (HidNpadButton_Down | HidNpadButton_StickLDown)) {
                gLobbyFocus = 7;
            }
            if (kDown & HidNpadButton_Y) {
                openSwitchRoomCodeKeyboard();
            }
            if (kDown & HidNpadButton_X) {
                if (gWs.isConnected()) {
                    std::string leavePkt = "{\"kind\":\"leaveRoom\",\"roomCode\":\"" + MiniJson::esc(wireRoomCode()) +
                                           "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                           "\",\"senderCharId\":" + std::to_string(gMyCharId) + "}";
                    gWs.sendText(leavePkt);
                    gWs.disconnect();
                    gIsOnlineRoom = false;
                    gRoomPeers.clear();
                    rebuildLobbySeats();
                    gStatusBanner = "👋 已退出在线房间，恢复单人+轻音AI模式";
                } else {
                    gIsOnlineRoom = true;
                    gRoomPeers.clear();
                    gRoomPeers.push_back({gMyPeerName, gMyCharId, gMyPeerName});
                    rebuildLobbySeats();
                    gWs.connectToRelay("azusa.online", "443", "/ddz");
                    SDL_Delay(350);
                    sendJoinRequestPacket();
                    gStatusBanner = "🌐 已连接跨平台服务器 azusa.online，房间号: " + gRoomCode;
                }
            }
            if (kDown & HidNpadButton_A) {
                if (gSelectedGame == 0) startNewDoudizhuRound();
                else startNewMahjongRound();
            }
        } else if (gScreen == MODE_DDZ_TABLE) {
            auto& myHand = gDdzSeats[gDdzMySeat].hand;
            if (kDown & HidNpadButton_Minus) {
                gDdzPhase = "lobby";
                gScreen = MODE_LOBBY;
                gStatusBanner = "👋 已退出房间返回大厅";
            }
            if (kDown & HidNpadButton_R) {
                gDdzShowCounter = !gDdzShowCounter;
            }
            if (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) {
                if (!myHand.empty()) gDdzCursor = (gDdzCursor + (int)myHand.size() - 1) % (int)myHand.size();
            }
            if (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) {
                if (!myHand.empty()) gDdzCursor = (gDdzCursor + 1) % (int)myHand.size();
            }
            if (gDdzPhase == "bidding" && gDdzTurnSeat == gDdzMySeat) {
                if (kDown & HidNpadButton_B) handleDdzBid(gDdzMySeat, 0);
                if (kDown & HidNpadButton_Y) handleDdzBid(gDdzMySeat, 1);
                if (kDown & HidNpadButton_X) handleDdzBid(gDdzMySeat, 2);
                if (kDown & HidNpadButton_A) handleDdzBid(gDdzMySeat, 3);
            } else if (gDdzPhase == "playing" && gDdzTurnSeat == gDdzMySeat) {
                if (kDown & HidNpadButton_A) {
                    if (gDdzCursor >= 0 && gDdzCursor < (int)myHand.size()) {
                        myHand[gDdzCursor].selected = !myHand[gDdzCursor].selected;
                    }
                }
                if (kDown & HidNpadButton_L) {
                    for (auto& c : myHand) c.selected = false;
                }
                if (kDown & HidNpadButton_Y) {
                    selectDdzHintForMe();
                }
                if (kDown & HidNpadButton_B) {
                    handleDdzPass(gDdzMySeat);
                }
                if (kDown & HidNpadButton_X) {
                    std::vector<DdzCard> chosen;
                    for (const auto& c : myHand) if (c.selected) chosen.push_back(c);
                    DdzEvalHand ev = DdzEvaluator::evaluate(chosen);
                    bool freeLead = (gDdzLastPlaySeat == gDdzMySeat || gDdzLastPlaySeat == -1);
                    if (ev.category == "invalid") {
                        gStatusBanner = "⚠️ 所选牌型不符合斗地主规则！";
                    } else if (!freeLead && !DdzEvaluator::canBeat(ev, gDdzLastValid)) {
                        gStatusBanner = "⚠️ 所选牌型管不上上家的牌！";
                    } else {
                        if (gIsOnlineRoom && !gIsRoomAuthority) {
                            std::string arr = "[";
                            for (size_t i = 0; i < chosen.size(); ++i) { if (i > 0) arr += ","; arr += chosen[i].toJson(); }
                            arr += "]";
                            std::string pkt = "{\"kind\":\"playCardsAction\",\"roomCode\":\"" + MiniJson::esc(gRoomCode) +
                                              "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                              "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                                              ",\"playedCards\":" + arr + "}";
                            gWs.sendText(pkt);
                        } else {
                            executeDdzPlay(gDdzMySeat, ev);
                        }
                    }
                }
            } else if (gDdzPhase == "roundOver") {
                if (kDown & HidNpadButton_A) {
                    gDdzRound++;
                    startNewDoudizhuRound();
                }
            }
        } else if (gScreen == MODE_MJ_TABLE) {
            auto& myHand = gMjSeats[gMjMySeat].hand;
            if (kDown & HidNpadButton_Minus) {
                gMjPhase = "lobby";
                gScreen = MODE_LOBBY;
                gStatusBanner = "👋 已退出麻将房间返回大厅";
            }
            if (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) {
                if (!myHand.empty()) gMjCursor = (gMjCursor + (int)myHand.size() - 1) % (int)myHand.size();
            }
            if (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) {
                if (!myHand.empty()) gMjCursor = (gMjCursor + 1) % (int)myHand.size();
            }
            if (gMjPhase == "claimWindow" && gMjHasClaim) {
                if ((kDown & HidNpadButton_X) && gMjCanHu) {
                    executeMjWin(gMjMySeat, gMjClaimFromSeat, "点炮胡 (" + gMjClaimTile.fullName() + ")");
                } else if ((kDown & HidNpadButton_Y) && (gMjCanKong || gMjCanPong)) {
                    gMjSeats[gMjClaimFromSeat].discards.pop_back();
                    int needRem = gMjCanKong ? 3 : 2;
                    int rem = 0;
                    for (auto it = myHand.begin(); it != myHand.end() && rem < needRem;) {
                        if (it->suit == gMjClaimTile.suit && it->rank == gMjClaimTile.rank) { it = myHand.erase(it); rem++; }
                        else ++it;
                    }
                    gMjSeats[gMjMySeat].melds.push_back({gMjClaimTile.id, gMjCanKong ? "明杠" : "碰", gMjClaimTile});
                    gMjHasClaim = false;
                    if (gMjCanKong) {
                        drawMjTileForSeat(gMjMySeat);
                    } else {
                        gMjPhase = "playing";
                        gMjTurnSeat = gMjMySeat;
                        gStatusBanner = "🀄 已碰 [" + gMjClaimTile.fullName() + "]！请点选一张手牌按 [Y] 打出";
                        broadcastMjState();
                    }
                } else if (kDown & HidNpadButton_B) {
                    gMjHasClaim = false;
                    drawMjTileForSeat((gMjClaimFromSeat + 1) % 4);
                }
            } else if (gMjPhase == "playing" && gMjTurnSeat == gMjMySeat) {
                // Tap A once to select tile, tap A again on same tile to deselect (matching v1.9.2 requirement!)
                if (kDown & HidNpadButton_A) {
                    if (gMjSelectedIdx == gMjCursor) gMjSelectedIdx = -1;
                    else gMjSelectedIdx = gMjCursor;
                }
                // Press Y to discard the currently selected tile
                if (kDown & HidNpadButton_Y) {
                    int idx = (gMjSelectedIdx >= 0 && gMjSelectedIdx < (int)myHand.size()) ? gMjSelectedIdx : gMjCursor;
                    if (idx >= 0 && idx < (int)myHand.size()) {
                        std::string tid = myHand[idx].id;
                        if (gIsOnlineRoom && !gIsRoomAuthority) {
                            std::string pkt = "{\"kind\":\"discardAction\",\"roomCode\":\"MJ_" + MiniJson::esc(gRoomCode) +
                                              "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                              "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                                              ",\"tileId\":\"" + MiniJson::esc(tid) + "\"}";
                            gWs.sendText(pkt);
                            gMjSelectedIdx = -1;
                        } else {
                            executeMjDiscard(gMjMySeat, tid);
                        }
                    }
                }
                // Press X to declare Self-Drawn Hu (自摸)
                if (kDown & HidNpadButton_X) {
                    if (MjEvaluator::canHu(myHand, (int)gMjSeats[gMjMySeat].melds.size())) {
                        executeMjWin(gMjMySeat, -1, "自摸胡牌");
                    } else {
                        gStatusBanner = "⚠️ 当前手牌尚未满足胡牌牌型！";
                    }
                }
            } else if (gMjPhase == "roundOver") {
                if (kDown & HidNpadButton_A) {
                    gMjRound++;
                    startNewMahjongRound();
                }
            }
        }

        // Render Frame
        SDL_Color bg = (gSelectedGame == 0) ? COL_BG_DDZ : COL_BG_MJ;
        SDL_SetRenderDrawColor(gRenderer, bg.r, bg.g, bg.b, 255);
        SDL_RenderClear(gRenderer);

        renderTopBar();
        if (gScreen == MODE_LOBBY) renderLobbyScreen();
        else if (gScreen == MODE_DDZ_TABLE) renderDoudizhuTable();
        else if (gScreen == MODE_MJ_TABLE) renderMahjongTable();

        SDL_RenderPresent(gRenderer);
    }

    gWs.disconnect();
    for (auto& kv : gTexCache) if (kv.second) SDL_DestroyTexture(kv.second);
    if (gFontSmall) TTF_CloseFont(gFontSmall);
    if (gFontMed)   TTF_CloseFont(gFontMed);
    if (gFontLarge) TTF_CloseFont(gFontLarge);
    if (gFontHuge)  TTF_CloseFont(gFontHuge);
    SDL_DestroyRenderer(gRenderer);
    SDL_DestroyWindow(gWindow);
    TTF_Quit();
    IMG_Quit();
    SDL_Quit();
    plExit();
    socketExit();
    romfsExit();
    return 0;
}
