import SwiftUI
import UniformTypeIdentifiers

struct KOnAIChatSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @ObservedObject var musicManager = KOnMusicManager.shared
    @ObservedObject var llm = KOnLocalLLMManager.shared
    @Environment(\.dismiss) private var dismiss

    var onOpenGameRoom: () -> Void

    @State private var selectedTab: Int = 0
    @State private var inputText: String = ""
    @State private var showFileImporter: Bool = false

    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httGold = Color(red: 0.88, green: 0.72, blue: 0.38)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    private let darkBg = Color(red: 0.08, green: 0.09, blue: 0.13)
    private let cardBg = Color(red: 0.13, green: 0.15, blue: 0.20)

    var body: some View {
        NavigationView {
            ZStack {
                darkBg.ignoresSafeArea()
                VStack(spacing: 8) {
                    // Top Tab Switcher
                    HStack(spacing: 8) {
                        tabButton(title: "🍵 茶会副驾对话", idx: 0)
                        tabButton(title: "⚙️ 本地模型与记忆", idx: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    if selectedTab == 0 {
                        chatTabView
                    } else {
                        modelManagerTabView
                    }
                }
            }
            .navigationTitle("放课后茶会 · AI 副驾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { llm.enableVoiceBroadcast.toggle() }) {
                        Image(systemName: llm.enableVoiceBroadcast ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundColor(llm.enableVoiceBroadcast ? httGold : .gray)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(httGold)
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .onAppear {
            llm.onRequestOpenGameRoom = {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onOpenGameRoom()
                }
            }
            if !llm.activeModelFileName.isEmpty && !llm.activeModelLoaded {
                llm.loadModelIntoMemory(fileName: llm.activeModelFileName)
            }
        }
        .onDisappear {
            // Release mapped model buffer on close to protect navigation & game room RAM
            llm.unloadModelFromMemory(silent: true)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.data, UTType.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                llm.importLocalGGUF(from: first)
            }
        }
    }

    private func tabButton(title: String, idx: Int) -> some View {
        Button(action: { selectedTab = idx }) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selectedTab == idx ? httCrimson : cardBg)
                .foregroundColor(selectedTab == idx ? .white : httCream.opacity(0.8))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedTab == idx ? httGold : Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    // MARK: - Tab 0: K-ON! Co-Pilot Chat
    private var chatTabView: some View {
        VStack(spacing: 8) {
            // Live Context Bar (Character + Emotion + Speed + Music + Accent)
            HStack(spacing: 8) {
                Text("[\(manager.selectedCharacter.displayName(.zhHans)) · \(llm.currentEmotionTag)]")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(httGold)
                Spacer()
                Text("\(Int(manager.currentSpeedKmh)) km/h")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Button(action: {
                    llm.ttsAccent = (llm.ttsAccent == .mandarin) ? .cantonese : .mandarin
                }) {
                    Text("播报:\(llm.ttsAccent.label)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(httCream)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cardBg)
            .cornerRadius(10)
            .padding(.horizontal, 12)

            // Quick Co-Pilot Command Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quickChip("🚗 路况汇报", "汇报一下当前路况和还有多久到")
                    quickChip("🍵 茶会复盘", "茶会复盘！吐槽一下刚才的牌局")
                    quickChip("🎸 切一首轻音", "切歌，放下一首轻音歌")
                    quickChip("☕ 找附近咖啡馆", "帮我找一下附近的咖啡馆")
                    quickChip("🀄 开棋牌室", "我想打拉密牌，打开棋牌室")
                }
                .padding(.horizontal, 12)
            }

            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(llm.messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: llm.messages.count) { _ in
                    if let last = llm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Input Bar
            HStack(spacing: 8) {
                TextField("和轻音部聊点什么，或直接下达控车指令...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(cardBg)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(httGold.opacity(0.45), lineWidth: 1))

                Button(action: {
                    let q = inputText
                    inputText = ""
                    llm.sendUserMessage(q)
                }) {
                    Image(systemName: llm.isGenerating ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(llm.isGenerating ? Color.gray : httCrimson)
                        .clipShape(Circle())
                }
                .disabled(llm.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func quickChip(_ title: String, _ prompt: String) -> some View {
        Button(action: { llm.sendUserMessage(prompt) }) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(cardBg)
                .foregroundColor(httCream)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold.opacity(0.4), lineWidth: 1))
        }
        .disabled(llm.isGenerating)
    }

    private func messageBubble(_ msg: KOnAIChatMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 42) }
            VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                if !msg.isUser {
                    HStack(spacing: 5) {
                        Text(msg.speakerName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(httGold)
                        if !msg.emotionTag.isEmpty {
                            Text("[\(msg.emotionTag)]")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(httCrimson.opacity(0.55))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                }
                Text(msg.text.isEmpty ? "..." : msg.text)
                    .font(.system(size: 14))
                    .foregroundColor(msg.isUser ? .white : httCream)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(msg.isUser ? httCrimson : cardBg)
                    .cornerRadius(14)
                if let hint = msg.actionHint {
                    Text("✨ \(hint)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            if !msg.isUser { Spacer(minLength: 36) }
        }
    }

    // MARK: - Tab 1: On-Demand GGUF Model Manager & Memory
    private var modelManagerTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Status & Memory Guard Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("📱 设备内存：\(String(format: "%.1f", llm.devicePhysicalRamGB)) GB")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(httGold)
                        Spacer()
                        Text("上下文上限：\(llm.maxContextTurns) 轮")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    Text(llm.statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(httCream)
                    Toggle("低内存保护（退出自动释放模型内存）", isOn: $llm.lowMemoryGuardEnabled)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .tint(httCrimson)
                }
                .padding(12)
                .background(cardBg)
                .cornerRadius(12)

                // On-Demand GGUF Catalog
                Text("📦 按需下载本地模型（不占安装包体积）")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(httGold)

                ForEach(KOnLocalLLMManager.modelCatalog) { spec in
                    let isInstalled = llm.installedModels.contains(spec.fileName)
                    let isActive = llm.activeModelFileName == spec.fileName && llm.activeModelLoaded
                    let isDownloading = llm.downloadingModelId == spec.id

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spec.displayName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text(spec.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text(spec.sizeLabel)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(httGold)
                        }

                        if isDownloading {
                            ProgressView(value: llm.downloadProgress)
                                .tint(httGold)
                            HStack {
                                Text("下载中 \(Int(llm.downloadProgress * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundColor(httCream)
                                Spacer()
                                Button("取消") { llm.cancelDownload() }
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        } else if isInstalled {
                            HStack(spacing: 8) {
                                Button(isActive ? "✓ 已挂载 (点击释放)" : "挂载启用") {
                                    if isActive { llm.unloadModelFromMemory() }
                                    else { llm.loadModelIntoMemory(fileName: spec.fileName) }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isActive ? Color.green.opacity(0.75) : httCrimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)

                                Button("删除释放空间") { llm.deleteModel(fileName: spec.fileName) }
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.red.opacity(0.85))
                            }
                        } else {
                            Button("⬇️ 一键下载 (.gguf)") { llm.startDownload(spec: spec) }
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(httCrimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .disabled(llm.downloadingModelId != nil)
                        }
                    }
                    .padding(12)
                    .background(cardBg)
                    .cornerRadius(12)
                }

                // Manual .gguf Import
                Button(action: { showFileImporter = true }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("从手机文件导入本地 .gguf 模型")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(httGold)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold.opacity(0.5), lineWidth: 1))
                }

                // Local Long-Term Memories
                HStack {
                    Text("📝 茶会本地长期记忆（\(llm.memories.count) 条）")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(httGold)
                    Spacer()
                    if !llm.memories.isEmpty {
                        Button("清空") { llm.clearMemories() }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                if llm.memories.isEmpty {
                    Text("对话中说“记住我喜欢…”即可自动存入本地小本本。")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else {
                    ForEach(llm.memories, id: \.self) { m in
                        Text("• \(m)")
                            .font(.system(size: 12))
                            .foregroundColor(httCream)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(12)
        }
    }
}
