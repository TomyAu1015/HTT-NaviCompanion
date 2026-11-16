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
#include <cmath>
#include <random>

#include "ws_client.hpp"
#include "game_logic.hpp"

// ============================================================================
// Constants & Theme Palette (1:1 K-ON! Ho-kago Tea Time Game Room)
// ============================================================================
static const int SCREEN_W = 1280;
static const int SCREEN_H = 720;

static const SDL_Color COL_BG_DDZ      = {14, 68, 40, 255};
static const SDL_Color COL_BG_MJ       = {11, 56, 35, 255};
static const SDL_Color COL_PANEL       = {7, 30, 19, 218};
static const SDL_Color COL_PANEL_INNER = {14, 52, 33, 235};
static const SDL_Color COL_GOLD        = {232, 184, 72, 255};
static const SDL_Color COL_GOLD_DIM    = {160, 125, 52, 180};
static const SDL_Color COL_CRIMSON     = {204, 46, 58, 255};
static const SDL_Color COL_CRIMSON_HI  = {235, 64, 76, 255};
static const SDL_Color COL_CRIMSON_DIM = {138, 32, 42, 225};
static const SDL_Color COL_GREEN_BTN   = {38, 142, 72, 255};
static const SDL_Color COL_HUMAN_GREEN = {46, 229, 130, 255};
static const SDL_Color COL_BLUE_BTN    = {30, 126, 220, 255};
static const SDL_Color COL_WHITE       = {255, 255, 255, 255};
static const SDL_Color COL_CREAM       = {252, 245, 230, 255};
static const SDL_Color COL_GRAY        = {148, 156, 152, 255};
static const SDL_Color COL_BLACK       = {20, 20, 20, 255};

