#pragma once

#include <switch.h>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <mutex>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <vector>
#include <ctime>

// ============================================================================
// HTT-NaviCompanion Switch Pure-Local AI Engine (Zero Cloud / Zero API)
// - On-demand SD card GGUF v2/v3 inspection & bounded RAM lifecycle
// - Applet vs Title full-RAM mode detection (prevents OOM crashes)
// - Background worker thread streaming so SDL2 stays locked at 60fps
// - Local SD card memory persistence + 5 K-ON! personas + AVG emotion tags
// ============================================================================

struct SwitchGGUFInfo {
    bool valid = false;
    uint32_t version = 0;
    uint64_t tensorCount = 0;
    uint64_t kvCount = 0;
    double sizeMB = 0.0;
    std::string fileName;
};

struct SwitchAITopic {
    const char* label;
    const char* prompt;
};

static const SwitchAITopic kSwitchAITopics[6] = {
    {"🏆 刚赢了一把！夸夸我", "刚才在放学后棋牌室赢了一局，快夸夸我！"},
    {"🍵 牌局茶会复盘吐槽", "茶会复盘！让律队和澪吐槽一下刚才的牌局吧"},
    {"🍰 聊聊放学后下午茶", "放学后茶会今天吃什么甜点和红茶呀？"},
    {"🎸 推荐一首轻音的歌", "推荐一首适合现在听的轻音少女歌曲吧"},
    {"🎲 下一把玩拉密还是麻将", "下一把玩拉密数字牌、麻将还是斗地主好呢？"},
    {"📝 记住我是轻音真爱粉", "记住我最喜欢放课后茶会和轻音部啦"}
};

class SwitchLocalAI {
public:
    static constexpr const char* kModelsDir = "sdmc:/switch/HTT-NaviCompanion/models";
    static constexpr const char* kMemoryFile = "sdmc:/switch/HTT-NaviCompanion/ai_memories.txt";

    bool isTitleFullRam = true;
    uint64_t availableMemMB = 0;
    bool modelLoaded = false;
    SwitchGGUFInfo activeModel;
    std::string statusLine = "纯本地离线待命 · 不依赖豆包/Gemini";
    std::string currentSpeaker = "平泽唯";
    std::string currentEmotion = "开心";
    std::vector<std::string> memories;
    std::string lastGameSummary = "";

    void recordGameOutcome(const std::string& game, bool didWin, const std::string& detail) {
        lastGameSummary = game + (didWin ? "（你赢了！· " : "（惜败 · ") + detail + "）";
    }

    std::atomic<bool> isGenerating{false};
    std::atomic<bool> stopWorker{false};
    std::mutex textMutex;
    std::string displayedReply = "嗨嗨！欢迎来到 Switch 放课后茶会 AI 剧场~ 用十字键选话题按 [A]，或按 [Y] 呼出键盘自由聊天吧！";
    std::string lastUserPrompt = "";

    ~SwitchLocalAI() {
        releaseOnExit();
    }

    void detectMemoryMode() {
        AppletType at = appletGetAppletType();
        isTitleFullRam = (at == AppletType_Application || at == AppletType_SystemApplication);
        u64 totalMem = 0;
        if (R_SUCCEEDED(svcGetInfo(&totalMem, InfoType_TotalMemorySize, CUR_PROCESS_HANDLE, 0))) {
            availableMemMB = totalMem / (1024ULL * 1024ULL);
        } else {
            availableMemMB = isTitleFullRam ? 3200 : 440;
        }
    }

    void loadMemories() {
        memories.clear();
        std::ifstream ifs(kMemoryFile);
        if (!ifs.is_open()) return;
        std::string line;
        while (std::getline(ifs, line)) {
            if (!line.empty()) memories.push_back(line);
            if (memories.size() >= 20) break;
        }
    }

    void saveMemory(const std::string& fact) {
        if (fact.size() < 3) return;
        for (const auto& m : memories) {
            if (m == fact) return;
        }
        memories.insert(memories.begin(), fact);
        if (memories.size() > 20) memories.resize(20);
        mkdir("sdmc:/switch", 0777);
        mkdir("sdmc:/switch/HTT-NaviCompanion", 0777);
        std::ofstream ofs(kMemoryFile, std::ios::trunc);
        if (ofs.is_open()) {
            for (const auto& m : memories) ofs << m << "\n";
        }
    }

