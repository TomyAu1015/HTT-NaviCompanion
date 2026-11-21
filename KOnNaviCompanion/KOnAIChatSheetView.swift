import SwiftUI
import UniformTypeIdentifiers
import Speech
import AVFoundation

struct KOnAIChatSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @ObservedObject var musicManager = KOnMusicManager.shared
    @ObservedObject var llm = KOnLocalLLMManager.shared
    @StateObject private var voiceInput = KOnVoiceInputManager()
    @Environment(\.dismiss) private var dismiss

    var onOpenGameRoom: () -> Void

    @State private var selectedTab: Int = 0
    @State private var inputText: String = ""
    @State private var apiKeyDraft: String = ""
    @State private var baseUrlDraft: String = ""
    @State private var modelNameDraft: String = ""
    @State private var showFileImporter: Bool = false
    @State private var micPressStartDate: Date? = nil
    @FocusState private var isInputFocused: Bool

    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { dismissKeyboard() }
                        .foregroundColor(httGold)
                }
            }
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
            // Do NOT auto-load 1GB GGUF inside .onAppear so opening AI sheet is 100% instant and crash-free!
            llm.cancelIdleUnload()
            llm.checkPreviousCrashGuard()
            llm.autoMountIfNeeded()
        }
        .onDisappear {
            // Smart delayed unload (90s) when low-memory guard is on; keep resident otherwise for 3D map + music + AI
            llm.scheduleIdleUnloadIfNeeded()
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
        Button(action: { dismissKeyboard(); selectedTab = idx }) {
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
                Button(action: {
                    if llm.hasSavedCloudKey { llm.toggleCloudLocalMode() } else { selectedTab = 1 }
                }) {
                    Text("[\(manager.selectedCharacter.displayName(.zhHans)) · \(llm.isCloudActive ? "☁️ " + llm.cloudProvider.label : "📱 本地")]")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(httGold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                Spacer()
                Text("\(Int(manager.currentSpeedKmh)) km/h")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Button(action: {
                    llm.enableWebSearch.toggle()
                }) {
                    Text(llm.enableWebSearch ? "🌐联网:开" : "🌐联网:关")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(llm.enableWebSearch ? Color.blue.opacity(0.45) : Color.white.opacity(0.12))
                        .foregroundColor(httCream)
                        .cornerRadius(6)
                }
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

            // Messages List (Tap empty space or drag to dismiss keyboard!)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 16).onChanged { _ in dismissKeyboard() })
                .onChange(of: llm.messages.count) { _ in
                    if let last = llm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Voice Recognition Status Banner (when listening or error)
            if voiceInput.isRecording || !voiceInput.statusMessage.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(voiceInput.isRecording ? Color.red : httGold)
                        .frame(width: 7, height: 7)
                    Text(voiceInput.isRecording
                         ? "🎙️ 正在聆听（\(voiceInput.selectedLanguage.shortLabel) · 软件内直录）..."
                         : voiceInput.statusMessage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(voiceInput.isRecording ? Color(red: 1.0, green: 0.72, blue: 0.72) : httCream)
                        .lineLimit(2)
                    Spacer()
                    if voiceInput.isRecording {
                        Button("完成") { voiceInput.stopRecording() }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(httGold)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 12)
            }

            // Input Bar with In-App Cantonese / Multi-Language Voice Input
            HStack(spacing: 6) {
                Menu {
                    ForEach(KOnVoiceInputLanguage.allCases) { lang in
                        Button(action: { voiceInput.setLanguage(lang) }) {
                            HStack {
                                Text(lang.displayName)
                                if voiceInput.selectedLanguage == lang { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(voiceInput.selectedLanguage.shortLabel)
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(httGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .background(cardBg)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(httGold.opacity(0.45), lineWidth: 1))
                }

                Image(systemName: voiceInput.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(voiceInput.isRecording ? Color.red : Color(red: 0.16, green: 0.48, blue: 0.88))
                    .clipShape(Circle())
                    .scaleEffect(voiceInput.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: voiceInput.isRecording)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if micPressStartDate == nil {
                                    micPressStartDate = Date()
                                    dismissKeyboard()
                                    if !voiceInput.isRecording {
                                        let basePrefix = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        voiceInput.startRecording { partial in
                                            inputText = basePrefix.isEmpty ? partial : (basePrefix + " " + partial)
                                        }
                                    } else {
                                        voiceInput.stopRecording()
                                        micPressStartDate = Date.distantPast
                                    }
                                }
                            }
                            .onEnded { _ in
                                let started = micPressStartDate ?? Date()
                                micPressStartDate = nil
                                // Long press (>= 0.35s): stop on release; Quick tap (< 0.35s): stay recording until tapped again!
                                if started != Date.distantPast && Date().timeIntervalSince(started) >= 0.35 && voiceInput.isRecording {
                                    voiceInput.finishRecordingGracefully()
                                }
                            }
                    )

                TextField("语音或打字提问，支持粤语/多语言...", text: $inputText)
                    .focused($isInputFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit {
                        voiceInput.stopRecording()
                        let q = inputText
                        inputText = ""
                        dismissKeyboard()
                        llm.sendUserMessage(q)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(cardBg)
                    .cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(httGold.opacity(0.45), lineWidth: 1))

                Button(action: {
                    voiceInput.stopRecording()
                    let q = inputText
                    inputText = ""
                    dismissKeyboard()
                    llm.sendUserMessage(q)
                }) {
                    Image(systemName: llm.isGenerating ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(llm.isGenerating ? Color.gray : httCrimson)
                        .clipShape(Circle())
                }
                .disabled(llm.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func quickChip(_ title: String, _ prompt: String) -> some View {
        Button(action: { dismissKeyboard(); llm.sendUserMessage(prompt) }) {
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
                if !msg.nearbyPlaces.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(msg.nearbyPlaces.enumerated()), id: \.element.id) { idx, place in
                            let distLabel = place.distanceMeters < 1000 ? "\(Int(place.distanceMeters))m" : String(format: "%.1fkm", place.distanceMeters / 1000.0)
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(idx + 1). \(place.name)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text("距你 \(distLabel)" + (place.address.isEmpty ? "" : " · \(place.address)"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Button(action: {
                                    llm.navigateToNearbyPlace(place)
                                    dismiss()
                                }) {
                                    Text("一键导航")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(7)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.10, green: 0.13, blue: 0.20))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(httGold.opacity(0.45), lineWidth: 1))
                        }
                    }
                    .frame(maxWidth: 290, alignment: .leading)
                    .padding(.top, 4)
                }
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
                // In-App Zero-Cost System Voice Recognition Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("🎙️ 软件内语音录入（零成本 · 粤语/多语言）")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(httGold)
                    Text("当前语言：\(voiceInput.selectedLanguage.displayName)。全程嵌入本软件内实时转文字，不跳转外部应用、无需 API Key。")
                        .font(.system(size: 11))
                        .foregroundColor(httCream.opacity(0.9))
                    Text("离线多语言包：前往 iPhone「设置 → 通用 → 键盘 → 听写语言」勾选粤语/英语/日语等即可自动下载对应语言包。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.gray)
                }
                .padding(12)
                .background(cardBg)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(httGold.opacity(0.45), lineWidth: 1))

                // Cloud API Key Card (Gemini / Doubao / DeepSeek / Custom)
                VStack(alignment: .leading, spacing: 8) {
                    Text("☁️ 云端大模型 API Key（Gemini / 豆包 / DeepSeek）")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(httGold)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(CloudAIProvider.allCases) { prov in
                                let selected = llm.cloudProvider == prov
                                Button(action: {
                                    llm.selectCloudProvider(prov)
                                    baseUrlDraft = llm.cloudBaseUrl
                                    modelNameDraft = llm.cloudModelName
                                }) {
                                    Text(prov.label)
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selected ? httCrimson : Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }

                    Text(llm.isCloudActive ? "当前生效：☁️ \(llm.cloudProvider.label)（点上方「本地 Qwen2.5」可随时切回离线模型）" : "当前生效：📱 本地离线 Qwen2.5（不消耗云端 API 额度）")
                        .font(.system(size: 11))
                        .foregroundColor(llm.isCloudActive ? Color.green : httCream)

                    if llm.cloudProvider != .local {
                        HStack(spacing: 6) {
                            TextField("填入 API Key", text: $apiKeyDraft)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.35))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(httGold.opacity(0.4), lineWidth: 1))
                            Button("粘贴") {
                                if let clip = UIPasteboard.general.string {
                                    apiKeyDraft = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(httGold)
                            .cornerRadius(8)
                        }

                        TextField("模型名 / 豆包接入点 ID (ep-...)", text: $modelNameDraft)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))

                        if llm.cloudProvider != .gemini {
                            HStack(spacing: 6) {
                                TextField("API Base URL", text: $baseUrlDraft)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.35))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                Button("粘贴") {
                                    if let clip = UIPasteboard.general.string {
                                        baseUrlDraft = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.16))
                                .cornerRadius(8)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                dismissKeyboard()
                                llm.saveCloudConfig(provider: llm.cloudProvider, apiKey: apiKeyDraft, baseUrl: baseUrlDraft, modelName: modelNameDraft)
                            }) {
                                Text("保存启用")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.18, green: 0.49, blue: 0.2))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            Button(action: {
                                dismissKeyboard()
                                llm.saveCloudConfig(provider: llm.cloudProvider, apiKey: apiKeyDraft, baseUrl: baseUrlDraft, modelName: modelNameDraft)
                                llm.testCloudConnection()
                            }) {
                                Text("保存并测试连接")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }

                        if !llm.cloudTestStatus.isEmpty {
                            Text(llm.cloudTestStatus)
                                .font(.system(size: 11))
                                .foregroundColor(httGold)
                        }
                    }
                }
                .padding(12)
                .background(cardBg)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(httGold.opacity(0.35), lineWidth: 1))
                .onAppear {
                    apiKeyDraft = llm.cloudApiKey
                    baseUrlDraft = llm.cloudBaseUrl
                    modelNameDraft = llm.cloudModelName
                }
                // Status & Memory Guard Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("📱 设备 \(String(format: "%.1f", llm.devicePhysicalRamGB))GB · 可用约 \(llm.liveAvailableMemoryMB)MB")
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
                    Toggle("低内存保护（退出茶会 90 秒后自动释放模型）", isOn: $llm.lowMemoryGuardEnabled)
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


// MARK: - In-App Zero-Cost System Voice Recognition (Apple Speech Framework)
enum KOnVoiceInputLanguage: String, CaseIterable, Identifiable {
    case cantoneseHK = "zh-HK"
    case mandarinCN = "zh-CN"
    case traditionalTW = "zh-TW"
    case englishUS = "en-US"
    case japaneseJP = "ja-JP"

    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .cantoneseHK: return "粤语"
        case .mandarinCN: return "普通话"
        case .traditionalTW: return "繁體"
        case .englishUS: return "EN"
        case .japaneseJP: return "日本語"
        }
    }
    var displayName: String {
        switch self {
        case .cantoneseHK: return "粤语 / 广东话 (zh-HK)"
        case .mandarinCN: return "普通话 (zh-CN)"
        case .traditionalTW: return "繁體中文 (zh-TW)"
        case .englishUS: return "English (en-US)"
        case .japaneseJP: return "日本語 (ja-JP)"
        }
    }
}

final class KOnVoiceInputManager: NSObject, ObservableObject {
    @Published var isRecording: Bool = false
    @Published var statusMessage: String = ""
    @Published var selectedLanguage: KOnVoiceInputLanguage = .cantoneseHK

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var onTextUpdate: ((String) -> Void)?

    override init() {
        super.init()
        if let rawLang = UserDefaults.standard.string(forKey: "htt_voice_lang"),
           let l = KOnVoiceInputLanguage(rawValue: rawLang) {
            selectedLanguage = l
        }
    }

    func setLanguage(_ lang: KOnVoiceInputLanguage) {
        selectedLanguage = lang
        UserDefaults.standard.set(lang.rawValue, forKey: "htt_voice_lang")
    }

    func startRecording(onUpdate: @escaping (String) -> Void) {
        stopRecording()
        self.onTextUpdate = onUpdate
        self.statusMessage = ""

        // Crash Guard: verify Info.plist contains both privacy keys before touching TCC audio/speech APIs
        let hasMicDesc = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        let hasSpeechDesc = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
        guard hasMicDesc && hasSpeechDesc else {
            self.statusMessage = "安装包缺少麦克风/语音权限声明，请用最新构建的 IPA 覆盖安装即可正常使用"
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] micGranted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard micGranted else {
                    self.statusMessage = "请在系统设置中开启麦克风权限"
                    return
                }
                SFSpeechRecognizer.requestAuthorization { authStatus in
                    DispatchQueue.main.async {
                        if authStatus == .authorized {
                            self.startAppleSpeechSession()
                        } else {
                            self.statusMessage = "请在系统设置中开启语音识别权限"
                        }
                    }
                }
            }
        }
    }

    private func startAppleSpeechSession() {
        let locale = Locale(identifier: selectedLanguage.rawValue)
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            statusMessage = "当前语音识别暂不可用，请检查网络或下载系统离线听写语言包"
            return
        }
        self.speechRecognizer = recognizer

        do {
            // Deactivate first to clear any stale .playback / CarPlay / Bluetooth A2DP route that causes -10868
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            self.audioEngine = engine

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 13.0, *) {
                req.requiresOnDeviceRecognition = false
            }
            self.recognitionRequest = req

            let inputNode = engine.inputNode
            let hwFmt = inputNode.outputFormat(forBus: 0)
            let tapFmt: AVAudioFormat? = (hwFmt.sampleRate > 0 && hwFmt.channelCount > 0) ? hwFmt : nil
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFmt) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            engine.prepare()
            try engine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let res = result {
                        self.onTextUpdate?(res.bestTranscription.formattedString)
                        if res.isFinal {
                            self.stopRecording()
                        }
                    }
                    if let err = error, self.isRecording {
                        self.statusMessage = "识别已结束：\(err.localizedDescription)"
                        self.stopRecording()
                    }
                }
            }
        } catch {
            statusMessage = "启动录音失败：\(error.localizedDescription)"
            stopRecording()
        }
    }

    func finishRecordingGracefully() {
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        isRecording = false
    }

    func stopRecording() {
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .default, options: KOnMusicManager.shared.isPlaying ? [] : [.mixWithOthers])
        try? session.setActive(true)
    }
}