// ============================================================================
// Global App State
// ============================================================================
enum AppScreenMode {
    MODE_LOBBY = 0,
    MODE_DDZ_TABLE = 1,
    MODE_MJ_TABLE = 2,
    MODE_RMK_TABLE = 3
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
static int gSelectedGame = 0; // 0 = 放课后斗地主(3P), 1 = 广东红中麻将(4P), 2 = 拉密数字牌(2-4P)
static int gMyCharId = 1;     // 1..5
static std::string gRoomCode = "";
static std::string gMyDisplayName = "Switch";
static std::string gMyPeerName = "Switch#101";
static std::string gStatusBanner = "欢迎来到放课后棋牌室！按 [L/R] 切换游戏，按 [Y] 填写房号后按 [X] 跨平台联机";

static bool gIsOnlineRoom = false;
static bool gIsRoomAuthority = true;
static std::vector<RoomPeer> gRoomPeers;

// Lobby focus index for D-Pad / Stick navigation
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
static int gDdzTotalRounds = 3;
static int gDdzTurnLimit = 20;
static uint32_t gDdzTurnStartTick = 0;
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
static int gMjTotalRounds = 4;
static int gMjTurnLimit = 20;
static uint32_t gMjTurnStartTick = 0;
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
// Rummikub Runtime State (106 Tiles · 2~4 Players · 30-Pt Icebreak · 60s Timer)
// ============================================================================
static std::string gRmkPhase = "lobby";
static int gRmkRoomPlayerCount = 4; // 2, 3, or 4 players selectable!
static std::vector<RmkSeat> gRmkSeats(4);
static std::vector<RmkTile> gRmkPool;
static int gRmkPoolCount = 0;
static std::vector<RmkMeld> gRmkTableMelds;
static int gRmkMySeat = 0;
static int gRmkTurnSeat = 0;
static int gRmkWinnerSeat = -1;
static int gRmkRound = 1;
static int gRmkCursor = 0;
static bool gRmkSortByColor = false;
static uint32_t gRmkTurnStartTick = 0;
static uint32_t gRmkAiNextTick = 0;
static bool gRmkEditing = false;
static std::vector<RmkMeld> gRmkWorkMelds, gRmkSnapMelds;
static std::vector<RmkTile> gRmkWorkHand, gRmkSnapHand;

static SDL_Color rmkTileColor(const std::string& c) {
    if (c == "R") return {220, 40, 50, 255};
    if (c == "B") return {30, 122, 230, 255};
    if (c == "Y") return {230, 149, 12, 255};
    if (c == "K") return {32, 146, 98, 255};
    return {126, 72, 198, 255};
}

// ============================================================================
// UTF-8 Sanitizer & Name Cleaners (Zero '☒' Missing Glyph Boxes & No '#365')
// ============================================================================
static std::string sanitizeForSwitchFont(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = (unsigned char)s[i];
        if (c < 0x80) {
            out.push_back((char)c);
            i += 1;
        } else if ((c & 0xE0) == 0xC0 && i + 1 < s.size()) {
            out.append(s, i, 2);
            i += 2;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < s.size()) {
            unsigned int b1 = (unsigned char)s[i + 1];
            unsigned int b2 = (unsigned char)s[i + 2];
            unsigned int cp = ((c & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
            // Filter out unsupported Miscellaneous Symbols, Dingbats, Variation Selectors & Replacement Chars
            // Keep arrows/triangles (U+25A0..U+25FF) and standard CJK/punctuation
            bool skip = false;
            if (cp >= 0x2300 && cp <= 0x23FF) skip = true; // ⏳, ⏱, etc.
            if (cp >= 0x2600 && cp <= 0x27BF && cp != 0x2605 && cp != 0x2660 && cp != 0x2663 && cp != 0x2665 && cp != 0x2666) skip = true; // ⚠️, ✅, ✨, etc.
            if (cp >= 0xFE00 && cp <= 0xFE0F) skip = true; // Variation selectors
            if (cp == 0xFFFD) skip = true;
            if (!skip) out.append(s, i, 3);
            i += 3;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < s.size()) {
            // Skip all 4-byte supplementary plane emojis (👑, 🎮, 🀄, 🃏, 🤖, 📱, 🎉, 🏆, 🐎, etc.)
            i += 4;
        } else {
            i += 1;
        }
    }
    // Trim leading spaces and collapse double spaces left by removed emojis
    std::string trimmed;
    bool prevSpace = true;
    for (char ch : out) {
        if (ch == ' ') {
            if (!prevSpace) trimmed.push_back(ch);
            prevSpace = true;
        } else {
            trimmed.push_back(ch);
            prevSpace = false;
        }
    }
    while (!trimmed.empty() && trimmed.back() == ' ') trimmed.pop_back();
    return trimmed;
}

// Strips '#365' device suffix and emojis from any peer name or seat name
static std::string cleanPeerLabel(const std::string& rawName) {
    std::string s = sanitizeForSwitchFont(rawName);
    // If string has trailing "(角色)" like "iPhone13pro#365 (田井中律)", strip '#365' before '(' or at end
    size_t hashPos = s.find('#');
    while (hashPos != std::string::npos) {
        // Check if '#2 ' is a seat prefix at index 0
        if (hashPos == 0 && s.size() > 2 && isdigit((unsigned char)s[1]) && s[2] == ' ') {
            s = s.substr(1, 1) + "号 " + s.substr(3);
            hashPos = s.find('#');
            continue;
        }
        size_t endDigit = hashPos + 1;
        while (endDigit < s.size() && isdigit((unsigned char)s[endDigit])) endDigit++;
        if (endDigit > hashPos + 1) {
            s.erase(hashPos, endDigit - hashPos);
        } else {
            break;
        }
        hashPos = s.find('#', hashPos);
    }
    // Also strip redundant "[房主] " if "房主" already present
    size_t brk = s.find("[房主] ");
    if (brk != std::string::npos) s.replace(brk, strlen("[房主] "), "房主 ");
    return sanitizeForSwitchFont(s);
}

// Truncates a UTF-8 string cleanly to maxChars codepoints so long names never overflow badges
static std::string truncateUtf8(const std::string& s, int maxCodepoints) {
    std::string clean = cleanPeerLabel(s);
    int count = 0;
    size_t i = 0;
    while (i < clean.size()) {
        if (count >= maxCodepoints) {
            return clean.substr(0, i) + "..";
        }
        unsigned char c = (unsigned char)clean[i];
        if (c < 0x80) i += 1;
        else if ((c & 0xE0) == 0xC0) i += 2;
        else if ((c & 0xF0) == 0xE0) i += 3;
        else i += 4;
        count++;
    }
    return clean;
}

// ============================================================================
// Helper: Texture & Smooth Scanline Anti-Aliased Geometry Rendering
// ============================================================================
static SDL_Texture* getTexture(const std::string& path) {
    auto it = gTexCache.find(path);
    if (it != gTexCache.end()) return it->second;
    SDL_Surface* surf = IMG_Load(path.c_str());
    if (!surf) {
        gTexCache[path] = nullptr;
        return nullptr;
    }
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
    SDL_Texture* tex = SDL_CreateTextureFromSurface(gRenderer, surf);
    SDL_FreeSurface(surf);
    gTexCache[path] = tex;
    return tex;
}

static void drawImage(const std::string& path, int x, int y, int w, int h) {
    SDL_Texture* tex = getTexture(path);
    if (tex) {
        SDL_Rect dst = {x, y, w, h};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    }
}

static void drawRoundedRectFill(int x, int y, int w, int h, int rad, SDL_Color c) {
    if (w <= 0 || h <= 0) return;
    int r = std::min(rad, std::min(w / 2, h / 2));
    SDL_SetRenderDrawBlendMode(gRenderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(gRenderer, c.r, c.g, c.b, c.a);
    if (r <= 1) {
        SDL_Rect rc = {x, y, w, h};
        SDL_RenderFillRect(gRenderer, &rc);
        return;
    }
    SDL_Rect mid = {x, y + r, w, h - 2 * r};
    SDL_RenderFillRect(gRenderer, &mid);
    for (int dy = 0; dy < r; ++dy) {
        double yd = (double)r - 0.5 - (double)dy;
        int dx = (int)std::round((double)r - std::sqrt(std::max(0.0, (double)(r * r) - yd * yd)));
        SDL_RenderDrawLine(gRenderer, x + dx, y + dy, x + w - 1 - dx, y + dy);
        SDL_RenderDrawLine(gRenderer, x + dx, y + h - 1 - dy, x + w - 1 - dx, y + h - 1 - dy);
    }
}

// Smooth scanline-filled rounded border (ZERO gaps along corners!)
static void drawRoundedRectOutline(int x, int y, int w, int h, int rad, SDL_Color c, int thickness = 2) {
    if (w <= 0 || h <= 0 || thickness <= 0) return;
    int r = std::min(rad, std::min(w / 2, h / 2));
    SDL_SetRenderDrawBlendMode(gRenderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(gRenderer, c.r, c.g, c.b, c.a);
    if (r <= 1) {
        for (int t = 0; t < thickness; ++t) {
            SDL_Rect rc = {x + t, y + t, w - 2 * t, h - 2 * t};
            SDL_RenderDrawRect(gRenderer, &rc);
        }
        return;
    }
    // Top, Bottom, Left, Right straight bars
    SDL_Rect topBar = {x + r, y, w - 2 * r, thickness};
    SDL_Rect botBar = {x + r, y + h - thickness, w - 2 * r, thickness};
    SDL_Rect lftBar = {x, y + r, thickness, h - 2 * r};
    SDL_Rect rgtBar = {x + w - thickness, y + r, thickness, h - 2 * r};
    SDL_RenderFillRect(gRenderer, &topBar);
    SDL_RenderFillRect(gRenderer, &botBar);
    SDL_RenderFillRect(gRenderer, &lftBar);
    SDL_RenderFillRect(gRenderer, &rgtBar);

    // 4 Corner rings filled with horizontal scanlines so there are never any pixel gaps
    int rIn = std::max(0, r - thickness);
    for (int dy = 0; dy < r; ++dy) {
        double ydOut = (double)r - 0.5 - (double)dy;
        int xOut = (int)std::round((double)r - std::sqrt(std::max(0.0, (double)(r * r) - ydOut * ydOut)));
        int xIn = r;
        if (dy >= thickness && rIn > 0) {
            double ydIn = (double)rIn - 0.5 - (double)(dy - thickness);
            if (ydIn > 0.0) {
                xIn = thickness + (int)std::round((double)rIn - std::sqrt(std::max(0.0, (double)(rIn * rIn) - ydIn * ydIn)));
            } else {
                xIn = thickness;
            }
        }
        if (xIn < xOut) xIn = xOut;
        // Top-left & Top-right corner scanlines
        SDL_RenderDrawLine(gRenderer, x + xOut, y + dy, x + xIn, y + dy);
        SDL_RenderDrawLine(gRenderer, x + w - 1 - xIn, y + dy, x + w - 1 - xOut, y + dy);
        // Bottom-left & Bottom-right corner scanlines
        SDL_RenderDrawLine(gRenderer, x + xOut, y + h - 1 - dy, x + xIn, y + h - 1 - dy);
        SDL_RenderDrawLine(gRenderer, x + w - 1 - xIn, y + h - 1 - dy, x + w - 1 - xOut, y + h - 1 - dy);
    }
}

static void drawRectFill(int x, int y, int w, int h, SDL_Color c) {
    drawRoundedRectFill(x, y, w, h, 10, c);
}

static void drawRectOutline(int x, int y, int w, int h, SDL_Color c, int thickness = 2) {
    drawRoundedRectOutline(x, y, w, h, 10, c, thickness);
}

static int drawText(TTF_Font* font, const std::string& rawText, int x, int y, SDL_Color col, bool center = false, bool rightAlign = false) {
    if (!font) return 0;
    std::string text = sanitizeForSwitchFont(rawText);
    if (text.empty()) return 0;
    SDL_Surface* surf = TTF_RenderUTF8_Blended(font, text.c_str(), col);
    if (!surf) return 0;
    int tw = surf->w;
    SDL_Texture* tex = SDL_CreateTextureFromSurface(gRenderer, surf);
    if (tex) {
        SDL_Rect dst = {x, y, surf->w, surf->h};
        if (center) dst.x -= surf->w / 2;
        else if (rightAlign) dst.x -= surf->w;
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
        SDL_DestroyTexture(tex);
    }
    SDL_FreeSurface(surf);
    return tw;
}

// ============================================================================
// Switch System On-Screen Keyboard (Swkbd) for Room Code & Nickname Input
// ============================================================================
static void openSwitchRoomCodeKeyboard() {
    SwkbdConfig kbd;
    Result rc = swkbdCreate(&kbd, 0);
    if (R_SUCCEEDED(rc)) {
        swkbdConfigMakePresetDefault(&kbd);
        swkbdConfigSetHeaderText(&kbd, "请输入放课后棋牌室房间号 (与 iOS / Android 相同)");
        swkbdConfigSetSubText(&kbd, "例如: 900 或 888");
        swkbdConfigSetInitialText(&kbd, gRoomCode.c_str());
        swkbdConfigSetStringLenMax(&kbd, 12);
        char outBuf[32] = {0};
        if (R_SUCCEEDED(swkbdShow(&kbd, outBuf, sizeof(outBuf)))) {
            if (strlen(outBuf) > 0) {
                gRoomCode = outBuf;
                gStatusBanner = "已设置房间号: " + gRoomCode;
            }
        }
        swkbdClose(&kbd);
    }
}

static void openSwitchNicknameKeyboard() {
    SwkbdConfig kbd;
    Result rc = swkbdCreate(&kbd, 0);
    if (R_SUCCEEDED(rc)) {
        swkbdConfigMakePresetDefault(&kbd);
        swkbdConfigSetHeaderText(&kbd, "请输入 Switch 联机昵称");
        swkbdConfigSetSubText(&kbd, "例如: TomySwitch");
        swkbdConfigSetInitialText(&kbd, gMyDisplayName.c_str());
        swkbdConfigSetStringLenMax(&kbd, 16);
        char outBuf[32] = {0};
        if (R_SUCCEEDED(swkbdShow(&kbd, outBuf, sizeof(outBuf)))) {
            std::string cleaned = cleanPeerLabel(outBuf);
            if (!cleaned.empty()) {
                std::string oldPeer = gMyPeerName;
                gMyDisplayName = cleaned;
                size_t hPos = oldPeer.rfind('#');
                std::string suffix = (hPos != std::string::npos) ? oldPeer.substr(hPos) : ("#" + std::to_string(100 + (rand() % 900)));
                gMyPeerName = gMyDisplayName + suffix;
                for (auto& rp : gRoomPeers) {
                    if (rp.name == oldPeer) {
                        rp.name = gMyPeerName;
                        rp.displayName = gMyDisplayName;
                    }
                }
                gStatusBanner = "已修改本机昵称: " + gMyDisplayName;
            }
        }
        swkbdClose(&kbd);
    }
}

// ============================================================================
// Cross-Platform WebSocket Sync (wss://azusa.online/ddz)
// ============================================================================
static std::string wireRoomCode() {
    return (gSelectedGame == 1) ? ("MJ_" + gRoomCode) : ((gSelectedGame == 2) ? ("RMK_" + gRoomCode) : gRoomCode);
}

static void sendJoinRequestPacket() {
    std::string rc = wireRoomCode();
    int maxP = (gSelectedGame == 0) ? 3 : ((gSelectedGame == 1) ? 4 : gRmkRoomPlayerCount);
    std::string gType = (gSelectedGame == 0) ? "doudizhu" : ((gSelectedGame == 1) ? "mahjong" : "rummikub");
    std::string j = "{\"kind\":\"joinRequest\",\"roomCode\":\"" + MiniJson::esc(rc) +
                    "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                    "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                    ",\"maxPlayers\":" + std::to_string(maxP) +
                    ",\"gameType\":\"" + gType + "\"}";
    gWs.sendText(j);
}

static void broadcastRoomRoster() {
    if (!gIsOnlineRoom || !gWs.isConnected() || !gIsRoomAuthority) return;
    std::string peersArr = "[";
    for (size_t i = 0; i < gRoomPeers.size(); ++i) {
        if (i > 0) peersArr += ",";
        std::string disp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
        peersArr += "{\"name\":\"" + MiniJson::esc(gRoomPeers[i].name) +
                    "\",\"charId\":" + std::to_string(gRoomPeers[i].charId) +
                    ",\"displayName\":\"" + MiniJson::esc(disp) + "\"}";
    }
    peersArr += "]";
    std::string pkt = "{\"kind\":\"roomRoster\",\"roomCode\":\"" + MiniJson::esc(wireRoomCode()) +
                      "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                      "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                      ",\"hostPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                      "\",\"roomPeers\":" + peersArr + "}";
    gWs.sendText(pkt);
}

static void broadcastDdzState() {
    if (!gIsOnlineRoom || !gWs.isConnected()) return;
    std::string peersArr = "[";
    for (size_t i = 0; i < gRoomPeers.size(); ++i) {
        if (i > 0) peersArr += ",";
        std::string disp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
        peersArr += "{\"name\":\"" + MiniJson::esc(gRoomPeers[i].name) +
                    "\",\"charId\":" + std::to_string(gRoomPeers[i].charId) +
                    ",\"displayName\":\"" + MiniJson::esc(disp) + "\"}";
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
                      ",\"bidsCount\":" + std::to_string(gDdzBidsCount) +
                      ",\"multiplier\":" + std::to_string(gDdzMultiplier) +
                      ",\"lastPlaySeat\":" + std::to_string(gDdzLastPlaySeat) +
                      (gDdzLastValid.category != "invalid" ? (",\"lastValidHand\":" + gDdzLastValid.toJson()) : "") +
                      (gDdzWinnerSeat >= 0 ? (",\"winnerSeat\":" + std::to_string(gDdzWinnerSeat)) : "") +
                      ",\"currentRound\":" + std::to_string(gDdzRound) +
                      ",\"totalRounds\":" + std::to_string(gDdzTotalRounds) +
                      ",\"baseScore\":" + std::to_string(gDdzBaseScore) +
                      ",\"statusBanner\":\"" + MiniJson::esc(gStatusBanner) + "\"}";
    gWs.sendText(pkt);
}

static void broadcastMjState() {
    if (!gIsOnlineRoom || !gWs.isConnected()) return;
    std::string peersArr = "[";
    for (size_t i = 0; i < gRoomPeers.size(); ++i) {
        if (i > 0) peersArr += ",";
        std::string disp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
        peersArr += "{\"name\":\"" + MiniJson::esc(gRoomPeers[i].name) +
                    "\",\"charId\":" + std::to_string(gRoomPeers[i].charId) +
                    ",\"displayName\":\"" + MiniJson::esc(disp) + "\"}";
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
                      (!gMjDrawnTileId.empty() ? (",\"drawnTileId\":\"" + MiniJson::esc(gMjDrawnTileId) + "\"") : "") +
                      (gMjWinnerSeat >= 0 ? (",\"winnerSeat\":" + std::to_string(gMjWinnerSeat)) : "") +
                      ",\"winReason\":\"" + MiniJson::esc(gMjWinReason) + "\"" +
                      ",\"currentRound\":" + std::to_string(gMjRound) +
                      ",\"totalRounds\":" + std::to_string(gMjTotalRounds) +
                      ",\"baseScore\":" + std::to_string(gMjBaseScore) +
                      ",\"statusBanner\":\"" + MiniJson::esc(gStatusBanner) + "\"}";
    gWs.sendText(pkt);
}

// ============================================================================
// Lobby Seat Builder (Uses cleanPeerLabel so '#365' never appears!)
// ============================================================================
static void rebuildLobbySeats() {
    if (gRoomPeers.empty()) {
        gRoomPeers.push_back({gMyPeerName, gMyCharId, gMyDisplayName});
    } else {
        for (auto& rp : gRoomPeers) {
            if (rp.name == gMyPeerName) {
                rp.charId = gMyCharId;
                rp.displayName = gMyDisplayName;
            } else if (rp.displayName.empty()) {
                rp.displayName = cleanPeerLabel(rp.name);
            } else {
                rp.displayName = cleanPeerLabel(rp.displayName);
            }
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
            std::string cleanDisp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
            std::string roleTag = (i == 0) ? "房主 " : (std::to_string(i + 1) + "号 ");
            gDdzSeats[i] = {i, roleTag + cleanDisp,
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
            std::string cleanDisp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
            std::string roleTag = (i == 0) ? "房主 " : (std::to_string(i + 1) + "号 ");
            gMjSeats[i] = {i, roleTag + cleanDisp, gRoomPeers[i].charId, false, gRoomPeers[i].name, {}, {}, {}, prevScore, (i == 0), ""};
        } else {
            int aiChar = 1;
            for (int c = 1; c <= 5; ++c) if (!usedChars.count(c)) { aiChar = c; usedChars.insert(c); break; }
            gMjSeats[i] = {i, getCharacterName(aiChar) + " (AI)", aiChar, true, "AI_" + std::to_string(i), {}, {}, {}, prevScore, (i == 0), ""};
        }
    }

    // Rummikub 2..4 seats (Dynamic gRmkRoomPlayerCount, humans replace AI!)
    usedChars.clear();
    int rmkCnt = std::max(2, std::min(4, gRmkRoomPlayerCount));
    std::vector<RmkSeat> newRmk(rmkCnt);
    for (int i = 0; i < rmkCnt; ++i) {
        int prevScore = (i < (int)gRmkSeats.size()) ? gRmkSeats[i].score : 1000;
        if (i < (int)gRoomPeers.size()) {
            if (gRoomPeers[i].name == gMyPeerName) gRmkMySeat = i;
            usedChars.insert(gRoomPeers[i].charId);
            std::string cleanDisp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
            std::string roleTag = (i == 0) ? "房主 " : (std::to_string(i + 1) + "号 ");
            newRmk[i] = {i, roleTag + cleanDisp, gRoomPeers[i].charId, false, gRoomPeers[i].name, {}, false, prevScore};
        } else {
            int aiChar = 1;
            for (int c = 1; c <= 5; ++c) if (!usedChars.count(c)) { aiChar = c; usedChars.insert(c); break; }
            newRmk[i] = {i, getCharacterName(aiChar) + " (AI)", aiChar, true, "AI_" + std::to_string(i), {}, false, prevScore};
        }
    }
    gRmkSeats = newRmk;
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
    gDdzTurnSeat = (gDdzRound - 1) % 3;
    gDdzHighestBid = 0;
    gDdzHighestBidder = -1;
    gDdzBidsCount = 0;
    gDdzMultiplier = 1;
    gDdzLastValid = DdzEvalHand();
    gDdzLastPlaySeat = -1;
    gDdzWinnerSeat = -1;
    gDdzCursor = 0;
    gDdzDealStartTick = SDL_GetTicks();
    gDdzTurnStartTick = SDL_GetTicks();
    gDdzAiNextTick = SDL_GetTicks() + 1800;
    gScreen = MODE_DDZ_TABLE;
    gStatusBanner = "发牌完成！轮到 [" + cleanPeerLabel(gDdzSeats[gDdzTurnSeat].name) + "] 叫地主";
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

    gDdzSeats[seatIdx].lastActionText = (score == 0) ? "不叫" : ("叫 " + std::to_string(score) + " 分");
    if (score > gDdzHighestBid) {
        gDdzHighestBid = score;
        gDdzHighestBidder = seatIdx;
    }
    gDdzBidsCount++;

    if (score == 3 || gDdzBidsCount >= 3) {
        int landlord = (gDdzHighestBidder >= 0) ? gDdzHighestBidder : 0;
        if (gDdzHighestBid == 0) gDdzHighestBid = 1;
        gDdzMultiplier = gDdzHighestBid;
        for (int i = 0; i < 3; ++i) {
            gDdzSeats[i].isLandlord = (i == landlord);
            gDdzSeats[i].lastActionText = "";
        }
        for (const auto& hc : gDdzHoleCards) {
            gDdzSeats[landlord].hand.push_back(hc);
        }
        std::sort(gDdzSeats[landlord].hand.begin(), gDdzSeats[landlord].hand.end(), [](const DdzCard& a, const DdzCard& b) {
            return a.rank > b.rank;
        });
        gDdzPhase = "playing";
        gDdzTurnSeat = landlord;
        gDdzTurnStartTick = SDL_GetTicks();
        gStatusBanner = "[" + cleanPeerLabel(gDdzSeats[landlord].name) + "] 成为地主！获得3张底牌，请先出牌";
    } else {
        gDdzTurnSeat = (gDdzTurnSeat + 1) % 3;
        gDdzTurnStartTick = SDL_GetTicks();
        gStatusBanner = "轮到 [" + cleanPeerLabel(gDdzSeats[gDdzTurnSeat].name) + "] 叫分";
    }
    gDdzAiNextTick = SDL_GetTicks() + 1800;
    broadcastDdzState();
}

static void executeDdzPlay(int seatIdx, const DdzEvalHand& eval) {
    auto& hand = gDdzSeats[seatIdx].hand;
    for (const auto& pc : eval.cards) {
        auto it = std::find_if(hand.begin(), hand.end(), [&](const DdzCard& c) { return c.id == pc.id; });
        if (it != hand.end()) hand.erase(it);
    }
    if (eval.category == "bomb" || eval.category == "rocket") {
        gDdzMultiplier *= 2;
    }
    gDdzSeats[seatIdx].lastPlayedCards = eval.cards;
    gDdzSeats[seatIdx].lastActionText = eval.labelZh();
    gDdzLastValid = eval;
    gDdzLastPlaySeat = seatIdx;
    if (seatIdx == gDdzMySeat && gDdzCursor >= (int)hand.size()) {
        gDdzCursor = std::max(0, (int)hand.size() - 1);
    }

    if (hand.empty()) {
        gDdzPhase = "roundOver";
        gDdzWinnerSeat = seatIdx;
        int delta = gDdzBaseScore * gDdzMultiplier;
        bool landlordWon = gDdzSeats[seatIdx].isLandlord;
        for (int i = 0; i < 3; ++i) {
            if (gDdzSeats[i].isLandlord) gDdzSeats[i].score += landlordWon ? (delta * 2) : (-delta * 2);
            else gDdzSeats[i].score += landlordWon ? (-delta) : delta;
        }
        gStatusBanner = "本局结束！[" + cleanPeerLabel(gDdzSeats[seatIdx].name) + "] 获胜 (" + (landlordWon ? "地主胜" : "农民胜") + ")！按 [A] 下一局";
    } else {
        gDdzTurnSeat = (seatIdx + 1) % 3;
        gDdzSeats[gDdzTurnSeat].lastPlayedCards.clear();
        gDdzSeats[gDdzTurnSeat].lastActionText = "";
        gDdzTurnStartTick = SDL_GetTicks();
        gStatusBanner = "[" + cleanPeerLabel(gDdzSeats[seatIdx].name) + "] 打出 " + eval.labelZh() + " · 轮到 [" + cleanPeerLabel(gDdzSeats[gDdzTurnSeat].name) + "]";
    }
    gDdzAiNextTick = SDL_GetTicks() + 1800;
    broadcastDdzState();
}

static void handleDdzPass(int seatIdx) {
    if (gDdzPhase != "playing" || seatIdx != gDdzTurnSeat) return;
    if (gDdzLastPlaySeat == seatIdx || gDdzLastPlaySeat == -1) {
        gStatusBanner = "[注意] 您是本轮首发出牌，不能选择不出！";
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
            if (i != gDdzTurnSeat) gDdzSeats[i].lastPlayedCards.clear();
        }
    }
    gDdzTurnStartTick = SDL_GetTicks();
    gStatusBanner = "[" + cleanPeerLabel(gDdzSeats[seatIdx].name) + "] 不出 · 轮到 [" + cleanPeerLabel(gDdzSeats[gDdzTurnSeat].name) + "]";
    gDdzAiNextTick = SDL_GetTicks() + 1800;
    broadcastDdzState();
}

static void selectDdzHintForMe() {
    auto& hand = gDdzSeats[gDdzMySeat].hand;
    for (auto& c : hand) c.selected = false;
    if (hand.empty()) return;

    bool freeLead = (gDdzLastPlaySeat == gDdzMySeat || gDdzLastPlaySeat == -1);
    if (freeLead) {
        hand.back().selected = true;
        gDdzCursor = (int)hand.size() - 1;
        return;
    }

    if (gDdzLastValid.category == "single") {
        for (int i = (int)hand.size() - 1; i >= 0; --i) {
            if (hand[i].rank > gDdzLastValid.primaryRank) {
                hand[i].selected = true;
                gDdzCursor = i;
                return;
            }
        }
    } else if (gDdzLastValid.category == "pair") {
        for (int i = (int)hand.size() - 1; i >= 1; --i) {
            if (hand[i].rank == hand[i - 1].rank && hand[i].rank > gDdzLastValid.primaryRank) {
                hand[i].selected = true;
                hand[i - 1].selected = true;
                gDdzCursor = i - 1;
                return;
            }
        }
    } else if (gDdzLastValid.category == "triple") {
        for (int i = (int)hand.size() - 1; i >= 2; --i) {
            if (hand[i].rank == hand[i - 1].rank && hand[i].rank == hand[i - 2].rank && hand[i].rank > gDdzLastValid.primaryRank) {
                hand[i].selected = hand[i - 1].selected = hand[i - 2].selected = true;
                gDdzCursor = i - 2;
                return;
            }
        }
    }
    for (int i = (int)hand.size() - 1; i >= 3; --i) {
        if (hand[i].rank == hand[i - 1].rank && hand[i].rank == hand[i - 2].rank && hand[i].rank == hand[i - 3].rank) {
            hand[i].selected = hand[i - 1].selected = hand[i - 2].selected = hand[i - 3].selected = true;
            gDdzCursor = i - 3;
            return;
        }
    }
    handleDdzPass(gDdzMySeat);
}

// ============================================================================
// Mahjong Game Flow (136 Tiles · 红中赖子 · 自摸胡 · 4马奖马)
// ============================================================================
static void startNewMahjongRound() {
    if (gIsOnlineRoom && !gIsRoomAuthority) return;
    rebuildLobbySeats();

    gMjWall.clear();
    const char* suits[] = {"W", "T", "D"};
    const char* suitPrefix[] = {"w", "t", "d"};
    for (int s = 0; s < 3; ++s) {
        for (int r = 1; r <= 9; ++r) {
            for (int c = 1; c <= 4; ++c) {
                gMjWall.push_back({std::string(suitPrefix[s]) + "_" + std::to_string(r) + "_" + std::to_string(c), suits[s], r});
            }
        }
    }
    for (int r = 1; r <= 6; ++r) {
        for (int c = 1; c <= 4; ++c) {
            gMjWall.push_back({"h_" + std::to_string(r) + "_" + std::to_string(c), "H", r});
        }
    }
    for (int c = 1; c <= 4; ++c) {
        gMjWall.push_back({"z_5_" + std::to_string(c), "Z", 0});
    }

    std::mt19937 rng((unsigned int)time(nullptr) ^ SDL_GetTicks());
    std::shuffle(gMjWall.begin(), gMjWall.end(), rng);

    int dealer = (gMjRound - 1) % 4;
    for (int i = 0; i < 4; ++i) {
        gMjSeats[i].hand.assign(gMjWall.begin() + i * 13, gMjWall.begin() + (i + 1) * 13);
        MjEvaluator::sortHand(gMjSeats[i].hand);
        gMjSeats[i].melds.clear();
        gMjSeats[i].discards.clear();
        gMjSeats[i].isDealer = (i == dealer);
        gMjSeats[i].lastActionText = "";
    }
    gMjWall.erase(gMjWall.begin(), gMjWall.begin() + 52);

    // Dealer draws 14th tile placed on far right (unsorted until discard!)
    MjTile drawn = gMjWall.front();
    gMjWall.erase(gMjWall.begin());
    gMjSeats[dealer].hand.push_back(drawn);
    gMjDrawnTileId = drawn.id;
    gMjWallCount = (int)gMjWall.size();

    gMjPhase = "playing";
    gMjTurnSeat = dealer;
    gMjWinnerSeat = -1;
    gMjWinReason = "";
    gMjHasClaim = false;
    gMjSelectedIdx = -1;
    gMjCursor = (int)gMjSeats[gMjMySeat].hand.size() - 1;
    gMjDealStartTick = SDL_GetTicks();
    gMjTurnStartTick = SDL_GetTicks();
    gMjAiNextTick = SDL_GetTicks() + 1850;
    gScreen = MODE_MJ_TABLE;
    gStatusBanner = "广东红中麻将开局！庄家 [" + cleanPeerLabel(gMjSeats[dealer].name) + "] 先出牌";
    broadcastMjState();
}

static void executeMjWin(int winner, int loser, const std::string& reason) {
    gMjPhase = "roundOver";
    gMjWinnerSeat = winner;
    gMjHasClaim = false;
    int horseHits = 0;
    int drawCount = std::min(4, (int)gMjWall.size());
    for (int i = 0; i < drawCount; ++i) {
        const auto& ht = gMjWall[i];
        if (ht.isLaizi() || ((ht.suit == "W" || ht.suit == "T" || ht.suit == "D") && (ht.rank == 1 || ht.rank == 5 || ht.rank == 9))) {
            horseHits++;
        }
    }
    int horseMult = 1 + horseHits;
    gMjWinReason = reason + " (中" + std::to_string(horseHits) + "马)";
    int delta = gMjBaseScore * 2 * horseMult;
    if (loser < 0) {
        for (int i = 0; i < 4; ++i) {
            if (i == winner) gMjSeats[i].score += delta * 3;
            else gMjSeats[i].score -= delta;
        }
    } else {
        gMjSeats[winner].score += delta;
        gMjSeats[loser].score -= delta;
    }
    gStatusBanner = "[" + cleanPeerLabel(gMjSeats[winner].name) + "] " + gMjWinReason + "！按 [A] 下一局";
    broadcastMjState();
}

static void drawMjTileForSeat(int seatIdx) {
    if (gMjWall.empty()) {
        gMjPhase = "roundOver";
        gMjWinnerSeat = -1;
        gMjWinReason = "荒庄流局";
        gStatusBanner = "牌山摸空，本局荒庄流局！按 [A] 开始下一局";
        broadcastMjState();
        return;
    }
    MjTile t = gMjWall.front();
    gMjWall.erase(gMjWall.begin());
    gMjWallCount = (int)gMjWall.size();
    // Place newly drawn tile on far right (unsorted until discard!)
    gMjSeats[seatIdx].hand.push_back(t);
    gMjDrawnTileId = t.id;
    gMjTurnSeat = seatIdx;
    gMjPhase = "playing";
    gMjHasClaim = false;
    gMjSelectedIdx = -1;
    if (seatIdx == gMjMySeat) {
        gMjCursor = (int)gMjSeats[seatIdx].hand.size() - 1;
    }
    gMjTurnStartTick = SDL_GetTicks();
    gMjAiNextTick = SDL_GetTicks() + 1850;
    gStatusBanner = "轮到 [" + cleanPeerLabel(gMjSeats[seatIdx].name) + "] 摸牌出牌 (余 " + std::to_string(gMjWallCount) + " 张)";
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
    gMjDrawnTileId = "";
    gMjSeats[seatIdx].discards.push_back(discarded);
    gMjSeats[seatIdx].lastActionText = "打出 " + discarded.fullName();
    if (seatIdx == gMjMySeat) {
        gMjSelectedIdx = -1;
        if (gMjCursor >= (int)hand.size()) gMjCursor = std::max(0, (int)hand.size() - 1);
    }

    // Check Pong/Kong for my seat (Self-draw only rule: no 点炮胡 on discard!)
    if (seatIdx != gMjMySeat && !discarded.isLaizi()) {
        int sameCount = 0;
        for (const auto& t : gMjSeats[gMjMySeat].hand) {
            if (t.suit == discarded.suit && t.rank == discarded.rank) sameCount++;
        }
        bool canHu = false;
        bool canKong = (sameCount >= 3);
        bool canPong = (sameCount >= 2);
        if (canHu || canKong || canPong) {
            gMjPhase = "claimWindow";
            gMjHasClaim = true;
            gMjClaimFromSeat = seatIdx;
            gMjClaimTile = discarded;
            gMjCanHu = canHu;
            gMjCanKong = canKong;
            gMjCanPong = canPong;
            gStatusBanner = "[" + cleanPeerLabel(gMjSeats[seatIdx].name) + "] 打出 [" + discarded.fullName() + "]！请选择 碰 / 杠 / 过";
            broadcastMjState();
            return;
        }
    }

    // Check AI Pong
    for (int step = 1; step <= 3; ++step) {
        int s = (seatIdx + step) % 4;
        if (!gMjSeats[s].isAI || discarded.isLaizi()) continue;
        int sameCount = 0;
        for (const auto& t : gMjSeats[s].hand) {
            if (t.suit == discarded.suit && t.rank == discarded.rank) sameCount++;
        }
        if (sameCount >= 2 && (rand() % 3 == 0)) {
            gMjSeats[seatIdx].discards.pop_back();
            int removed = 0;
            auto& aiH = gMjSeats[s].hand;
            for (auto ait = aiH.begin(); ait != aiH.end() && removed < 2;) {
                if (ait->suit == discarded.suit && ait->rank == discarded.rank) { ait = aiH.erase(ait); removed++; }
                else ++ait;
            }
            gMjSeats[s].melds.push_back({discarded.id, "碰", discarded});
            gMjSeats[s].lastActionText = "碰 " + discarded.fullName();
            gMjTurnSeat = s;
            gMjPhase = "playing";
            gMjTurnStartTick = SDL_GetTicks();
            gMjAiNextTick = SDL_GetTicks() + 1850;
            gStatusBanner = "[" + cleanPeerLabel(gMjSeats[s].name) + "] 碰了 [" + discarded.fullName() + "]！";
            broadcastMjState();
            return;
        }
    }

    drawMjTileForSeat((seatIdx + 1) % 4);
}


static void sortRmkHand(std::vector<RmkTile>& h) {
    std::sort(h.begin(), h.end(), [](const RmkTile& a, const RmkTile& b) {
        if (a.isJoker() != b.isJoker()) return !a.isJoker();
        if (gRmkSortByColor) {
            if (a.color != b.color) return a.color < b.color;
            return a.number < b.number;
        }
        if (a.number != b.number) return a.number < b.number;
        return a.color < b.color;
    });
}

static void resetRmkWorkspace() {
    gRmkEditing = false;
    if (gRmkMySeat >= 0 && gRmkMySeat < (int)gRmkSeats.size()) {
        gRmkSnapHand = gRmkSeats[gRmkMySeat].hand;
        for (auto& t : gRmkSeats[gRmkMySeat].hand) t.selected = false;
    } else {
        gRmkSnapHand.clear();
    }
    gRmkWorkHand = gRmkSnapHand;
    gRmkSnapMelds = gRmkTableMelds;
    gRmkWorkMelds = gRmkSnapMelds;
    for (auto& t : gRmkWorkHand) t.selected = false;
}

static void selectRmkHintForMe() {
    auto& rack = gRmkEditing ? gRmkWorkHand : gRmkSeats[gRmkMySeat].hand;
    for (auto& t : rack) t.selected = false;
    auto best = RmkEvaluator::findBestMeld(rack);
    if (best.empty()) {
        gStatusBanner = "[提示] 当前牌架暂无可直出的3张以上顺组或群组，建议点击【摸牌过】";
        return;
    }
    std::set<std::string> ids;
    for (const auto& b : best) ids.insert(b.id);
    for (size_t i = 0; i < rack.size(); ++i) {
        if (ids.count(rack[i].id)) {
            rack[i].selected = true;
            gRmkCursor = (int)i;
        }
    }
    int pts = RmkEvaluator::evaluateMeld(best);
    gStatusBanner = "[提示] 已为您选中一组有效牌型 (" + std::to_string(pts) + "分)，点击【放上桌面】即可摆出！";
}

static void broadcastRmkState() {
    if (!gIsOnlineRoom || !gWs.isConnected()) return;
    std::string peersArr = "[";
    for (size_t i = 0; i < gRoomPeers.size(); ++i) {
        if (i > 0) peersArr += ",";
        std::string disp = cleanPeerLabel(gRoomPeers[i].displayName.empty() ? gRoomPeers[i].name : gRoomPeers[i].displayName);
        peersArr += "{\"name\":\"" + MiniJson::esc(gRoomPeers[i].name) + "\",\"charId\":" + std::to_string(gRoomPeers[i].charId) + ",\"displayName\":\"" + MiniJson::esc(disp) + "\"}";
    }
    peersArr += "]";
    std::string seatsArr = "[";
    for (size_t i = 0; i < gRmkSeats.size(); ++i) {
        if (i > 0) seatsArr += ",";
        const auto& s = gRmkSeats[i];
        std::string hArr = "[";
        for (size_t k = 0; k < s.hand.size(); ++k) { if (k > 0) hArr += ","; hArr += s.hand[k].toJson(); }
        hArr += "]";
        seatsArr += "{\"id\":" + std::to_string(s.id) + ",\"name\":\"" + MiniJson::esc(s.name) + "\",\"characterId\":" + std::to_string(s.characterId) +
                    ",\"isAI\":" + std::string(s.isAI ? "true" : "false") + ",\"peerDisplayName\":\"" + MiniJson::esc(s.peerDisplayName) +
                    "\",\"hand\":" + hArr + ",\"hasBrokenIce\":" + std::string(s.hasBrokenIce ? "true" : "false") + ",\"score\":" + std::to_string(s.score) + "}";
    }
    seatsArr += "]";
    std::string meldsArr = "[";
    for (size_t i = 0; i < gRmkTableMelds.size(); ++i) { if (i > 0) meldsArr += ","; meldsArr += gRmkTableMelds[i].toJson(); }
    meldsArr += "]";
    std::string pkt = "{\"kind\":\"stateSync\",\"roomCode\":\"RMK_" + MiniJson::esc(gRoomCode) +
                      "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) + "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                      ",\"maxPlayers\":" + std::to_string(gRmkRoomPlayerCount) + ",\"gameType\":\"rummikub\"" +
                      ",\"hostPeerName\":\"" + MiniJson::esc(gMyPeerName) + "\",\"roomPeers\":" + peersArr +
                      ",\"seats\":" + seatsArr + ",\"tableMelds\":" + meldsArr + ",\"poolCount\":" + std::to_string(gRmkPoolCount) +
                      ",\"phase\":\"" + gRmkPhase + "\",\"currentTurnSeat\":" + std::to_string(gRmkTurnSeat) +
                      ",\"currentRound\":" + std::to_string(gRmkRound) + ",\"statusBanner\":\"" + MiniJson::esc(gStatusBanner) + "\"}";
    gWs.sendText(pkt);
}

static void startNewRmkRound() {
    if (gIsOnlineRoom && !gIsRoomAuthority) return;
    rebuildLobbySeats();
    int pCnt = (int)gRmkSeats.size();
    gRmkPool.clear();
    const char* cols[] = {"R", "B", "Y", "K"};
    for (int copy = 1; copy <= 2; ++copy) {
        for (int c = 0; c < 4; ++c) {
            for (int n = 1; n <= 13; ++n) {
                gRmkPool.push_back({std::string(cols[c]) + "_" + std::to_string(n) + "_" + std::to_string(copy), cols[c], n, false});
            }
        }
    }
    gRmkPool.push_back({"J_1", "J", 0, false});
    gRmkPool.push_back({"J_2", "J", 0, false});
    std::mt19937 rng((unsigned int)time(nullptr) ^ SDL_GetTicks());
    std::shuffle(gRmkPool.begin(), gRmkPool.end(), rng);

    for (int i = 0; i < pCnt; ++i) {
        gRmkSeats[i].hand.assign(gRmkPool.begin(), gRmkPool.begin() + 14);
        gRmkPool.erase(gRmkPool.begin(), gRmkPool.begin() + 14);
        sortRmkHand(gRmkSeats[i].hand);
        gRmkSeats[i].hasBrokenIce = false;
    }
    gRmkPoolCount = (int)gRmkPool.size();
    gRmkTableMelds.clear();
    gRmkTurnSeat = (gRmkRound - 1) % pCnt;
    gRmkWinnerSeat = -1;
    gRmkPhase = "playing";
    gRmkCursor = 0;
    gRmkTurnStartTick = SDL_GetTicks();
    gRmkAiNextTick = SDL_GetTicks() + 1500;
    gScreen = MODE_RMK_TABLE;
    resetRmkWorkspace();
    gStatusBanner = "第 " + std::to_string(gRmkRound) + " 局发牌完成 (" + std::to_string(pCnt) + "人局)！轮到 [" + cleanPeerLabel(gRmkSeats[gRmkTurnSeat].name) + "] 出牌 (需>=30分破冰)";
    broadcastRmkState();
}

static void executeRmkDraw(int seatIdx, const std::string& reason) {
    int pCnt = std::max(2, (int)gRmkSeats.size());
    if (!gRmkPool.empty()) {
        gRmkSeats[seatIdx].hand.push_back(gRmkPool.front());
        gRmkPool.erase(gRmkPool.begin());
        sortRmkHand(gRmkSeats[seatIdx].hand);
        gRmkPoolCount = (int)gRmkPool.size();
    }
    gRmkTurnSeat = (seatIdx + 1) % pCnt;
    gRmkTurnStartTick = SDL_GetTicks();
    gRmkAiNextTick = SDL_GetTicks() + 1500;
    resetRmkWorkspace();
    gStatusBanner = "[" + cleanPeerLabel(gRmkSeats[seatIdx].name) + "] " + reason + " · 轮到 [" + cleanPeerLabel(gRmkSeats[gRmkTurnSeat].name) + "]";
    broadcastRmkState();
}

static void executeRmkCommit(int seatIdx, const std::vector<RmkMeld>& newMelds, const std::set<std::string>& playedIds) {
    int pCnt = std::max(2, (int)gRmkSeats.size());
    gRmkTableMelds = newMelds;
    auto& h = gRmkSeats[seatIdx].hand;
    h.erase(std::remove_if(h.begin(), h.end(), [&](const RmkTile& t) { return playedIds.count(t.id) > 0; }), h.end());
    gRmkSeats[seatIdx].hasBrokenIce = true;
    if (h.empty()) {
        gRmkPhase = "roundOver";
        gRmkWinnerSeat = seatIdx;
        int gain = 0;
        for (int i = 0; i < pCnt; ++i) {
            if (i == seatIdx) continue;
            int pen = 0;
            for (const auto& t : gRmkSeats[i].hand) pen += t.isJoker() ? 30 : t.number;
            gRmkSeats[i].score -= pen;
            gain += pen;
        }
        gRmkSeats[seatIdx].score += gain;
        gStatusBanner = "[" + cleanPeerLabel(gRmkSeats[seatIdx].name) + "] 清空牌架获胜！(+" + std::to_string(gain) + "分) 按[A]下一局";
        broadcastRmkState();
        return;
    }
    gRmkTurnSeat = (seatIdx + 1) % pCnt;
    gRmkTurnStartTick = SDL_GetTicks();
    gRmkAiNextTick = SDL_GetTicks() + 1500;
    resetRmkWorkspace();
    gStatusBanner = "[" + cleanPeerLabel(gRmkSeats[seatIdx].name) + "] 出牌 " + std::to_string(playedIds.size()) + " 张！轮到 [" + cleanPeerLabel(gRmkSeats[gRmkTurnSeat].name) + "]";
    broadcastRmkState();
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
        bool isRmkPkt = (rc.rfind("RMK_", 0) == 0);
        std::string cleanRc = isMjPkt ? rc.substr(3) : (isRmkPkt ? rc.substr(4) : rc);
        if (cleanRc != gRoomCode) continue;

        if (kind == "roomRoster") {
            int mp = MiniJson::getInt(raw, "maxPlayers", 0);
            if (isRmkPkt && mp >= 2 && mp <= 4) gRmkRoomPlayerCount = mp;
            auto rObjs = MiniJson::extractObjectsArray(raw, "roomPeers");
            if (!rObjs.empty()) {
                gRoomPeers.clear();
                for (const auto& ro : rObjs) {
                    std::string pn = MiniJson::getStr(ro, "name");
                    int pc = MiniJson::getInt(ro, "charId", 1);
                    std::string pd = cleanPeerLabel(MiniJson::getStr(ro, "displayName", pn));
                    if (!pn.empty()) gRoomPeers.push_back({pn, pc, pd});
                }
                rebuildLobbySeats();
                std::string hostDisp = cleanPeerLabel(gRoomPeers.front().displayName);
                int cap = isMjPkt ? 4 : (isRmkPkt ? gRmkRoomPlayerCount : 3);
                if (gIsRoomAuthority) {
                    gStatusBanner = "您是房主 (当前 " + std::to_string(gRoomPeers.size()) + "/" + std::to_string(cap) + " 人)";
                } else {
                    gStatusBanner = "已加入房间 " + gRoomCode + " (当前 " + std::to_string(gRoomPeers.size()) + "/" + std::to_string(cap) + " 人) · 房主: " + hostDisp;
                }
            }
        } else if (kind == "joinRequest") {
            int maxP = isMjPkt ? 4 : (isRmkPkt ? gRmkRoomPlayerCount : 3);
            std::string cleanSender = cleanPeerLabel(sender);
            bool exists = false;
            for (auto& rp : gRoomPeers) {
                if (rp.name == sender) {
                    rp.charId = senderChar;
                    rp.displayName = cleanSender;
                    exists = true;
                }
            }
            if (!exists && (int)gRoomPeers.size() < maxP) {
                gRoomPeers.push_back({sender, senderChar, cleanSender});
                rebuildLobbySeats();
                gStatusBanner = "跨平台玩家 [" + cleanSender + "] 已加入房间 " + gRoomCode + " (自动替换AI座位)！";
            }
            if (gIsRoomAuthority) {
                broadcastRoomRoster();
                if (gSelectedGame == 0) broadcastDdzState();
                else if (gSelectedGame == 1) broadcastMjState();
                else broadcastRmkState();
            }
        } else if (kind == "leaveRoom") {
            std::string cleanSender = cleanPeerLabel(sender);
            gRoomPeers.erase(std::remove_if(gRoomPeers.begin(), gRoomPeers.end(), [&](const RoomPeer& p) {
                return p.name == sender;
            }), gRoomPeers.end());
            rebuildLobbySeats();
            gStatusBanner = "玩家 [" + cleanSender + "] 已离开房间";
        } else if (kind == "bidAction" && gIsRoomAuthority && !isMjPkt && !isRmkPkt) {
            int bid = MiniJson::getInt(raw, "bidScore", 0);
            handleDdzBid(gDdzTurnSeat, bid);
        } else if (kind == "passAction" && gIsRoomAuthority && !isMjPkt && !isRmkPkt) {
            handleDdzPass(gDdzTurnSeat);
        } else if (kind == "playCardsAction" && gIsRoomAuthority && !isMjPkt && !isRmkPkt) {
            auto cardObjs = MiniJson::extractObjectsArray(raw, "playedCards");
            std::vector<DdzCard> played;
            for (const auto& co : cardObjs) played.push_back(DdzCard::fromJson(co));
            DdzEvalHand ev = DdzEvaluator::evaluate(played);
            if (ev.category != "invalid") executeDdzPlay(gDdzTurnSeat, ev);
        } else if (kind == "discardAction" && gIsRoomAuthority && isMjPkt) {
            std::string tid = MiniJson::getStr(raw, "tileId");
            executeMjDiscard(gMjTurnSeat, tid);
        } else if (kind == "drawTileAction" && gIsRoomAuthority && isRmkPkt) {
            executeRmkDraw(gRmkTurnSeat, "摸牌过");
        } else if (kind == "commitTurnAction" && gIsRoomAuthority && isRmkPkt) {
            auto mObjs = MiniJson::extractObjectsArray(raw, "tableMelds");
            std::vector<RmkMeld> nms;
            for (const auto& mo : mObjs) {
                RmkMeld m; m.id = MiniJson::getStr(mo, "id");
                auto tObjs = MiniJson::extractObjectsArray(mo, "tiles");
                for (const auto& to : tObjs) m.tiles.push_back(RmkTile::fromJson(to));
                nms.push_back(m);
            }
            std::set<std::string> pids;
            size_t pPos = raw.find("\"committedHandIds\"");
            if (pPos != std::string::npos) {
                size_t lb = raw.find('[', pPos), rb = raw.find(']', lb);
                if (lb != std::string::npos && rb != std::string::npos) {
                    std::string sub = raw.substr(lb + 1, rb - lb - 1);
                    size_t q1 = 0;
                    while ((q1 = sub.find('"', q1)) != std::string::npos) {
                        size_t q2 = sub.find('"', q1 + 1);
                        if (q2 == std::string::npos) break;
                        pids.insert(sub.substr(q1 + 1, q2 - q1 - 1));
                        q1 = q2 + 1;
                    }
                }
            }
            executeRmkCommit(gRmkTurnSeat, nms, pids);
        } else if (kind == "stateSync") {
            std::string hostName = MiniJson::getStr(raw, "hostPeerName");
            gIsRoomAuthority = (hostName == gMyPeerName);
            std::string banner = sanitizeForSwitchFont(MiniJson::getStr(raw, "statusBanner"));
            if (!banner.empty()) gStatusBanner = banner;

            auto rObjs = MiniJson::extractObjectsArray(raw, "roomPeers");
            if (!rObjs.empty()) {
                gRoomPeers.clear();
                for (const auto& ro : rObjs) {
                    std::string pn = MiniJson::getStr(ro, "name");
                    int pc = MiniJson::getInt(ro, "charId", 1);
                    std::string pd = cleanPeerLabel(MiniJson::getStr(ro, "displayName", pn));
                    if (!pn.empty()) gRoomPeers.push_back({pn, pc, pd});
                }
            }

            if (isRmkPkt) {
                gSelectedGame = 2;
                gRmkPhase = MiniJson::getStr(raw, "phase", gRmkPhase);
                gRmkTurnSeat = MiniJson::getInt(raw, "currentTurnSeat", gRmkTurnSeat);
                gRmkPoolCount = MiniJson::getInt(raw, "poolCount", gRmkPoolCount);
                gRmkRound = MiniJson::getInt(raw, "currentRound", gRmkRound);
                auto sObjs = MiniJson::extractObjectsArray(raw, "seats");
                if (sObjs.size() >= 2 && sObjs.size() <= 4) {
                    gRmkRoomPlayerCount = (int)sObjs.size();
                    gRmkSeats.resize(gRmkRoomPlayerCount);
                    for (int i = 0; i < gRmkRoomPlayerCount; ++i) {
                        gRmkSeats[i].id = i;
                        gRmkSeats[i].name = cleanPeerLabel(MiniJson::getStr(sObjs[i], "name", gRmkSeats[i].name));
                        gRmkSeats[i].characterId = MiniJson::getInt(sObjs[i], "characterId", 1);
                        gRmkSeats[i].isAI = MiniJson::getBool(sObjs[i], "isAI", false);
                        gRmkSeats[i].peerDisplayName = MiniJson::getStr(sObjs[i], "peerDisplayName");
                        gRmkSeats[i].hasBrokenIce = MiniJson::getBool(sObjs[i], "hasBrokenIce", false);
                        gRmkSeats[i].score = MiniJson::getInt(sObjs[i], "score", 1000);
                        if (gRmkSeats[i].peerDisplayName == gMyPeerName) gRmkMySeat = i;
                        auto hObjs = MiniJson::extractObjectsArray(sObjs[i], "hand");
                        gRmkSeats[i].hand.clear();
                        for (const auto& to : hObjs) gRmkSeats[i].hand.push_back(RmkTile::fromJson(to));
                    }
                }
                auto mObjs = MiniJson::extractObjectsArray(raw, "tableMelds");
                gRmkTableMelds.clear();
                for (const auto& mo : mObjs) {
                    RmkMeld m; m.id = MiniJson::getStr(mo, "id");
                    auto tObjs = MiniJson::extractObjectsArray(mo, "tiles");
                    for (const auto& to : tObjs) m.tiles.push_back(RmkTile::fromJson(to));
                    gRmkTableMelds.push_back(m);
                }
                gRmkTurnStartTick = SDL_GetTicks();
                resetRmkWorkspace();
                if (gRmkPhase != "lobby") gScreen = MODE_RMK_TABLE;
                else if (gScreen == MODE_RMK_TABLE) gScreen = MODE_LOBBY;
            } else if (!isMjPkt) {
                gSelectedGame = 0;
                gDdzPhase = MiniJson::getStr(raw, "phase", gDdzPhase);
                gDdzTurnSeat = MiniJson::getInt(raw, "currentTurnSeat", gDdzTurnSeat);
                gDdzHighestBid = MiniJson::getInt(raw, "highestBid", gDdzHighestBid);
                gDdzMultiplier = MiniJson::getInt(raw, "multiplier", gDdzMultiplier);
                gDdzLastPlaySeat = MiniJson::getInt(raw, "lastPlaySeat", gDdzLastPlaySeat);
                gDdzWinnerSeat = MiniJson::getInt(raw, "winnerSeat", gDdzWinnerSeat);
                gDdzRound = MiniJson::getInt(raw, "currentRound", gDdzRound);
                gDdzTotalRounds = MiniJson::getInt(raw, "totalRounds", gDdzTotalRounds);
                gDdzBaseScore = MiniJson::getInt(raw, "baseScore", gDdzBaseScore);
                gDdzTurnLimit = MiniJson::getInt(raw, "turnTimeLimit", gDdzTurnLimit);
                gDdzTurnStartTick = SDL_GetTicks();

                auto hcObjs = MiniJson::extractObjectsArray(raw, "holeCards");
                if (!hcObjs.empty()) {
                    gDdzHoleCards.clear();
                    for (const auto& ho : hcObjs) gDdzHoleCards.push_back(DdzCard::fromJson(ho));
                }
                auto seatObjs = MiniJson::extractObjectsArray(raw, "seats");
                if (seatObjs.size() == 3) {
                    for (int i = 0; i < 3; ++i) {
                        gDdzSeats[i].name = cleanPeerLabel(MiniJson::getStr(seatObjs[i], "name", gDdzSeats[i].name));
                        gDdzSeats[i].characterId = MiniJson::getInt(seatObjs[i], "characterId", 1);
                        gDdzSeats[i].isAI = MiniJson::getBool(seatObjs[i], "isAI", false);
                        gDdzSeats[i].peerDisplayName = MiniJson::getStr(seatObjs[i], "peerDisplayName");
                        gDdzSeats[i].isLandlord = MiniJson::getBool(seatObjs[i], "isLandlord", false);
                        gDdzSeats[i].lastActionText = sanitizeForSwitchFont(MiniJson::getStr(seatObjs[i], "lastActionText"));
                        gDdzSeats[i].score = MiniJson::getInt(seatObjs[i], "score", 1000);
                        if (gDdzSeats[i].peerDisplayName == gMyPeerName) gDdzMySeat = i;

                        auto hObjs = MiniJson::extractObjectsArray(seatObjs[i], "hand");
                        gDdzSeats[i].hand.clear();
                        for (const auto& co : hObjs) gDdzSeats[i].hand.push_back(DdzCard::fromJson(co));

                        auto lpObjs = MiniJson::extractObjectsArray(seatObjs[i], "lastPlayedCards");
                        gDdzSeats[i].lastPlayedCards.clear();
                        for (const auto& co : lpObjs) gDdzSeats[i].lastPlayedCards.push_back(DdzCard::fromJson(co));
                    }
                    if (gDdzCursor >= (int)gDdzSeats[gDdzMySeat].hand.size()) {
                        gDdzCursor = std::max(0, (int)gDdzSeats[gDdzMySeat].hand.size() - 1);
                    }
                }
                if (gDdzPhase != "lobby") gScreen = MODE_DDZ_TABLE;
                else if (gScreen == MODE_DDZ_TABLE) gScreen = MODE_LOBBY;
            } else {
                gSelectedGame = 1;
                gMjPhase = MiniJson::getStr(raw, "phase", gMjPhase);
                gMjTurnSeat = MiniJson::getInt(raw, "currentTurnSeat", gMjTurnSeat);
                gMjWallCount = MiniJson::getInt(raw, "wallCount", gMjWallCount);
                gMjWinnerSeat = MiniJson::getInt(raw, "winnerSeat", gMjWinnerSeat);
                gMjWinReason = sanitizeForSwitchFont(MiniJson::getStr(raw, "winReason", gMjWinReason));
                gMjDrawnTileId = MiniJson::getStr(raw, "drawnTileId", "");
                gMjRound = MiniJson::getInt(raw, "currentRound", gMjRound);
                gMjTotalRounds = MiniJson::getInt(raw, "totalRounds", gMjTotalRounds);
                gMjBaseScore = MiniJson::getInt(raw, "baseScore", gMjBaseScore);
                gMjTurnLimit = MiniJson::getInt(raw, "turnTimeLimit", gMjTurnLimit);
                gMjTurnStartTick = SDL_GetTicks();

                auto seatObjs = MiniJson::extractObjectsArray(raw, "seats");
                if (seatObjs.size() == 4) {
                    for (int i = 0; i < 4; ++i) {
                        gMjSeats[i].name = cleanPeerLabel(MiniJson::getStr(seatObjs[i], "name", gMjSeats[i].name));
                        gMjSeats[i].characterId = MiniJson::getInt(seatObjs[i], "characterId", 1);
                        gMjSeats[i].isAI = MiniJson::getBool(seatObjs[i], "isAI", false);
                        gMjSeats[i].peerDisplayName = MiniJson::getStr(seatObjs[i], "peerDisplayName");
                        gMjSeats[i].score = MiniJson::getInt(seatObjs[i], "score", 1000);
                        gMjSeats[i].isDealer = MiniJson::getBool(seatObjs[i], "isDealer", false);
                        gMjSeats[i].lastActionText = sanitizeForSwitchFont(MiniJson::getStr(seatObjs[i], "lastActionText"));
                        if (gMjSeats[i].peerDisplayName == gMyPeerName) gMjMySeat = i;

                        auto hObjs = MiniJson::extractObjectsArray(seatObjs[i], "hand");
                        gMjSeats[i].hand.clear();
                        for (const auto& to : hObjs) gMjSeats[i].hand.push_back(MjTile::fromJson(to));

                        auto mObjs = MiniJson::extractObjectsArray(seatObjs[i], "melds");
                        gMjSeats[i].melds.clear();
                        for (const auto& mo : mObjs) gMjSeats[i].melds.push_back(MjMeld::fromJson(mo));

                        auto dObjs = MiniJson::extractObjectsArray(seatObjs[i], "discards");
                        gMjSeats[i].discards.clear();
                        for (const auto& to : dObjs) gMjSeats[i].discards.push_back(MjTile::fromJson(to));
                    }
                    if (gMjCursor >= (int)gMjSeats[gMjMySeat].hand.size()) {
                        gMjCursor = std::max(0, (int)gMjSeats[gMjMySeat].hand.size() - 1);
                    }
                }
                // Check pendingClaim for my seat
                std::string claimObj = MiniJson::extractObject(raw, "pendingClaim");
                if (!claimObj.empty() && gMjPhase == "claimWindow") {
                    int claimer = MiniJson::getInt(claimObj, "claimerSeat", -1);
                    if (claimer == gMjMySeat) {
                        gMjHasClaim = true;
                        gMjClaimFromSeat = MiniJson::getInt(claimObj, "fromSeat", 0);
                        gMjCanHu = MiniJson::getBool(claimObj, "canHu", false);
                        gMjCanKong = MiniJson::getBool(claimObj, "canKong", false);
                        gMjCanPong = MiniJson::getBool(claimObj, "canPong", true);
                        std::string tObj = MiniJson::extractObject(claimObj, "tile");
                        if (!tObj.empty()) gMjClaimTile = MjTile::fromJson(tObj);
                    } else {
                        gMjHasClaim = false;
                    }
                } else if (gMjPhase != "claimWindow") {
                    gMjHasClaim = false;
                }

                if (gMjPhase != "lobby") gScreen = MODE_MJ_TABLE;
                else if (gScreen == MODE_MJ_TABLE) gScreen = MODE_LOBBY;
            }
        }
    }
}

// ============================================================================
// High-Res K-ON! Rendering Helpers (Animated Mascots, 3D Cards & Tiles, Badges)
// ============================================================================
static void drawCharAvatar(int charId, int x, int y, int w, int h, bool isActive = false) {
    int cid = (charId >= 1 && charId <= 5) ? charId : 1;
    // Use full desktop mascot sprite sheet (sheet_1..5.png) for live animation!
    SDL_Texture* sheet = getTexture("romfs:/cards/sheet_" + std::to_string(cid) + ".png");
    if (sheet) {
        int fw = (cid >= 4) ? 112 : 96;
        int fh = 96;
        int row = isActive ? 2 : 0;
        int maxCols = isActive ? 6 : 4;
        int col = ((SDL_GetTicks() / (isActive ? 150 : 230)) + cid) % maxCols;
        SDL_Rect src = {col * fw, row * fh, fw, fh};
        SDL_Rect dst = {x, y, w, h};
        SDL_RenderCopy(gRenderer, sheet, &src, &dst);
        return;
    }
    SDL_Texture* tex = getTexture("romfs:/cards/char_" + std::to_string(cid) + ".png");
    if (tex) {
        SDL_Rect dst = {x, y, w, h};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    }
}

static void drawTeaPartyBanner(int x, int y, int w, int h) {
    SDL_Texture* strip = getTexture("romfs:/cards/teaparty_strip.png");
    if (strip) {
        int tick = (SDL_GetTicks() / 260) % 4;
        SDL_Rect src = {tick * 288, 0, 288, 160};
        SDL_Rect dst = {x, y, w, h};
        SDL_RenderCopy(gRenderer, strip, &src, &dst);
    }
}

static void drawPokerCard(const DdzCard& c, int x, int y, int w, int h, bool isCursor, bool isSelected) {
    int drawY = y - (isSelected ? 18 : 0);
    SDL_Texture* baseTex = getTexture("romfs:/cards/poker_front.png");
    if (baseTex) {
        SDL_Rect bDst = {x - 2, drawY - 2, w + 4, h + 4};
        SDL_RenderCopy(gRenderer, baseTex, nullptr, &bDst);
    } else {
        drawRoundedRectFill(x, drawY, w, h, 8, COL_WHITE);
    }

    int headerH = std::max(20, h / 5);
    SDL_Color idxCol = c.isRed() ? SDL_Color{215, 25, 35, 255} : COL_BLACK;
    drawText(gFontSmall, c.rankLabel(), x + 5, drawY + 2, idxCol);
    if (c.rank < 16) {
        int sx = x + (c.rank == 10 ? 28 : 21);
        int sy = drawY + 11;
        SDL_SetRenderDrawColor(gRenderer, idxCol.r, idxCol.g, idxCol.b, 255);
        if (c.suit == "♦") {
            for (int dy = -5; dy <= 5; ++dy) {
                int hw = 5 - std::abs(dy);
                SDL_RenderDrawLine(gRenderer, sx - hw, sy + dy, sx + hw, sy + dy);
            }
        } else if (c.suit == "♥") {
            SDL_Rect l1 = {sx - 4, sy - 4, 4, 4}, l2 = {sx + 1, sy - 4, 4, 4};
            SDL_RenderFillRect(gRenderer, &l1);
            SDL_RenderFillRect(gRenderer, &l2);
            for (int dy = 0; dy <= 5; ++dy) {
                int hw = 5 - dy;
                SDL_RenderDrawLine(gRenderer, sx - hw, sy + dy, sx + hw, sy + dy);
            }
        } else if (c.suit == "♣") {
            SDL_Rect c1 = {sx - 2, sy - 5, 4, 4}, c2 = {sx - 5, sy - 1, 4, 4}, c3 = {sx + 1, sy - 1, 4, 4};
            SDL_RenderFillRect(gRenderer, &c1);
            SDL_RenderFillRect(gRenderer, &c2);
            SDL_RenderFillRect(gRenderer, &c3);
            SDL_RenderDrawLine(gRenderer, sx, sy + 1, sx, sy + 5);
        } else {
            for (int dy = -5; dy <= 1; ++dy) {
                int hw = (dy + 5) * 5 / 6;
                SDL_RenderDrawLine(gRenderer, sx - hw, sy + dy, sx + hw, sy + dy);
            }
            SDL_RenderDrawLine(gRenderer, sx, sy + 1, sx, sy + 5);
            SDL_RenderDrawLine(gRenderer, sx - 2, sy + 5, sx + 2, sy + 5);
        }
    }

    SDL_Texture* tex = getTexture(c.romfsImagePath());
    if (tex) {
        SDL_Rect dst = {x + 3, drawY + headerH, w - 6, h - headerH - 4};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    }

    if (isCursor) {
        drawRoundedRectOutline(x - 3, drawY - 3, w + 6, h + 6, 9, COL_GOLD, 3);
        drawText(gFontSmall, "▲", x + w / 2, drawY + h + 2, COL_GOLD, true);
    } else if (isSelected) {
        drawRoundedRectOutline(x - 1, drawY - 1, w + 2, h + 2, 8, COL_HUMAN_GREEN, 3);
    }
}

static void drawPokerBack(int x, int y, int w, int h) {
    SDL_Texture* tex = getTexture("romfs:/cards/poker_back.png");
    if (tex) {
        SDL_Rect dst = {x, y, w, h};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    } else {
        drawRoundedRectFill(x, y, w, h, 6, COL_CRIMSON);
        drawRoundedRectOutline(x, y, w, h, 6, COL_GOLD, 1);
    }
}

static void drawMahjongTile(const MjTile& t, int x, int y, int w, int h, bool isCursor, bool isSelected, bool isHighlight) {
    int drawY = y - (isSelected ? 16 : 0);
    SDL_Texture* baseTex = getTexture("romfs:/cards/tile_front.png");
    if (baseTex) {
        SDL_Rect bDst = {x - 1, drawY - 1, w + 2, h + 2};
        SDL_RenderCopy(gRenderer, baseTex, nullptr, &bDst);
    } else {
        drawRoundedRectFill(x, drawY, w, h, 6, {252, 249, 240, 255});
    }

    int padX = std::max(2, w / 14);
    int topBevel = std::max(3, h / 14);
    int botPad = std::max(2, h / 18);
    SDL_Texture* tex = getTexture(t.romfsImagePath());
    if (tex) {
        SDL_Rect dst = {x + padX, drawY + topBevel, w - padX * 2, h - topBevel - botPad};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    } else {
        drawText(gFontSmall, t.fullName(), x + w / 2, drawY + h / 3, COL_BLACK, true);
    }
    if (t.isLaizi() && w >= 40) {
        drawRoundedRectFill(x + w - 18, drawY + 2, 16, 15, 4, COL_GOLD);
        drawText(gFontSmall, "赖", x + w - 10, drawY + 1, COL_BLACK, true);
    }
    if (isCursor) {
        drawRoundedRectOutline(x - 2, drawY - 2, w + 4, h + 4, 8, COL_GOLD, 3);
        drawText(gFontSmall, "▲", x + w / 2, drawY + h + 2, COL_GOLD, true);
    } else if (isSelected || isHighlight) {
        drawRoundedRectOutline(x - 1, drawY - 1, w + 2, h + 2, 7, COL_HUMAN_GREEN, 2);
    }
}

static void drawMahjongBack(int x, int y, int w, int h) {
    const char* path = (w > h) ? "romfs:/cards/tile_back_h.png" : "romfs:/cards/tile_back_v.png";
    SDL_Texture* tex = getTexture(path);
    if (tex) {
        SDL_Rect dst = {x, y, w, h};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    } else {
        drawRoundedRectFill(x, y, w, h, 4, {28, 150, 88, 255});
    }
}

// Compact 2-Line Seat Badge (Matches iOS 'mjCompactSeatBadge' 1:1 — Never overflows!)
static void drawCompactSeatBadge(int x, int y, int w, int h, int charId, const std::string& rawName, int score, int tileCount, bool isAI, bool isTurn, bool isDealerOrHost, const std::string& extraRole = "") {
    drawRoundedRectFill(x, y, w, h, 12, {7, 28, 18, 232});
    SDL_Color borderCol = isTurn ? COL_GOLD : (isAI ? SDL_Color{120, 140, 130, 140} : COL_HUMAN_GREEN);
    drawRoundedRectOutline(x, y, w, h, 12, borderCol, isTurn ? 2 : 1);

    int avH = h - 8;
    int avW = std::max(36, avH - 4);
    drawCharAvatar(charId, x + 6, y + 4, avW, avH, isTurn);

    int tx = x + avW + 10;
    // Icon (Crown for Host/Seat0, Gamepad for Human, AI icon for AI)
    std::string cleanN = truncateUtf8(rawName, (w > 220) ? 11 : 8);
    bool isHostName = (cleanN.find("房主") != std::string::npos);
    std::string iconPath = isHostName ? "romfs:/cards/icon_crown.png" : (isAI ? "romfs:/cards/icon_ai.png" : "romfs:/cards/icon_human.png");
    drawImage(iconPath, tx, y + 7, 18, 18);
    drawText(gFontSmall, cleanN, tx + 21, y + 6, COL_WHITE);

    // Line 2: Score + Tile count + Dealer/Role pill
    std::string line2 = std::to_string(score) + "分";
    if (tileCount >= 0) line2 += " · " + std::to_string(tileCount) + "张";
    if (!extraRole.empty()) line2 = extraRole + " · " + line2;
    drawText(gFontSmall, line2, tx, y + 29, isAI ? COL_GOLD : COL_HUMAN_GREEN);

    if (isDealerOrHost) {
        drawRoundedRectFill(x + w - 28, y + 6, 22, 18, 5, COL_CRIMSON);
        drawText(gFontSmall, "庄", x + w - 17, y + 5, COL_WHITE, true);
    }
}

// ============================================================================
// Render Screens
// ============================================================================
static inline bool pointInRect(int px, int py, int x, int y, int w, int h) {
    return px >= x && px <= (x + w) && py >= y && py <= (y + h);
}

static void renderTopBar() {
    drawRoundedRectFill(0, 0, SCREEN_W, 50, 0, {5, 22, 14, 238});
    SDL_SetRenderDrawColor(gRenderer, COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 140);
    SDL_RenderDrawLine(gRenderer, 0, 50, SCREEN_W, 50);

    if (gScreen != MODE_LOBBY) {
        drawRoundedRectFill(16, 9, 142, 32, 16, {12, 42, 26, 240});
        drawRoundedRectOutline(16, 9, 142, 32, 16, COL_GOLD, 1);
        drawText(gFontSmall, "[-] < 退出房间", 87, 15, COL_GOLD, true);
        if (!gIsOnlineRoom || gIsRoomAuthority) {
            drawRoundedRectFill(SCREEN_W - 148, 9, 132, 32, 16, COL_GOLD);
            drawText(gFontSmall, "[ZR] 刷新重开", SCREEN_W - 82, 15, COL_BLACK, true);
        }
    } else {
        drawImage("romfs:/cards/htt_logo.png", 20, 4, 48, 42);
        drawText(gFontSmall, "HTT 轻音部", 74, 16, COL_GOLD);
    }

    drawText(gFontLarge, "放课后茶会 · 放课后棋牌室", SCREEN_W / 2, 10, COL_WHITE, true);

    if (gScreen == MODE_LOBBY) {
        drawRoundedRectFill(SCREEN_W - 138, 9, 122, 32, 16, {12, 42, 26, 240});
        drawRoundedRectOutline(SCREEN_W - 138, 9, 122, 32, 16, COL_GOLD, 1);
        drawText(gFontSmall, "[+] 退出软件", SCREEN_W - 77, 15, COL_GOLD, true);
    }
}

static void renderLobbyScreen() {
    bool wsConn = gWs.isConnected();
    bool inJoinedRoom = gIsOnlineRoom && wsConn;

    // 0. Game Switcher Bar (3 Clean Tabs: NO [L]/[R] labels, NO Aeroplane Chess, Consistent Player Count Brackets!)
    if (inJoinedRoom) {
        SDL_Color bgC = (gSelectedGame == 0) ? COL_CRIMSON : ((gSelectedGame == 1) ? COL_GREEN_BTN : SDL_Color{225, 118, 22, 255});
        drawRoundedRectFill(36, 58, 1208, 44, 12, bgC);
        drawRoundedRectOutline(36, 58, 1208, 44, 12, COL_GOLD, 2);
        const char* ic = (gSelectedGame == 0) ? "romfs:/cards/icon_poker.png" : ((gSelectedGame == 1) ? "romfs:/cards/icon_mahjong.png" : "romfs:/cards/icon_rummikub.png");
        drawImage(ic, 52, 62, 36, 36);
        std::string badge = (gSelectedGame == 0 ? "当前房间：放课后斗地主 (3人)" : (gSelectedGame == 1 ? "当前房间：广东红中麻将 (4人 · 136张)" : ("当前房间：拉密数字牌 (" + std::to_string(gRmkRoomPlayerCount) + "人 · 30分破冰)")));
        drawText(gFontMed, badge, 98, 68, COL_WHITE);
        drawText(gFontMed, "房号: " + gRoomCode, 1224, 68, COL_GOLD, false, true);
    } else {
        drawRoundedRectFill(36, 58, 392, 44, 12, gSelectedGame == 0 ? COL_CRIMSON : COL_PANEL);
        drawRoundedRectOutline(36, 58, 392, 44, 12, gSelectedGame == 0 ? COL_GOLD : COL_GOLD_DIM, gSelectedGame == 0 ? 2 : 1);
        drawImage("romfs:/cards/icon_poker.png", 54, 63, 32, 32);
        drawText(gFontMed, "放课后斗地主 (3人)", 246, 68, COL_WHITE, true);

        drawRoundedRectFill(444, 58, 392, 44, 12, gSelectedGame == 1 ? COL_GREEN_BTN : COL_PANEL);
        drawRoundedRectOutline(444, 58, 392, 44, 12, gSelectedGame == 1 ? COL_GOLD : COL_GOLD_DIM, gSelectedGame == 1 ? 2 : 1);
        drawImage("romfs:/cards/icon_mahjong.png", 462, 63, 32, 32);
        drawText(gFontMed, "广东红中麻将 (4人)", 654, 68, COL_WHITE, true);

        drawRoundedRectFill(852, 58, 392, 44, 12, gSelectedGame == 2 ? SDL_Color{225, 118, 22, 255} : COL_PANEL);
        drawRoundedRectOutline(852, 58, 392, 44, 12, gSelectedGame == 2 ? COL_GOLD : COL_GOLD_DIM, gSelectedGame == 2 ? 2 : 1);
        drawImage("romfs:/cards/icon_rummikub.png", 870, 63, 32, 32);
        drawText(gFontMed, "拉密数字牌 (2-4人)", 1062, 68, COL_WHITE, true);
    }

    // Status Banner (with real Game Icon + Crown Icon, zero '☒' boxes!)
    drawRoundedRectFill(36, 108, 1208, 38, 10, COL_PANEL);
    drawRoundedRectOutline(36, 108, 1208, 38, 10, COL_GOLD, 1);
    const char* bannerIc = (gSelectedGame == 0) ? "romfs:/cards/icon_poker.png" : ((gSelectedGame == 1) ? "romfs:/cards/icon_mahjong.png" : "romfs:/cards/icon_rummikub.png");
    drawImage(bannerIc, 48, 113, 28, 28);
    int bannerTextX = 82;
    if (gIsRoomAuthority && inJoinedRoom) {
        drawImage("romfs:/cards/icon_crown.png", 80, 115, 24, 24);
        bannerTextX = 110;
    }
    drawText(gFontSmall, gStatusBanner, bannerTextX, 118, COL_GOLD);

    // 1. Character Selector + Animated 5-Member After-School Tea Party Stage
    drawRoundedRectFill(36, 152, 1208, 134, 14, COL_PANEL);
    drawRoundedRectOutline(36, 152, 1208, 134, 14, COL_GOLD_DIM, 1);
    drawText(gFontMed, "1. 昵称与轻音部角色 (摇杆/触屏选择)    本机昵称: " + gMyDisplayName, 54, 160, COL_GOLD);

    drawRoundedRectFill(756, 158, 168, 28, 8, COL_BLUE_BTN);
    drawRoundedRectOutline(756, 158, 168, 28, 8, COL_GOLD, 1);
    drawText(gFontSmall, "[ZL] 修改昵称", 840, 163, COL_WHITE, true);

    for (int i = 0; i < 5; ++i) {
        int bx = 52 + i * 178;
        int by = 194;
        bool isSel = (gMyCharId == kCharacters[i].charId);
        bool isFoc = (gLobbyFocus == i);
        drawRoundedRectFill(bx, by, 168, 82, 12, isSel ? COL_CRIMSON : COL_PANEL_INNER);
        if (isFoc) {
            drawRoundedRectOutline(bx - 2, by - 2, 172, 86, 13, COL_WHITE, 3);
            drawRoundedRectOutline(bx, by, 168, 82, 12, COL_GOLD, 2);
        } else {
            drawRoundedRectOutline(bx, by, 168, 82, 12, isSel ? COL_GOLD : COL_GOLD_DIM, isSel ? 2 : 1);
        }
        drawCharAvatar(kCharacters[i].charId, bx + 10, by + 9, 64, 64, isSel || isFoc);
        drawText(gFontMed, kCharacters[i].nameZh, bx + 116, by + 28, COL_WHITE, true);
    }

    // Right side of Card 1: Animated 5-Member After-School Tea Party Stage
    drawRoundedRectFill(950, 158, 280, 120, 12, {12, 44, 28, 235});
    drawRoundedRectOutline(950, 158, 280, 120, 12, COL_GOLD, 1);
    drawTeaPartyBanner(962, 154, 256, 122);

    // 2. Cross-Platform Online Server Card (wss://azusa.online/ddz)
    drawRoundedRectFill(36, 294, 1208, 114, 14, COL_PANEL);
    drawRoundedRectOutline(36, 294, 1208, 114, 14, COL_GOLD_DIM, 1);
    drawText(gFontMed, "2. 跨平台在线联机 (Switch / iOS / Android 互通 · wss://azusa.online/ddz)", 54, 302, COL_GOLD);

    // Room Code Input Box (gLobbyFocus == 5)
    bool focRc = (gLobbyFocus == 5);
    drawRoundedRectFill(54, 338, 360, 56, 12, focRc ? SDL_Color{22, 74, 46, 255} : COL_PANEL_INNER);
    if (focRc) {
        drawRoundedRectOutline(52, 336, 364, 60, 13, COL_WHITE, 3);
        drawRoundedRectOutline(54, 338, 360, 56, 12, COL_GOLD, 2);
    } else {
        drawRoundedRectOutline(54, 338, 360, 56, 12, COL_GOLD, 1);
    }
    std::string rcDisplay = gRoomCode.empty() ? "[Y] 房号: 必填房号 (点击输入)" : ("[Y] 房间号: " + gRoomCode);
    drawText(gFontMed, rcDisplay, 234, 353, gRoomCode.empty() ? COL_GOLD : COL_WHITE, true);

    // Connect / Disconnect Button (gLobbyFocus == 6)
    bool focConn = (gLobbyFocus == 6);
    drawRoundedRectFill(432, 338, 386, 56, 12, wsConn ? COL_BLUE_BTN : COL_GREEN_BTN);
    if (focConn) {
        drawRoundedRectOutline(430, 336, 390, 60, 13, COL_WHITE, 3);
        drawRoundedRectOutline(432, 338, 386, 56, 12, COL_GOLD, 2);
    } else {
        drawRoundedRectOutline(432, 338, 386, 56, 12, COL_GOLD, 1);
    }
    drawText(gFontMed, wsConn ? ("[X] 已连(" + gRoomCode + ") · 按[X]退出房间") : "[X] 连接跨平台联机房间", 625, 353, COL_WHITE, true);

    drawText(gFontSmall, "同房号即与 iOS / Android 同桌对局", 840, 344, COL_CREAM);
    drawText(gFontSmall, "真人进房自动替换轻音部 AI 座位", 840, 368, COL_GOLD);

    // 3. Seat Preview (Supports 2P / 3P / 4P selector for Rummikub!)
    drawRoundedRectFill(36, 416, 1208, 174, 14, COL_PANEL);
    drawRoundedRectOutline(36, 416, 1208, 174, 14, COL_GOLD_DIM, 1);
    int seatCnt = (gSelectedGame == 0) ? 3 : ((gSelectedGame == 1) ? 4 : gRmkRoomPlayerCount);
    drawText(gFontMed, std::string("3. 牌桌座位预览 (1号为房主，不足") + std::to_string(seatCnt) + "人由轻音AI补位，真人进房自动替换AI)", 54, 424, COL_GOLD);

    // If Rummikub is selected, render [2人局] [3人局] [4人局] selector buttons in header!
    if (gSelectedGame == 2) {
        int pCounts[3] = {2, 3, 4};
        for (int idx = 0; idx < 3; ++idx) {
            int cntVal = pCounts[idx];
            int pbx = 918 + idx * 102;
            bool isCntSel = (gRmkRoomPlayerCount == cntVal);
            drawRoundedRectFill(pbx, 421, 94, 28, 8, isCntSel ? SDL_Color{225, 118, 22, 255} : COL_PANEL_INNER);
            drawRoundedRectOutline(pbx, 421, 94, 28, 8, isCntSel ? COL_GOLD : COL_GOLD_DIM, isCntSel ? 2 : 1);
            drawText(gFontSmall, std::to_string(cntVal) + "人局", pbx + 47, 426, COL_WHITE, true);
        }
    }

    int sw = (1172 - (seatCnt - 1) * 14) / seatCnt;
    for (int i = 0; i < seatCnt; ++i) {
        int sx = 54 + i * (sw + 14);
        int sy = 458;
        std::string rawName = (gSelectedGame == 0) ? gDdzSeats[i].name : ((gSelectedGame == 1) ? gMjSeats[i].name : gRmkSeats[i].name);
        std::string sName = truncateUtf8(rawName, (seatCnt <= 3) ? 14 : 10);
        int sChar = (gSelectedGame == 0) ? gDdzSeats[i].characterId : ((gSelectedGame == 1) ? gMjSeats[i].characterId : gRmkSeats[i].characterId);
        bool isAI = (gSelectedGame == 0) ? gDdzSeats[i].isAI : ((gSelectedGame == 1) ? gMjSeats[i].isAI : gRmkSeats[i].isAI);
        int sc = (gSelectedGame == 0) ? gDdzSeats[i].score : ((gSelectedGame == 1) ? gMjSeats[i].score : gRmkSeats[i].score);

        drawRoundedRectFill(sx, sy, sw, 118, 12, COL_PANEL_INNER);
        drawRoundedRectOutline(sx, sy, sw, 118, 12, isAI ? COL_GOLD_DIM : COL_HUMAN_GREEN, isAI ? 1 : 2);

        drawCharAvatar(sChar, sx + 10, sy + 18, 68, 76, !isAI);

        std::string roleIcon = (i == 0 && !isAI) ? "romfs:/cards/icon_crown.png" : (isAI ? "romfs:/cards/icon_ai.png" : "romfs:/cards/icon_human.png");
        drawImage(roleIcon, sx + 84, sy + 18, 22, 22);
        drawText(gFontMed, sName, sx + 110, sy + 16, COL_WHITE);

        drawImage(isAI ? "romfs:/cards/icon_ai.png" : "romfs:/cards/icon_human.png", sx + 84, sy + 52, 18, 18);
        drawText(gFontSmall, isAI ? "AI 补位" : "真人玩家", sx + 106, sy + 51, isAI ? COL_GOLD : COL_HUMAN_GREEN);

        drawText(gFontSmall, "积分: " + std::to_string(sc) + " 分", sx + 84, sy + 82, COL_CREAM);
    }

    // 4. Bottom Start Button (gLobbyFocus == 7 — ZERO '☒' boxes, dynamically measured icon + text so it NEVER overlaps!)
    bool canStart = !wsConn || gIsRoomAuthority;
    bool focStart = (gLobbyFocus == 7);
    SDL_Color btnBg = canStart ? (focStart ? COL_CRIMSON_HI : COL_CRIMSON_DIM) : SDL_Color{85, 92, 90, 230};
    drawRoundedRectFill(36, 600, 1208, 68, 14, btnBg);
    if (focStart) {
        drawRoundedRectOutline(33, 597, 1214, 74, 16, COL_WHITE, 3);
        drawRoundedRectOutline(36, 600, 1208, 68, 14, COL_GOLD, 3);
        // Clean Left & Right Highlight Badges (with real PNG icon instead of '▶'/'◀'!)
        drawRoundedRectFill(54, 616, 136, 36, 10, COL_GOLD);
        drawImage("romfs:/cards/icon_crown.png", 62, 623, 20, 20);
        drawText(gFontSmall, "当前选中", 132, 624, COL_BLACK, true);

        drawRoundedRectFill(1090, 616, 136, 36, 10, COL_GOLD);
        drawText(gFontSmall, "按 [A] 确认", 1158, 624, COL_BLACK, true);
    } else {
        drawRoundedRectOutline(36, 600, 1208, 68, 14, COL_GOLD_DIM, 1);
    }

    std::string startTxt = canStart
        ? (std::string("[A] 立即开始") + (gSelectedGame == 0 ? "放课后斗地主 (3人 · 底分100)" : (gSelectedGame == 1 ? "广东红中麻将 (4人 · 底分100)" : ("拉密数字牌 (" + std::to_string(gRmkRoomPlayerCount) + "人 · 30分破冰)"))))
        : "等待 1 号房主开始对局...";
    const char* startIc = (gSelectedGame == 0) ? "romfs:/cards/icon_poker.png" : ((gSelectedGame == 1) ? "romfs:/cards/icon_mahjong.png" : "romfs:/cards/icon_rummikub.png");

    int txtW = 0, txtH = 0;
    if (gFontLarge) TTF_SizeUTF8(gFontLarge, sanitizeForSwitchFont(startTxt).c_str(), &txtW, &txtH);
    int totalGroupW = 38 + 12 + txtW;
    int groupStartX = (SCREEN_W - totalGroupW) / 2;
    drawImage(startIc, groupStartX, 615, 38, 38);
    drawText(gFontLarge, startTxt, groupStartX + 50, 618, focStart ? COL_WHITE : COL_CREAM, false);
}

static void renderDoudizhuTable() {
    // Status Banner
    drawRoundedRectFill(20, 56, 1240, 34, 10, COL_PANEL);
    drawRoundedRectOutline(20, 56, 1240, 34, 10, COL_GOLD, 1);
    drawImage("romfs:/cards/icon_poker.png", 30, 59, 28, 28);
    drawText(gFontSmall, gStatusBanner, 66, 63, COL_GOLD);

    // Hole Cards + Multiplier + Counter Toggle
    drawRoundedRectFill(20, 96, 250, 56, 10, COL_PANEL);
    drawRoundedRectOutline(20, 96, 250, 56, 10, COL_GOLD_DIM, 1);
    drawText(gFontSmall, "底牌:", 32, 114, COL_CREAM);
    for (size_t i = 0; i < gDdzHoleCards.size(); ++i) {
        if (gDdzPhase == "bidding") drawPokerBack(84 + (int)i * 44, 100, 36, 48);
        else drawPokerCard(gDdzHoleCards[i], 84 + (int)i * 44, 100, 36, 48, false, false);
    }
    drawRoundedRectFill(282, 104, 86, 40, 10, COL_CRIMSON);
    drawRoundedRectOutline(282, 104, 86, 40, 10, COL_GOLD, 1);
    drawText(gFontMed, "x" + std::to_string(gDdzMultiplier), 325, 112, COL_GOLD, true);

    drawRoundedRectFill(1110, 104, 150, 40, 10, gDdzShowCounter ? COL_GOLD : COL_PANEL);
    drawRoundedRectOutline(1110, 104, 150, 40, 10, COL_GOLD, 1);
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
            drawRoundedRectFill(bx, 158, 78, 38, 8, COL_PANEL);
            drawRoundedRectOutline(bx, 158, 78, 38, 8, COL_GOLD_DIM, 1);
            drawText(gFontSmall, labels[idx], bx + 39, 160, idx <= 2 ? COL_GOLD : COL_CREAM, true);
            drawText(gFontSmall, std::to_string(rem), bx + 39, 177, rem == 4 ? COL_CRIMSON_HI : (rem == 0 ? COL_GRAY : COL_WHITE), true);
        }
    }

    int leftIdx = (gDdzMySeat + 2) % 3;
    int rightIdx = (gDdzMySeat + 1) % 3;
    const auto& lSeat = gDdzSeats[leftIdx];
    const auto& rSeat = gDdzSeats[rightIdx];
    const auto& me = gDdzSeats[gDdzMySeat];

    // Left Opponent Card
    std::string lRole = (gDdzPhase == "bidding") ? "待叫分" : (lSeat.isLandlord ? "地主" : "农民");
    drawRoundedRectFill(20, 208, 224, 182, 12, COL_PANEL);
    drawRoundedRectOutline(20, 208, 224, 182, 12, gDdzTurnSeat == leftIdx ? COL_GOLD : (lSeat.isAI ? COL_GOLD_DIM : COL_HUMAN_GREEN), 2);
    drawCompactSeatBadge(26, 214, 212, 54, lSeat.characterId, lSeat.name, lSeat.score, -1, lSeat.isAI, gDdzTurnSeat == leftIdx, lSeat.isLandlord, lRole);
    for (int k = 0; k < std::min(6, std::max(1, (int)lSeat.hand.size() / 3)); ++k) {
        drawPokerBack(34 + k * 14, 282, 46, 64);
    }
    drawText(gFontMed, "余 " + std::to_string(lSeat.hand.size()) + " 张", 148, 302, COL_GOLD);

    // Right Opponent Card
    std::string rRole = (gDdzPhase == "bidding") ? "待叫分" : (rSeat.isLandlord ? "地主" : "农民");
    drawRoundedRectFill(1036, 208, 224, 182, 12, COL_PANEL);
    drawRoundedRectOutline(1036, 208, 224, 182, 12, gDdzTurnSeat == rightIdx ? COL_GOLD : (rSeat.isAI ? COL_GOLD_DIM : COL_HUMAN_GREEN), 2);
    drawCompactSeatBadge(1042, 214, 212, 54, rSeat.characterId, rSeat.name, rSeat.score, -1, rSeat.isAI, gDdzTurnSeat == rightIdx, rSeat.isLandlord, rRole);
    for (int k = 0; k < std::min(6, std::max(1, (int)rSeat.hand.size() / 3)); ++k) {
        drawPokerBack(1050 + k * 14, 282, 46, 64);
    }
    drawText(gFontMed, "余 " + std::to_string(rSeat.hand.size()) + " 张", 1164, 302, COL_GOLD);

    // Center 3-Seat Played Cards Area
    if (!lSeat.lastPlayedCards.empty()) {
        for (size_t i = 0; i < lSeat.lastPlayedCards.size(); ++i) {
            drawPokerCard(lSeat.lastPlayedCards[i], 265 + (int)i * 28, 222, 62, 86, false, false);
        }
    } else if (!lSeat.lastActionText.empty()) {
        drawText(gFontMed, "上家: " + lSeat.lastActionText, 270, 250, COL_GOLD);
    }

    if (!rSeat.lastPlayedCards.empty()) {
        int startX = 955 - (int)rSeat.lastPlayedCards.size() * 28;
        for (size_t i = 0; i < rSeat.lastPlayedCards.size(); ++i) {
            drawPokerCard(rSeat.lastPlayedCards[i], startX + (int)i * 28, 222, 62, 86, false, false);
        }
    } else if (!rSeat.lastActionText.empty()) {
        drawText(gFontMed, "下家: " + rSeat.lastActionText, 860, 250, COL_GOLD);
    }

    if (!me.lastPlayedCards.empty()) {
        int startX = SCREEN_W / 2 - ((int)me.lastPlayedCards.size() * 30) / 2;
        for (size_t i = 0; i < me.lastPlayedCards.size(); ++i) {
            drawPokerCard(me.lastPlayedCards[i], startX + (int)i * 30, 322, 64, 88, false, false);
        }
    } else if (!me.lastActionText.empty()) {
        drawText(gFontMed, "我方: " + me.lastActionText, SCREEN_W / 2, 355, COL_GOLD, true);
    }

    // Bottom Seat Badge + Action Bar
    std::string myRole = (gDdzPhase == "bidding") ? "待叫分" : (me.isLandlord ? "地主" : "农民");
    drawCompactSeatBadge(20, 428, 420, 52, me.characterId, me.name, me.score, (int)me.hand.size(), false, gDdzTurnSeat == gDdzMySeat, me.isLandlord, myRole);

    if (gDdzPhase == "bidding" && gDdzTurnSeat == gDdzMySeat) {
        drawRoundedRectFill(456, 428, 804, 52, 12, COL_CRIMSON);
        drawRoundedRectOutline(456, 428, 804, 52, 12, COL_GOLD, 2);
        drawText(gFontMed, "叫地主阶段:   [B] 不叫     [Y] 叫1分     [X] 叫2分     [A] 叫3分", 858, 442, COL_WHITE, true);
    } else if (gDdzPhase == "playing" && gDdzTurnSeat == gDdzMySeat) {
        drawRoundedRectFill(456, 428, 804, 52, 12, COL_GREEN_BTN);
        drawRoundedRectOutline(456, 428, 804, 52, 12, COL_GOLD, 2);
        drawText(gFontMed, "[摇杆/触屏] 选牌   [A] 提起/放下   [Y] 提示   [B] 不出   [X] 出牌", 858, 442, COL_WHITE, true);
    } else if (gDdzPhase == "roundOver") {
        drawRoundedRectFill(456, 428, 804, 52, 12, COL_CRIMSON);
        drawRoundedRectOutline(456, 428, 804, 52, 12, COL_GOLD, 2);
        drawText(gFontMed, "本局结束！按 [A] 再来一局，按 [-] 退出房间返回大厅", 858, 442, COL_WHITE, true);
    } else {
        drawRoundedRectFill(456, 428, 804, 52, 12, COL_PANEL);
        drawRoundedRectOutline(456, 428, 804, 52, 12, COL_GOLD_DIM, 1);
        drawText(gFontMed, "等待 [" + cleanPeerLabel(gDdzSeats[gDdzTurnSeat].name) + "] 操作...", 858, 442, COL_GOLD, true);
    }

    uint32_t elapsed = SDL_GetTicks() - gDdzDealStartTick;
    int visCount = std::min((int)me.hand.size(), std::max(1, (int)(elapsed / 38)));
    if (elapsed > 850) visCount = (int)me.hand.size();

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

    // 1. Top Status Banner (with 3D Hongzhong Mahjong icon + zero '☒' boxes!)
    drawRoundedRectFill(20, 54, 1240, 34, 10, COL_PANEL);
    drawRoundedRectOutline(20, 54, 1240, 34, 10, COL_GOLD, 1);
    drawImage("romfs:/cards/icon_mahjong.png", 30, 57, 28, 28);
    drawText(gFontSmall, gStatusBanner, 66, 61, COL_GOLD);

    // 2. Top Row: Opposite Seat Compact Badge + 3D Standing Tile Wall + Right Wall Counter Pill (1:1 with iOS!)
    const auto& opp = gMjSeats[oppIdx];
    drawCompactSeatBadge(64, 94, 214, 52, opp.characterId, opp.name, opp.score, (int)opp.hand.size(), opp.isAI, gMjTurnSeat == oppIdx, opp.isDealer);
    for (int i = 0; i < std::min(13, (int)opp.hand.size()); ++i) {
        drawMahjongBack(292 + i * 26, 102, 24, 34);
    }

    // Top-Right Wall Stack Pill (Matches iOS '余 75 张 第1局 ⏱ 15s')
    int elapsedSec = (SDL_GetTicks() - gMjTurnStartTick) / 1000;
    int remSec = (gMjTurnLimit > 0) ? std::max(1, gMjTurnLimit - (elapsedSec % gMjTurnLimit)) : 20;
    drawRoundedRectFill(836, 96, 380, 44, 12, COL_PANEL);
    drawRoundedRectOutline(836, 96, 380, 44, 12, COL_GOLD_DIM, 1);
    for (int i = 0; i < 6; ++i) {
        drawMahjongBack(848 + i * 18, 104, 16, 26);
    }
    drawText(gFontSmall, "余 " + std::to_string(gMjWallCount) + " 张   第" + std::to_string(gMjRound) + "局   " + std::to_string(remSec) + "s", 968, 108, COL_GOLD);

    // 3. Left & Right Seats (Vertical 3D Side-Tiles + Non-Overlapping Compact Seat Badges, 1:1 with iOS!)
    const auto& lSeat = gMjSeats[leftIdx];
    for (int i = 0; i < std::min(10, (int)lSeat.hand.size()); ++i) {
        drawMahjongBack(20, 164 + i * 22, 34, 20);
    }
    drawCompactSeatBadge(62, 232, 206, 54, lSeat.characterId, lSeat.name, lSeat.score, (int)lSeat.hand.size(), lSeat.isAI, gMjTurnSeat == leftIdx, lSeat.isDealer);

    const auto& rSeat = gMjSeats[rightIdx];
    for (int i = 0; i < std::min(10, (int)rSeat.hand.size()); ++i) {
        drawMahjongBack(1226, 164 + i * 22, 34, 20);
    }
    drawCompactSeatBadge(1012, 232, 206, 54, rSeat.characterId, rSeat.name, rSeat.score, (int)rSeat.hand.size(), rSeat.isAI, gMjTurnSeat == rightIdx, rSeat.isDealer);

    // 4. Center 4-Direction Wind Compass & Countdown Circle (Matches iOS 1:1 — Zero text collision!)
    int cx = 570, cy = 208, cw = 140, ch = 136;
    drawRoundedRectFill(cx, cy, cw, ch, 16, {7, 40, 48, 242});
    drawRoundedRectOutline(cx, cy, cw, ch, 16, COL_GOLD, 2);

    // Highlight active wind direction with crimson pill (like iOS!)
    auto drawWindLabel = [&](const char* label, int wx, int wy, bool active) {
        if (active) {
            drawRoundedRectFill(wx - 18, wy - 2, 36, 24, 6, COL_CRIMSON);
            drawText(gFontSmall, label, wx, wy + 1, COL_WHITE, true);
        } else {
            drawText(gFontSmall, label, wx, wy + 1, COL_GRAY, true);
        }
    };
    drawWindLabel("北", cx + cw / 2, cy + 8,  gMjTurnSeat == oppIdx);
    drawWindLabel("南", cx + cw / 2, cy + ch - 28, gMjTurnSeat == gMjMySeat);
    drawWindLabel("西", cx + 22,     cy + ch / 2 - 10, gMjTurnSeat == leftIdx);
    drawWindLabel("东", cx + cw - 22, cy + ch / 2 - 10, gMjTurnSeat == rightIdx);

    // Central Countdown Circle
    drawRoundedRectFill(cx + cw / 2 - 26, cy + ch / 2 - 26, 52, 52, 26, {10, 56, 66, 255});
    drawRoundedRectOutline(cx + cw / 2 - 26, cy + ch / 2 - 26, 52, 52, 26, COL_GOLD, 2);
    drawText(gFontMed, std::to_string(remSec), cx + cw / 2, cy + ch / 2 - 12, remSec <= 5 ? COL_CRIMSON_HI : COL_HUMAN_GREEN, true);

    // 5. Four Non-Overlapping Discard Rivers around Center Compass
    int dw = 28, dh = 38;
    // Opposite Discards (Above compass: x=478..802, y=152)
    size_t oppStart = opp.discards.size() > 10 ? opp.discards.size() - 10 : 0;
    for (size_t idx = oppStart; idx < opp.discards.size(); ++idx) {
        int i = (int)(idx - oppStart);
        drawMahjongTile(opp.discards[idx], 490 + i * 30, 156, dw, dh, false, false, idx + 1 == opp.discards.size());
    }

    // Left Discards (Between Left Seat Badge and Compass: x=282..546, 2 rows of 8)
    size_t lStart = lSeat.discards.size() > 16 ? lSeat.discards.size() - 16 : 0;
    for (size_t idx = lStart; idx < lSeat.discards.size(); ++idx) {
        int i = (int)(idx - lStart);
        drawMahjongTile(lSeat.discards[idx], 284 + (i % 8) * 30, 214 + (i / 8) * 42, dw, dh, false, false, idx + 1 == lSeat.discards.size());
    }

    // Right Discards (Between Compass and Right Seat Badge: x=734..998, 2 rows of 8)
    size_t rStart = rSeat.discards.size() > 16 ? rSeat.discards.size() - 16 : 0;
    for (size_t idx = rStart; idx < rSeat.discards.size(); ++idx) {
        int i = (int)(idx - rStart);
        drawMahjongTile(rSeat.discards[idx], 736 + (i % 8) * 30, 214 + (i / 8) * 42, dw, dh, false, false, idx + 1 == rSeat.discards.size());
    }

    // My Own Discards (Below compass: x=460..820, y=354..434, up to 2 rows of 10)
    const auto& me = gMjSeats[gMjMySeat];
    size_t mStart = me.discards.size() > 20 ? me.discards.size() - 20 : 0;
    for (size_t idx = mStart; idx < me.discards.size(); ++idx) {
        int i = (int)(idx - mStart);
        drawMahjongTile(me.discards[idx], 490 + (i % 10) * 30, 354 + (i / 10) * 40, dw, dh, false, false, idx + 1 == me.discards.size());
    }

    // 6. Bottom My Seat Badge + Action Bar (y=446, h=50)
    drawCompactSeatBadge(20, 446, 356, 50, me.characterId, me.name, me.score, (int)me.hand.size(), false, gMjTurnSeat == gMjMySeat, me.isDealer);

    if (gMjPhase == "claimWindow" && gMjHasClaim) {
        drawRoundedRectFill(390, 446, 870, 50, 12, COL_CRIMSON);
        drawRoundedRectOutline(390, 446, 870, 50, 12, COL_GOLD, 2);
        std::string cActs = "响应 [" + gMjClaimTile.fullName() + "]：";
        if (gMjCanHu) cActs += "  [X] 胡牌!";
        if (gMjCanKong) cActs += "  [Y] 明杠";
        else if (gMjCanPong) cActs += "  [Y] 碰牌";
        cActs += "    [B] 过";
        drawText(gFontMed, cActs, 825, 459, COL_WHITE, true);
    } else if (gMjPhase == "playing" && gMjTurnSeat == gMjMySeat) {
        drawRoundedRectFill(390, 446, 870, 50, 12, COL_GREEN_BTN);
        drawRoundedRectOutline(390, 446, 870, 50, 12, COL_GOLD, 2);
        std::string selTxt = (gMjSelectedIdx >= 0 && gMjSelectedIdx < (int)me.hand.size())
            ? ("已选 [" + me.hand[gMjSelectedIdx].fullName() + "] · 按[Y]或点击右侧打出 / 再按[A]取消")
            : "[摇杆/触屏] 选牌   [A] 选中/取消   [Y] 打出选中牌   [X] 自摸胡牌";
        drawText(gFontMed, selTxt, 825, 459, COL_WHITE, true);
    } else if (gMjPhase == "roundOver") {
        drawRoundedRectFill(390, 446, 870, 50, 12, COL_CRIMSON);
        drawRoundedRectOutline(390, 446, 870, 50, 12, COL_GOLD, 2);
        drawText(gFontMed, "本局结束 (" + gMjWinReason + ")！按 [A] 下一局，按 [-] 返回大厅", 825, 459, COL_WHITE, true);
    } else {
        drawRoundedRectFill(390, 446, 870, 50, 12, COL_PANEL);
        drawRoundedRectOutline(390, 446, 870, 50, 12, COL_GOLD_DIM, 1);
        drawText(gFontMed, "等待 [" + cleanPeerLabel(gMjSeats[gMjTurnSeat].name) + "] 摸牌出牌...", 825, 459, COL_GOLD, true);
    }

    // 7. Bottom Row: Visual Melds (碰/明杠/暗杠) + Fixed-Size Large Hand Tiles (62x90) + Drawn-Tile Gap
    int curX = 28;
    for (const auto& m : me.melds) {
        int cnt = (m.kind == "碰") ? 3 : 4;
        for (int k = 0; k < cnt; ++k) {
            if (m.kind == "暗杠" && k != 2) drawMahjongBack(curX, 540, 48, 68);
            else drawMahjongTile(m.tile, curX, 540, 48, 68, false, false, false);
            curX += 50;
        }
        curX += 14;
    }

    uint32_t elapsed = SDL_GetTicks() - gMjDealStartTick;
    int visCount = std::min((int)me.hand.size(), std::max(1, (int)(elapsed / 40)));
    if (elapsed > 750) visCount = (int)me.hand.size();

    int tileW = 62, tileH = 90;
    for (int i = 0; i < visCount; ++i) {
        bool isDrawn = (!gMjDrawnTileId.empty() && me.hand[i].id == gMjDrawnTileId) || (i + 1 == visCount && (visCount % 3 == 2));
        int extraGap = (isDrawn && i + 1 == visCount && visCount > 1) ? 28 : 0;
        drawMahjongTile(me.hand[i], curX + i * (tileW + 4) + extraGap, 526, tileW, tileH,
                        (i == gMjCursor), (i == gMjSelectedIdx), isDrawn);
    }
}


static void drawRmkTileBox(const RmkTile& t, int x, int y, int w, int h, bool isCursor, bool isSel) {
    int dy = y - (isSel ? 16 : 0);
    SDL_Texture* tex = getTexture(t.romfsImagePath());
    if (tex) {
        drawRoundedRectFill(x - 1, dy - 1, w + 2, h + 2, 7, COL_WHITE);
        SDL_Rect dst = {x, dy, w, h};
        SDL_RenderCopy(gRenderer, tex, nullptr, &dst);
    } else {
        drawRoundedRectFill(x, dy, w, h, 8, {252, 247, 235, 255});
        SDL_Color tc = rmkTileColor(t.color);
        drawText(gFontMed, t.isJoker() ? "鬼" : std::to_string(t.number), x + w / 2, dy + 6, tc, true);
        drawText(gFontSmall, t.isJoker() ? "百搭" : t.colorZh(), x + w / 2, dy + h - 22, tc, true);
    }
    if (isCursor) {
        drawRoundedRectOutline(x - 2, dy - 2, w + 4, h + 4, 9, COL_GOLD, 3);
        drawText(gFontSmall, "▲", x + w / 2, dy + h + 1, COL_GOLD, true);
    } else if (isSel) {
        drawRoundedRectOutline(x - 2, dy - 2, w + 4, h + 4, 9, COL_HUMAN_GREEN, 3);
    } else {
        drawRoundedRectOutline(x, dy, w, h, 7, {210, 185, 145, 220}, 1);
    }
}

static void renderRummikubTable() {
    int remSec = std::max(0, 60 - (int)((SDL_GetTicks() - gRmkTurnStartTick) / 1000));
    drawRoundedRectFill(20, 54, 1240, 34, 10, COL_PANEL);
    drawRoundedRectOutline(20, 54, 1240, 34, 10, COL_GOLD, 1);
    drawImage("romfs:/cards/icon_rummikub.png", 30, 57, 28, 28);
    drawText(gFontSmall, gStatusBanner, 66, 61, COL_GOLD);
    drawText(gFontSmall, "牌堆: " + std::to_string(gRmkPoolCount) + "张   限时: " + std::to_string(remSec) + "s", 1244, 61, remSec <= 10 ? COL_CRIMSON_HI : COL_HUMAN_GREEN, false, true);

    // 2..4 Dynamic Seats Row
    int seatCnt = std::max(2, (int)gRmkSeats.size());
    int badgeW = (1240 - (seatCnt - 1) * 12) / seatCnt;
    for (int i = 0; i < seatCnt; ++i) {
        int sx = 20 + i * (badgeW + 12);
        const auto& s = gRmkSeats[i];
        bool iturn = (gRmkTurnSeat == i);
        drawCompactSeatBadge(sx, 94, badgeW, 52, s.characterId, s.name, s.score, (int)s.hand.size(), s.isAI, iturn, (i == 0), s.hasBrokenIce ? "已破冰" : "未破冰");
    }

    // Center Table Melds (with K-ON! Character Rummikub Tiles + Click-to-return in workspace!)
    drawRoundedRectFill(20, 152, 1240, 314, 12, {7, 30, 19, 195});
    drawRoundedRectOutline(20, 152, 1240, 314, 12, COL_GOLD_DIM, 1);
    const auto& melds = gRmkEditing ? gRmkWorkMelds : gRmkTableMelds;
    if (melds.empty()) {
        drawText(gFontMed, "桌面暂无牌组 · 首次破冰需选牌总和 >=30 分后点【放上桌面】", SCREEN_W / 2, 294, COL_CREAM, true);
    } else {
        int mx = 34, my = 164;
        for (size_t i = 0; i < melds.size(); ++i) {
            int mw = (int)melds[i].tiles.size() * 44 + 12;
            if (mx + mw > 1240) { mx = 34; my += 74; }
            if (my > 400) break;
            bool ok = (RmkEvaluator::evaluateMeld(melds[i].tiles) >= 0);
            drawRoundedRectFill(mx, my, mw, 64, 8, {12, 48, 30, 230});
            drawRoundedRectOutline(mx, my, mw, 64, 8, ok ? COL_GOLD : COL_CRIMSON_HI, ok ? 1 : 2);
            for (size_t k = 0; k < melds[i].tiles.size(); ++k) {
                drawRmkTileBox(melds[i].tiles[k], mx + 6 + (int)k * 44, my + 5, 40, 54, false, false);
            }
            mx += mw + 12;
        }
    }

    // 6 Individual Action Boxes (1:1 matching iOS layout: 按数排/按色排 | 提示 | 放上桌面 | 复原 | 摸牌过 | 确认出牌)
    bool myTurn = (gRmkTurnSeat == gRmkMySeat && gRmkPhase == "playing");
    drawRoundedRectFill(20, 472, 1240, 48, 12, COL_PANEL);
    drawRoundedRectOutline(20, 472, 1240, 48, 12, COL_GOLD_DIM, 1);

    if (gRmkPhase == "roundOver") {
        drawRoundedRectFill(28, 476, 1224, 40, 10, COL_CRIMSON);
        drawRoundedRectOutline(28, 476, 1224, 40, 10, COL_GOLD, 2);
        drawText(gFontMed, "本局结束！点击此处或按 [A] 开始下一局，按 [-] 返回大厅", SCREEN_W / 2, 484, COL_WHITE, true);
    } else {
        // Box 1: 按数排 / 按色排 [ZL] (x=28, w=134)
        drawRoundedRectFill(28, 476, 134, 40, 9, {24, 118, 210, 255});
        drawRoundedRectOutline(28, 476, 134, 40, 9, COL_GOLD_DIM, 1);
        drawText(gFontSmall, gRmkSortByColor ? "[ZL] 按色排" : "[ZL] 按数排", 95, 486, COL_WHITE, true);

        // Box 2: 提示 [L] (x=170, w=116)
        drawRoundedRectFill(170, 476, 116, 40, 9, myTurn ? SDL_Color{146, 52, 182, 255} : SDL_Color{75, 82, 80, 200});
        drawRoundedRectOutline(170, 476, 116, 40, 9, COL_GOLD_DIM, 1);
        drawText(gFontSmall, "[L] 提示", 228, 486, COL_WHITE, true);

        // Box 3: 放上桌面 [Y] (x=294, w=150)
        drawRoundedRectFill(294, 476, 150, 40, 9, myTurn ? SDL_Color{235, 132, 18, 255} : SDL_Color{75, 82, 80, 200});
        drawRoundedRectOutline(294, 476, 150, 40, 9, myTurn ? COL_GOLD : COL_GOLD_DIM, 1);
        drawText(gFontSmall, "[Y] 放上桌面", 369, 486, COL_WHITE, true);

        // Box 4: 复原 [R] (x=452, w=116)
        drawRoundedRectFill(452, 476, 116, 40, 9, (myTurn && gRmkEditing) ? SDL_Color{110, 122, 135, 255} : SDL_Color{62, 70, 68, 190});
        drawRoundedRectOutline(452, 476, 116, 40, 9, COL_GOLD_DIM, 1);
        drawText(gFontSmall, "[R] 复原", 510, 486, (myTurn && gRmkEditing) ? COL_WHITE : COL_GRAY, true);

        // Box 5: 摸牌过 [B] (x=576, w=134)
        drawRoundedRectFill(576, 476, 134, 40, 9, myTurn ? SDL_Color{22, 148, 156, 255} : SDL_Color{75, 82, 80, 200});
        drawRoundedRectOutline(576, 476, 134, 40, 9, COL_GOLD_DIM, 1);
        drawText(gFontSmall, "[B] 摸牌过", 643, 486, COL_WHITE, true);

        // Box 6: 确认出牌 [X] (x=718, w=534)
        bool canCommit = (myTurn && gRmkEditing);
        drawRoundedRectFill(718, 476, 534, 40, 9, canCommit ? COL_GREEN_BTN : SDL_Color{45, 72, 58, 210});
        drawRoundedRectOutline(718, 476, 534, 40, 9, canCommit ? COL_GOLD : COL_GOLD_DIM, canCommit ? 2 : 1);
        std::string commitTxt = myTurn ? (gRmkEditing ? "[X] 确认出牌 (完成本回合)" : "请点选牌架上的牌 -> 点【放上桌面】-> 点【确认出牌】") : ("等待 [" + cleanPeerLabel(gRmkSeats[gRmkTurnSeat].name) + "] 出牌...");
        drawText(gFontSmall, commitTxt, 985, 486, canCommit ? COL_WHITE : COL_GOLD, true);
    }

    // Bottom Wooden Rack (牌架) with K-ON! Character Rummikub Tiles
    drawRoundedRectFill(20, 526, 1240, 158, 12, {92, 56, 30, 244});
    drawRoundedRectOutline(20, 526, 1240, 158, 12, COL_GOLD, 2);
    auto& rack = gRmkEditing ? gRmkWorkHand : gRmkSeats[gRmkMySeat].hand;
    int cnt = (int)rack.size();
    int tw = 58, th = 84;
    int step = (cnt > 1) ? std::min(62, (1184 - tw) / (cnt - 1)) : 0;
    for (int i = 0; i < cnt; ++i) {
        drawRmkTileBox(rack[i], 38 + i * step, 568, tw, th, (i == gRmkCursor), rack[i].selected);
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
            std::string discardId = ai.hand.back().id;
            for (int i = (int)ai.hand.size() - 1; i >= 0; --i) {
                if (!ai.hand[i].isLaizi()) { discardId = ai.hand[i].id; break; }
            }
            executeMjDiscard(gMjTurnSeat, discardId);
        }
    }

    if (gScreen == MODE_RMK_TABLE && gRmkPhase == "playing") {
        if (now - gRmkTurnStartTick >= 60000) {
            resetRmkWorkspace();
            executeRmkDraw(gRmkTurnSeat, "60秒超时复原并罚抽1张");
            return;
        }
        if (now >= gRmkAiNextTick && gRmkSeats[gRmkTurnSeat].isAI) {
            auto best = RmkEvaluator::findBestMeld(gRmkSeats[gRmkTurnSeat].hand);
            int pts = best.empty() ? 0 : RmkEvaluator::evaluateMeld(best);
            if (!best.empty() && (gRmkSeats[gRmkTurnSeat].hasBrokenIce || pts >= 30)) {
                auto nm = gRmkTableMelds;
                nm.push_back({"m_" + std::to_string(SDL_GetTicks()), best});
                std::set<std::string> pids;
                for (const auto& t : best) pids.insert(t.id);
                executeRmkCommit(gRmkTurnSeat, nm, pids);
            } else {
                executeRmkDraw(gRmkTurnSeat, "从共用牌堆摸1张牌");
            }
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
    gMyDisplayName = "Switch";
    gMyPeerName = gMyDisplayName + "#" + std::to_string(100 + (rand() % 900));

    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_TIMER);
    IMG_Init(IMG_INIT_JPG | IMG_INIT_PNG);
    TTF_Init();

    gWindow = SDL_CreateWindow("HTT_GameRoom_Switch", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, SCREEN_W, SCREEN_H, SDL_WINDOW_SHOWN);
    gRenderer = SDL_CreateRenderer(gWindow, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

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
    hidInitializeTouchScreen();
    bool wasTouching = false;
    bool wasWsConnected = false;
    uint32_t lastSlideTick = 0;

    bool running = true;
    while (running && appletMainLoop()) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) running = false;
        }

        padUpdate(&pad);
        u64 kDown = padGetButtonsDown(&pad);
        u64 kHeld = padGetButtons(&pad);

        bool nowWsConnected = gWs.isConnected();
        static uint32_t lastJoinHbTick = 0;
        if (nowWsConnected && !wasWsConnected && gIsOnlineRoom) {
            gStatusBanner = "已连接跨平台服务器 azusa.online，房间号: " + gRoomCode + "（等待同房好友或按[A]开始）";
            sendJoinRequestPacket();
            lastJoinHbTick = SDL_GetTicks();
        } else if (!nowWsConnected && wasWsConnected && gIsOnlineRoom) {
            gIsOnlineRoom = false;
            gStatusBanner = "[注意] 服务器连接已断开，请检查网络后按 [X] 重连";
        } else if (nowWsConnected && gIsOnlineRoom && gScreen == MODE_LOBBY && SDL_GetTicks() - lastJoinHbTick > 2500) {
            sendJoinRequestPacket();
            lastJoinHbTick = SDL_GetTicks();
        }
        wasWsConnected = nowWsConnected;

        HidTouchScreenState touchState = {0};
        hidGetTouchScreenStates(&touchState, 1);
        bool isTouchingNow = (touchState.count > 0);
        bool tapped = (isTouchingNow && !wasTouching);
        int tx = isTouchingNow ? (int)touchState.touches[0].x : -1;
        int ty = isTouchingNow ? (int)touchState.touches[0].y : -1;
        wasTouching = isTouchingNow;

        processIncomingNetworkMessages();
        updateAiTurns();

        // Host-only [ZR] / Touch refresh button in active game
        if (gScreen != MODE_LOBBY && (!gIsOnlineRoom || gIsRoomAuthority)) {
            if ((kDown & HidNpadButton_ZR) || (tapped && pointInRect(tx, ty, SCREEN_W - 148, 9, 132, 32))) {
                if (gScreen == MODE_DDZ_TABLE) { gDdzRound++; startNewDoudizhuRound(); }
                else if (gScreen == MODE_MJ_TABLE) { gMjRound++; startNewMahjongRound(); }
                else if (gScreen == MODE_RMK_TABLE) { gRmkRound++; startNewRmkRound(); }
                tapped = false;
            }
        }
        // Touch Top Bar Leave / Exit
        if (tapped && gScreen != MODE_LOBBY && pointInRect(tx, ty, 16, 9, 142, 32)) {
            kDown |= HidNpadButton_Minus;
            tapped = false;
        }
        if (tapped && gScreen == MODE_LOBBY && pointInRect(tx, ty, SCREEN_W - 138, 9, 122, 32)) {
            running = false;
            tapped = false;
        }
        // Touch mapping for Lobby, Doudizhu, Mahjong, and Rummikub
        if (tapped) {
            if (gScreen == MODE_LOBBY) {
                bool inJoinedRoom = gIsOnlineRoom && gWs.isConnected();
                if (!inJoinedRoom && pointInRect(tx, ty, 36, 58, 392, 44)) { gSelectedGame = 0; rebuildLobbySeats(); }
                else if (!inJoinedRoom && pointInRect(tx, ty, 444, 58, 392, 44)) { gSelectedGame = 1; rebuildLobbySeats(); }
                else if (!inJoinedRoom && pointInRect(tx, ty, 852, 58, 392, 44)) { gSelectedGame = 2; rebuildLobbySeats(); }
                else if (gSelectedGame == 2 && pointInRect(tx, ty, 918, 421, 94, 28)) { gRmkRoomPlayerCount = 2; rebuildLobbySeats(); if (gIsRoomAuthority) broadcastRoomRoster(); }
                else if (gSelectedGame == 2 && pointInRect(tx, ty, 1020, 421, 94, 28)) { gRmkRoomPlayerCount = 3; rebuildLobbySeats(); if (gIsRoomAuthority) broadcastRoomRoster(); }
                else if (gSelectedGame == 2 && pointInRect(tx, ty, 1122, 421, 94, 28)) { gRmkRoomPlayerCount = 4; rebuildLobbySeats(); if (gIsRoomAuthority) broadcastRoomRoster(); }
                else if (pointInRect(tx, ty, 756, 158, 168, 28)) kDown |= HidNpadButton_ZL;
                else if (pointInRect(tx, ty, 54, 338, 360, 56)) { gLobbyFocus = 5; kDown |= HidNpadButton_Y; }
                else if (pointInRect(tx, ty, 432, 338, 386, 56)) { gLobbyFocus = 6; kDown |= HidNpadButton_X; }
                else if (pointInRect(tx, ty, 36, 600, 1208, 68)) { gLobbyFocus = 7; kDown |= HidNpadButton_A; }
                else {
                    for (int i = 0; i < 5; ++i) {
                        if (pointInRect(tx, ty, 52 + i * 178, 194, 168, 82)) {
                            gLobbyFocus = i;
                            gMyCharId = kCharacters[i].charId;
                            rebuildLobbySeats();
                            break;
                        }
                    }
                }
            } else if (gScreen == MODE_DDZ_TABLE) {
                if (pointInRect(tx, ty, 1110, 104, 150, 40)) {
                    kDown |= HidNpadButton_R;
                } else if (pointInRect(tx, ty, 456, 428, 804, 52)) {
                    if (gDdzPhase == "bidding") {
                        if (tx < 670) kDown |= HidNpadButton_B;
                        else if (tx < 865) kDown |= HidNpadButton_Y;
                        else if (tx < 1060) kDown |= HidNpadButton_X;
                        else kDown |= HidNpadButton_A;
                    } else if (gDdzPhase == "playing") {
                        if (tx < 760) kDown |= HidNpadButton_Y;
                        else if (tx < 960) kDown |= HidNpadButton_B;
                        else kDown |= HidNpadButton_X;
                    } else if (gDdzPhase == "roundOver") {
                        kDown |= HidNpadButton_A;
                    }
                } else if (ty >= 490) {
                    auto& myHand = gDdzSeats[gDdzMySeat].hand;
                    int cnt = (int)myHand.size();
                    if (cnt > 0) {
                        int cardW = 84;
                        int step = (cnt > 1) ? std::min(52, (1160 - cardW) / (cnt - 1)) : 0;
                        int totalW = cardW + std::max(0, cnt - 1) * step;
                        int startX = (SCREEN_W - totalW) / 2;
                        for (int i = cnt - 1; i >= 0; --i) {
                            int cx = startX + i * step;
                            if (tx >= cx && tx <= cx + cardW) {
                                gDdzCursor = i;
                                myHand[i].selected = !myHand[i].selected;
                                break;
                            }
                        }
                    }
                }
            } else if (gScreen == MODE_MJ_TABLE) {
                if (pointInRect(tx, ty, 390, 446, 870, 50)) {
                    if (gMjPhase == "claimWindow") {
                        if (tx < 680) kDown |= HidNpadButton_X;
                        else if (tx < 980) kDown |= HidNpadButton_Y;
                        else kDown |= HidNpadButton_B;
                    } else if (gMjPhase == "playing") {
                        if (tx > 1050) kDown |= HidNpadButton_X;
                        else kDown |= HidNpadButton_Y;
                    } else if (gMjPhase == "roundOver") {
                        kDown |= HidNpadButton_A;
                    }
                } else if (ty >= 510) {
                    auto& myHand = gMjSeats[gMjMySeat].hand;
                    int cnt = (int)myHand.size();
                    int curX = 28;
                    for (const auto& m : gMjSeats[gMjMySeat].melds) {
                        curX += ((m.kind == "碰") ? 3 : 4) * 50 + 14;
                    }
                    int tileW = 62;
                    for (int i = cnt - 1; i >= 0; --i) {
                        bool isDrawn = (!gMjDrawnTileId.empty() && myHand[i].id == gMjDrawnTileId) || (i + 1 == cnt && (cnt % 3 == 2));
                        int extraGap = (isDrawn && i + 1 == cnt && cnt > 1) ? 28 : 0;
                        int mx = curX + i * (tileW + 4) + extraGap;
                        if (tx >= mx && tx <= mx + tileW) {
                            gMjCursor = i;
                            if (gMjPhase == "playing" && gMjTurnSeat == gMjMySeat) {
                                if (gMjSelectedIdx == i) gMjSelectedIdx = -1;
                                else gMjSelectedIdx = i;
                            }
                            break;
                        }
                    }
                }
            } else if (gScreen == MODE_RMK_TABLE) {
                if (gRmkPhase == "roundOver" && pointInRect(tx, ty, 20, 472, 1240, 48)) {
                    kDown |= HidNpadButton_A;
                } else if (pointInRect(tx, ty, 28, 476, 134, 40)) {
                    kDown |= HidNpadButton_ZL; // 按数排 / 按色排
                } else if (pointInRect(tx, ty, 170, 476, 116, 40)) {
                    kDown |= HidNpadButton_L;  // 提示
                } else if (pointInRect(tx, ty, 294, 476, 150, 40)) {
                    kDown |= HidNpadButton_Y;  // 放上桌面
                } else if (pointInRect(tx, ty, 452, 476, 116, 40)) {
                    kDown |= HidNpadButton_R;  // 复原
                } else if (pointInRect(tx, ty, 576, 476, 134, 40)) {
                    kDown |= HidNpadButton_B;  // 摸牌过
                } else if (pointInRect(tx, ty, 718, 476, 534, 40)) {
                    kDown |= HidNpadButton_X;  // 确认出牌
                } else if (ty >= 526) {
                    // Touch on bottom Rummikub rack tiles!
                    auto& rack = gRmkEditing ? gRmkWorkHand : gRmkSeats[gRmkMySeat].hand;
                    int cnt = (int)rack.size();
                    if (cnt > 0) {
                        int tw = 58;
                        int step = (cnt > 1) ? std::min(62, (1184 - tw) / (cnt - 1)) : 0;
                        for (int i = cnt - 1; i >= 0; --i) {
                            int rx = 38 + i * step;
                            if (tx >= rx && tx <= rx + tw) {
                                gRmkCursor = i;
                                rack[i].selected = !rack[i].selected;
                                break;
                            }
                        }
                    }
                } else if (pointInRect(tx, ty, 20, 152, 1240, 314) && gRmkPhase == "playing" && gRmkTurnSeat == gRmkMySeat && gRmkSeats[gRmkMySeat].hasBrokenIce) {
                    // Touch on table meld tile after Icebreak -> pick up to rack for rearrange!
                    if (!gRmkEditing) {
                        gRmkSnapHand = gRmkSeats[gRmkMySeat].hand;
                        gRmkWorkHand = gRmkSnapHand;
                        gRmkSnapMelds = gRmkTableMelds;
                        gRmkWorkMelds = gRmkSnapMelds;
                        gRmkEditing = true;
                    }
                    int mx = 34, my = 164;
                    bool hit = false;
                    for (size_t i = 0; i < gRmkWorkMelds.size() && !hit; ++i) {
                        int mw = (int)gRmkWorkMelds[i].tiles.size() * 44 + 12;
                        if (mx + mw > 1240) { mx = 34; my += 74; }
                        for (size_t k = 0; k < gRmkWorkMelds[i].tiles.size(); ++k) {
                            int trx = mx + 6 + (int)k * 44;
                            if (pointInRect(tx, ty, trx, my + 5, 40, 54)) {
                                RmkTile picked = gRmkWorkMelds[i].tiles[k];
                                picked.selected = true;
                                gRmkWorkMelds[i].tiles.erase(gRmkWorkMelds[i].tiles.begin() + k);
                                if (gRmkWorkMelds[i].tiles.empty()) gRmkWorkMelds.erase(gRmkWorkMelds.begin() + i);
                                gRmkWorkHand.push_back(picked);
                                gStatusBanner = "已从桌面取回1张牌重组（回合结束前桌面所有牌组须满3张合法）";
                                hit = true;
                                break;
                            }
                        }
                        mx += mw + 12;
                    }
                }
            }
        }

        if (gScreen == MODE_LOBBY) {
            if (kDown & HidNpadButton_Plus) {
                running = false;
            }
            if (!gIsOnlineRoom || !gWs.isConnected()) {
                if (kDown & HidNpadButton_L) { gSelectedGame = (gSelectedGame + 2) % 3; rebuildLobbySeats(); }
                if (kDown & HidNpadButton_R) { gSelectedGame = (gSelectedGame + 1) % 3; rebuildLobbySeats(); }
            }
            if (kDown & HidNpadButton_ZL) {
                openSwitchNicknameKeyboard();
                rebuildLobbySeats();
            }
            if (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) {
                if (gLobbyFocus <= 4) {
                    gLobbyFocus = (gLobbyFocus + 4) % 5;
                    gMyCharId = kCharacters[gLobbyFocus].charId;
                    rebuildLobbySeats();
                } else if (gLobbyFocus == 6) {
                    gLobbyFocus = 5;
                }
            }
            if (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) {
                if (gLobbyFocus <= 4) {
                    gLobbyFocus = (gLobbyFocus + 1) % 5;
                    gMyCharId = kCharacters[gLobbyFocus].charId;
                    rebuildLobbySeats();
                } else if (gLobbyFocus == 5) {
                    gLobbyFocus = 6;
                }
            }
            if (kDown & (HidNpadButton_Up | HidNpadButton_StickLUp)) {
                if (gLobbyFocus == 7) gLobbyFocus = 5;
                else if (gLobbyFocus == 5 || gLobbyFocus == 6) gLobbyFocus = std::max(0, std::min(4, gMyCharId - 1));
            }
            if (kDown & (HidNpadButton_Down | HidNpadButton_StickLDown)) {
                if (gLobbyFocus <= 4) gLobbyFocus = 5;
                else if (gLobbyFocus == 5 || gLobbyFocus == 6) gLobbyFocus = 7;
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
                    gStatusBanner = "已退出在线房间，恢复单人+轻音AI模式";
                } else {
                    if (gRoomCode.empty()) {
                        openSwitchRoomCodeKeyboard();
                    }
                    if (gRoomCode.empty()) {
                        gStatusBanner = "[注意] 请先按 [Y] 填写房间号后再连接！";
                    } else {
                        gIsOnlineRoom = true;
                        gRoomPeers.clear();
                        gRoomPeers.push_back({gMyPeerName, gMyCharId, gMyDisplayName});
                        rebuildLobbySeats();
                        gWs.connectToRelay("azusa.online", "443", "/ddz");
                        gStatusBanner = "正在连接跨平台服务器 azusa.online，房间号: " + gRoomCode + "...";
                    }
                }
            }
            if (kDown & HidNpadButton_A) {
                if (gLobbyFocus == 5) openSwitchRoomCodeKeyboard();
                else if (gLobbyFocus == 6) {
                    if (gWs.isConnected()) {
                        std::string leavePkt = "{\"kind\":\"leaveRoom\",\"roomCode\":\"" + MiniJson::esc(wireRoomCode()) +
                                               "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                               "\",\"senderCharId\":" + std::to_string(gMyCharId) + "}";
                        gWs.sendText(leavePkt);
                        gWs.disconnect();
                        gIsOnlineRoom = false;
                        gRoomPeers.clear();
                        rebuildLobbySeats();
                        gStatusBanner = "已退出在线房间，恢复单人+轻音AI模式";
                    } else {
                        if (gRoomCode.empty()) openSwitchRoomCodeKeyboard();
                        if (!gRoomCode.empty()) {
                            gIsOnlineRoom = true;
                            gRoomPeers.clear();
                            gRoomPeers.push_back({gMyPeerName, gMyCharId, gMyDisplayName});
                            rebuildLobbySeats();
                            gWs.connectToRelay("azusa.online", "443", "/ddz");
                            gStatusBanner = "正在连接跨平台服务器 azusa.online，房间号: " + gRoomCode + "...";
                        }
                    }
                } else {
                    if (gSelectedGame == 0) startNewDoudizhuRound();
                    else if (gSelectedGame == 1) startNewMahjongRound();
                    else startNewRmkRound();
                }
            }
        } else if (gScreen == MODE_DDZ_TABLE) {
            auto& myHand = gDdzSeats[gDdzMySeat].hand;
            if (kDown & HidNpadButton_Minus) {
                gDdzPhase = "lobby";
                gScreen = MODE_LOBBY;
                gStatusBanner = "已退出房间返回大厅";
            }
            if (kDown & HidNpadButton_R) {
                gDdzShowCounter = !gDdzShowCounter;
            }
            uint32_t nowT = SDL_GetTicks();
            bool slideLeft = (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) || ((kHeld & (HidNpadButton_Left | HidNpadButton_StickLLeft)) && nowT - lastSlideTick > 110);
            bool slideRight = (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) || ((kHeld & (HidNpadButton_Right | HidNpadButton_StickLRight)) && nowT - lastSlideTick > 110);
            if (slideLeft && !myHand.empty()) {
                gDdzCursor = (gDdzCursor + (int)myHand.size() - 1) % (int)myHand.size();
                lastSlideTick = nowT;
            } else if (slideRight && !myHand.empty()) {
                gDdzCursor = (gDdzCursor + 1) % (int)myHand.size();
                lastSlideTick = nowT;
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
                        gStatusBanner = "[注意] 所选牌型不符合斗地主规则！";
                    } else if (!freeLead && !DdzEvaluator::canBeat(ev, gDdzLastValid)) {
                        gStatusBanner = "[注意] 所选牌型管不上上家的牌！";
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
                gStatusBanner = "已退出麻将房间返回大厅";
            }
            uint32_t nowT = SDL_GetTicks();
            bool slideLeft = (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) || ((kHeld & (HidNpadButton_Left | HidNpadButton_StickLLeft)) && nowT - lastSlideTick > 110);
            bool slideRight = (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) || ((kHeld & (HidNpadButton_Right | HidNpadButton_StickLRight)) && nowT - lastSlideTick > 110);
            if (slideLeft && !myHand.empty()) {
                gMjCursor = (gMjCursor + (int)myHand.size() - 1) % (int)myHand.size();
                lastSlideTick = nowT;
            } else if (slideRight && !myHand.empty()) {
                gMjCursor = (gMjCursor + 1) % (int)myHand.size();
                lastSlideTick = nowT;
            }
            if (gMjPhase == "claimWindow" && gMjHasClaim) {
                if ((kDown & HidNpadButton_Y) && (gMjCanKong || gMjCanPong)) {
                    if (gIsOnlineRoom && !gIsRoomAuthority) {
                        std::string act = gMjCanKong ? "kong" : "pong";
                        std::string pkt = "{\"kind\":\"claimAction\",\"roomCode\":\"MJ_" + MiniJson::esc(gRoomCode) +
                                          "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                          "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                                          ",\"actionType\":\"" + act + "\"}";
                        gWs.sendText(pkt);
                        gMjHasClaim = false;
                    } else {
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
                            gStatusBanner = "已碰 [" + gMjClaimTile.fullName() + "]！请点选一张手牌按 [Y] 打出";
                            broadcastMjState();
                        }
                    }
                } else if (kDown & HidNpadButton_B) {
                    if (gIsOnlineRoom && !gIsRoomAuthority) {
                        std::string pkt = "{\"kind\":\"claimAction\",\"roomCode\":\"MJ_" + MiniJson::esc(gRoomCode) +
                                          "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                          "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                                          ",\"actionType\":\"pass\"}";
                        gWs.sendText(pkt);
                        gMjHasClaim = false;
                    } else {
                        gMjHasClaim = false;
                        drawMjTileForSeat((gMjClaimFromSeat + 1) % 4);
                    }
                }
            } else if (gMjPhase == "playing" && gMjTurnSeat == gMjMySeat) {
                if (kDown & HidNpadButton_A) {
                    if (gMjSelectedIdx == gMjCursor) gMjSelectedIdx = -1;
                    else gMjSelectedIdx = gMjCursor;
                }
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
                if (kDown & HidNpadButton_X) {
                    if (MjEvaluator::canHu(myHand, (int)gMjSeats[gMjMySeat].melds.size())) {
                        if (gIsOnlineRoom && !gIsRoomAuthority) {
                            std::string pkt = "{\"kind\":\"selfAction\",\"roomCode\":\"MJ_" + MiniJson::esc(gRoomCode) +
                                              "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) +
                                              "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                                              ",\"actionType\":\"selfHu\"}";
                            gWs.sendText(pkt);
                        } else {
                            executeMjWin(gMjMySeat, -1, "自摸胡牌");
                        }
                    } else {
                        gStatusBanner = "[注意] 当前手牌尚未满足胡牌牌型！";
                    }
                }
            } else if (gMjPhase == "roundOver") {
                if (kDown & HidNpadButton_A) {
                    gMjRound++;
                    startNewMahjongRound();
                }
            }
        } else if (gScreen == MODE_RMK_TABLE) {
            if (kDown & HidNpadButton_Minus) {
                gRmkPhase = "lobby";
                gScreen = MODE_LOBBY;
                gStatusBanner = "已退出拉密数字牌房间返回大厅";
            }
            if (kDown & HidNpadButton_ZL) {
                gRmkSortByColor = !gRmkSortByColor;
                sortRmkHand(gRmkSeats[gRmkMySeat].hand);
                if (gRmkEditing) sortRmkHand(gRmkWorkHand);
            }
            auto& rack = gRmkEditing ? gRmkWorkHand : gRmkSeats[gRmkMySeat].hand;
            uint32_t nowT = SDL_GetTicks();
            bool slideL = (kDown & (HidNpadButton_Left | HidNpadButton_StickLLeft)) || ((kHeld & (HidNpadButton_Left | HidNpadButton_StickLLeft)) && nowT - lastSlideTick > 110);
            bool slideR = (kDown & (HidNpadButton_Right | HidNpadButton_StickLRight)) || ((kHeld & (HidNpadButton_Right | HidNpadButton_StickLRight)) && nowT - lastSlideTick > 110);
            if (slideL && !rack.empty()) { gRmkCursor = (gRmkCursor + (int)rack.size() - 1) % (int)rack.size(); lastSlideTick = nowT; }
            if (slideR && !rack.empty()) { gRmkCursor = (gRmkCursor + 1) % (int)rack.size(); lastSlideTick = nowT; }

            if (gRmkPhase == "roundOver" && (kDown & HidNpadButton_A)) {
                gRmkRound++;
                startNewRmkRound();
            } else if (gRmkPhase == "playing" && gRmkTurnSeat == gRmkMySeat) {
                if (kDown & HidNpadButton_A && gRmkCursor >= 0 && gRmkCursor < (int)rack.size()) {
                    rack[gRmkCursor].selected = !rack[gRmkCursor].selected;
                }
                if (kDown & HidNpadButton_L) {
                    selectRmkHintForMe();
                }
                if (kDown & HidNpadButton_R) {
                    resetRmkWorkspace();
                    gStatusBanner = "已复原牌架与桌面";
                }
                if (kDown & HidNpadButton_Y) {
                    if (!gRmkEditing) {
                        gRmkSnapHand = gRmkSeats[gRmkMySeat].hand;
                        gRmkWorkHand = gRmkSnapHand;
                        gRmkSnapMelds = gRmkTableMelds;
                        gRmkWorkMelds = gRmkSnapMelds;
                        gRmkEditing = true;
                    }
                    std::vector<RmkTile> picked;
                    for (const auto& t : gRmkWorkHand) if (t.selected) picked.push_back(t);
                    if (RmkEvaluator::evaluateMeld(picked) >= 0) {
                        gRmkWorkHand.erase(std::remove_if(gRmkWorkHand.begin(), gRmkWorkHand.end(), [](const RmkTile& t){ return t.selected; }), gRmkWorkHand.end());
                        gRmkWorkMelds.push_back({"m_" + std::to_string(SDL_GetTicks()), picked});
                        gRmkCursor = std::min(gRmkCursor, std::max(0, (int)gRmkWorkHand.size() - 1));
                        gStatusBanner = "已暂放牌组到桌面，点击【确认出牌】或按 [X] 完成出牌！";
                    } else {
                        gStatusBanner = "[注意] 所选牌未能组成有效顺组或群组 (需>=3张)";
                    }
                }
                if (kDown & HidNpadButton_B) {
                    resetRmkWorkspace();
                    if (gIsOnlineRoom && !gIsRoomAuthority) {
                        gWs.sendText("{\"kind\":\"drawTileAction\",\"roomCode\":\"RMK_" + MiniJson::esc(gRoomCode) +
                                     "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) + "\",\"senderCharId\":" + std::to_string(gMyCharId) + "}");
                    } else {
                        executeRmkDraw(gRmkMySeat, "摸牌结束回合");
                    }
                }
                if (kDown & HidNpadButton_X && gRmkEditing) {
                    std::set<std::string> remIds;
                    for (const auto& t : gRmkWorkHand) remIds.insert(t.id);
                    std::set<std::string> playedIds;
                    for (const auto& t : gRmkSnapHand) if (!remIds.count(t.id)) playedIds.insert(t.id);
                    bool allOk = !playedIds.empty();
                    for (const auto& m : gRmkWorkMelds) if (RmkEvaluator::evaluateMeld(m.tiles) < 0) allOk = false;
                    if (!gRmkSeats[gRmkMySeat].hasBrokenIce) {
                        int icePts = 0;
                        for (size_t i = gRmkSnapMelds.size(); i < gRmkWorkMelds.size(); ++i) {
                            int p = RmkEvaluator::evaluateMeld(gRmkWorkMelds[i].tiles);
                            if (p > 0) icePts += p;
                        }
                        if (icePts < 30) { allOk = false; gStatusBanner = "[注意] 破冰总分需 >=30 分！(当前 " + std::to_string(icePts) + " 分)"; }
                    }
                    if (allOk) {
                        if (gIsOnlineRoom && !gIsRoomAuthority) {
                            std::string mArr = "[";
                            for (size_t i = 0; i < gRmkWorkMelds.size(); ++i) { if (i > 0) mArr += ","; mArr += gRmkWorkMelds[i].toJson(); }
                            mArr += "]";
                            std::string pArr = "[";
                            bool first = true;
                            for (const auto& pid : playedIds) { if (!first) pArr += ","; first = false; pArr += "\"" + MiniJson::esc(pid) + "\""; }
                            pArr += "]";
                            gWs.sendText("{\"kind\":\"commitTurnAction\",\"roomCode\":\"RMK_" + MiniJson::esc(gRoomCode) +
                                         "\",\"senderPeerName\":\"" + MiniJson::esc(gMyPeerName) + "\",\"senderCharId\":" + std::to_string(gMyCharId) +
                                         ",\"tableMelds\":" + mArr + ",\"committedHandIds\":" + pArr + "}");
                            gRmkEditing = false;
                        } else {
                            executeRmkCommit(gRmkMySeat, gRmkWorkMelds, playedIds);
                        }
                    }
                }
            }
        }

        // Render Frame with High-Res K-ON! Velvet & Star Background
        SDL_Color bg = (gSelectedGame == 0) ? COL_BG_DDZ : COL_BG_MJ;
        SDL_SetRenderDrawColor(gRenderer, bg.r, bg.g, bg.b, 255);
        SDL_RenderClear(gRenderer);

        drawImage((gScreen == MODE_LOBBY) ? "romfs:/cards/ui_bg_lobby.jpg" : "romfs:/cards/ui_bg_table.jpg", 0, 0, SCREEN_W, SCREEN_H);

        renderTopBar();
        if (gScreen == MODE_LOBBY) renderLobbyScreen();
        else if (gScreen == MODE_DDZ_TABLE) renderDoudizhuTable();
        else if (gScreen == MODE_MJ_TABLE) renderMahjongTable();
        else if (gScreen == MODE_RMK_TABLE) renderRummikubTable();

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