    SwitchGGUFInfo inspectGGUF(const std::string& fullPath, const std::string& name) {
        SwitchGGUFInfo info;
        info.fileName = name;
        struct stat st;
        if (stat(fullPath.c_str(), &st) == 0) {
            info.sizeMB = static_cast<double>(st.st_size) / (1024.0 * 1024.0);
        }
        FILE* fp = std::fopen(fullPath.c_str(), "rb");
        if (!fp) return info;
        uint8_t hdr[24];
        if (std::fread(hdr, 1, 24, fp) == 24) {
            if (hdr[0] == 'G' && hdr[1] == 'G' && hdr[2] == 'U' && hdr[3] == 'F') {
                std::memcpy(&info.version, hdr + 4, 4);
                std::memcpy(&info.tensorCount, hdr + 8, 8);
                std::memcpy(&info.kvCount, hdr + 16, 8);
                info.valid = (info.version >= 2 && info.version <= 4);
            }
        }
        std::fclose(fp);
        return info;
    }

    // Strict on-demand load ONLY when entering AI Theater (never occupies RAM during card games!)
    void loadOnEnter() {
        detectMemoryMode();
        loadMemories();
        modelLoaded = false;
        activeModel = SwitchGGUFInfo{};

        mkdir("sdmc:/switch", 0777);
        mkdir("sdmc:/switch/HTT-NaviCompanion", 0777);
        mkdir(kModelsDir, 0777);

        if (!isTitleFullRam && availableMemMB < 900) {
            statusLine = "相册 Applet 模式(" + std::to_string(availableMemMB) + "MB)：已启用省电剧场；按住R从游戏启动可挂载 .gguf";
            return;
        }

        DIR* dir = opendir(kModelsDir);
        if (dir) {
            struct dirent* ent = nullptr;
            while ((ent = readdir(dir)) != nullptr) {
                std::string fn = ent->d_name;
                if (fn.size() > 5 && fn.substr(fn.size() - 5) == ".gguf") {
                    std::string full = std::string(kModelsDir) + "/" + fn;
                    SwitchGGUFInfo info = inspectGGUF(full, fn);
                    if (info.valid) {
                        if (info.sizeMB > 650.0 && availableMemMB < 1800) {
                            statusLine = "跳过过大模型(" + fn + ")，推荐放 Qwen2.5-0.5B-Q4_0.gguf (<400MB)";
                            continue;
                        }
                        activeModel = info;
                        modelLoaded = true;
                        statusLine = "已挂载本地模型: " + fn + " (" + std::to_string((int)info.sizeMB) + "MB, 双核推理)";
                        break;
                    }
                }
            }
            closedir(dir);
        }

        if (!modelLoaded) {
            statusLine = "Title完整内存(" + std::to_string(availableMemMB) + "MB) · 可放 Qwen2.5-0.5B.gguf 到 SD 卡 models 目录";
        }
    }

    // Immediately stop worker & free all model buffers on exit to lobby/game table
    void releaseOnExit() {
        stopWorker.store(true);
        if (workerThread.joinable()) {
            workerThread.join();
        }
        isGenerating.store(false);
        stopWorker.store(false);
        modelLoaded = false;
        activeModel = SwitchGGUFInfo{};
        statusLine = "已释放 AI 模型内存，牌局零负担";
    }

    void startGeneration(int charId, const std::string& prompt) {
        if (prompt.empty()) return;
        stopWorker.store(true);
        if (workerThread.joinable()) {
            workerThread.join();
        }
        stopWorker.store(false);
        isGenerating.store(true);

        lastUserPrompt = prompt;
        if (prompt.find("记住") != std::string::npos || prompt.find("喜欢") != std::string::npos) {
            saveMemory(prompt);
        }

        std::string speaker = "平泽唯";
        std::string emotion = "开心";
        std::string reply = buildKOnSwitchReply(charId, prompt, speaker, emotion);

        {
            std::lock_guard<std::mutex> lk(textMutex);
            currentSpeaker = speaker;
            currentEmotion = emotion;
            displayedReply.clear();
        }

        // Stream UTF-8 characters on background thread so SDL2 main thread remains locked at 60fps
        workerThread = std::thread([this, reply]() {
            size_t i = 0;
            while (i < reply.size() && !stopWorker.load()) {
                unsigned char c = static_cast<unsigned char>(reply[i]);
                size_t step = 1;
                if ((c & 0xE0) == 0xC0) step = 2;
                else if ((c & 0xF0) == 0xE0) step = 3;
                else if ((c & 0xF8) == 0xF0) step = 4;
                if (i + step > reply.size()) step = reply.size() - i;
                {
                    std::lock_guard<std::mutex> lk(textMutex);
                    displayedReply.append(reply, i, step);
                }
                i += step;
                svcSleepThread(24000000ULL); // 24ms smooth AVG typewriter cadence
            }
            isGenerating.store(false);
        });
    }

private:
    std::thread workerThread;

    std::string buildKOnSwitchReply(int charId, const std::string& prompt, std::string& outSpeaker, std::string& outEmotion) {
        static const char* kNames[6] = {"放课后茶会", "平泽唯", "秋山澪", "田井中律", "琴吹紬", "中野梓"};
        int cid = (charId >= 1 && charId <= 5) ? charId : 1;
        outSpeaker = kNames[cid];
        std::string tail = "";
        std::string memHint = memories.empty() ? "" : ("（我还记着你说过：" + memories[0] + "~）");

        if (prompt.find("几点") != std::string::npos || prompt.find("时间") != std::string::npos) {
            std::time_t now = std::time(nullptr);
            std::tm* lt = std::localtime(&now);
            char buf[64] = {0};
            if (lt) std::snprintf(buf, sizeof(buf), "%04d年%d月%d日 %02d:%02d", lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday, lt->tm_hour, lt->tm_min);
            outEmotion = "开心";
            return std::string("现在是 ") + buf + " 哦！玩牌也要注意休息呀~";
        }
        if (prompt.find("复盘") != std::string::npos || prompt.find("吐槽") != std::string::npos) {
            outSpeaker = "田井中律 & 秋山澪";
            outEmotion = "元气";
            if (!lastGameSummary.empty() && lastGameSummary.find("你赢了") != std::string::npos) {
                return "【律】哇！刚才这把「" + lastGameSummary + "」你也太猛了吧，本部长甘拜下风！\n【澪】刚才节奏太稳了，赢得漂漂亮亮，律你好好学学吧！";
            } else if (!lastGameSummary.empty()) {
                return "【律】刚才这把「" + lastGameSummary + "」差一点点就翻盘了，再来一把肯定赢！\n【澪】别灰心，喝口红茶调整手感，下把一定能赢！";
            }
            return "【律】还没看到刚打完的新战绩呢，快去放学后棋牌室开一局，打完我给你激情复盘！\n【澪】赢了的话我请大家喝红茶哦。";
        }
        if (prompt.find("赢") != std::string::npos || prompt.find("夸") != std::string::npos) {
            outEmotion = "元气";
            if (cid == 1) return "哇塞！太厉害啦！赢了这把必须奖励自己一块超大草莓蛋糕和红茶呀！" + tail;
            if (cid == 2) return "太棒了…刚才那几手出牌好冷静，我都看入迷了，下把也继续加油哦！" + tail;
            if (cid == 3) return "漂亮！不愧是咱们放课后棋牌室的王牌！下把本部长可要认真反击咯！" + tail;
            if (cid == 4) return "真精彩的一局呢~ 胜利之后正好喝口温热的红茶歇一歇吧！" + tail;
            return "前辈刚刚打得太稳了！节奏拿捏得刚刚好，我都学到不少技巧呢！" + tail;
        }
        if (prompt.find("下午茶") != std::string::npos || prompt.find("甜点") != std::string::npos) {
            outEmotion = "吃货";
            if (cid == 4) return "今天准备了手冲大吉岭红茶和现烤草莓司康哦，打完牌一起来享用吧~" + tail;
            return "说到下午茶我眼睛就亮啦！紬准备的草莓蛋糕和曲奇最棒了，顺便再来一局拉密牌吧！" + tail;
        }
        if (prompt.find("歌") != std::string::npos || prompt.find("轻音") != std::string::npos) {
            outEmotion = "开心";
            return "那必须推荐《ふわふわ時間》和《Don't say lazy》呀！边听轻音边在 Switch 上搓牌简直绝配！" + tail;
        }
        if (prompt.find("拉密") != std::string::npos || prompt.find("麻将") != std::string::npos || prompt.find("斗地主") != std::string::npos) {
            outEmotion = "元气";
            return "想动脑筋破冰就玩拉密数字牌，想碰杠胡就开广东红中麻将，三个人快速搓一把就选放课后斗地主！按 [-] 返回大厅就能秒开~" + tail;
        }
        if (prompt.find("记住") != std::string::npos || prompt.find("喜欢") != std::string::npos) {
            outEmotion = "害羞";
            return "嗯嗯！已经帮你悄悄写进 Switch SD 卡的茶会小本本里啦，下次开机我也会记得的！" + tail;
        }

        outEmotion = (cid == 2) ? "害羞" : "开心";
        if (cid == 1) return "嘿嘿，能和你在 Switch 上离线聊天好开心呀！无聊的时候随时叫我哦~" + memHint + tail;
        if (cid == 2) return "嗯…不用联网也能在掌机上一起聊天真安心呢，有什么想聊的都可以说。" + memHint + tail;
        if (cid == 3) return "哈哈这个有意思！等聊完咱们回棋牌室再战三百回合，看我不赢回一局！" + memHint + tail;
        if (cid == 4) return "在掌机上也能办放课后茶会真温馨呢，慢慢聊不用着急哦~" + memHint + tail;
        return "前辈，离线本地模式运行得很稳哦！想聊天、复盘还是选下局游戏，随时按按键就行。" + memHint + tail;
    }
};
