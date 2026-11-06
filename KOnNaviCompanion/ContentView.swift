import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioPlayerManager.shared
    @State private var selectedTab: CharacterTab = .yui
    @State private var searchText: String = ""
    
    enum CharacterTab: String, CaseIterable, Identifiable {
        case yui = "平泽唯"
        case mio = "秋山澪"
        case ritsu = "田井中律"
        case mugi = "琴吹紬"
        case azusa = "中野梓"
        case special = "互动彩蛋"
        
        var id: String { self.rawValue }
        
        var idRange: ClosedRange<Int> {
            switch self {
            case .yui: return 1...196
            case .mio: return 197...392
            case .ritsu: return 393...588
            case .mugi: return 589...784
            case .azusa: return 785...980
            case .special: return 981...1122
            }
        }
        
        var themeColor: Color {
            switch self {
            case .yui: return Color(red: 0.95, green: 0.55, blue: 0.55)     // Sakura Pink
            case .mio: return Color(red: 0.45, green: 0.65, blue: 0.95)     // Sky Blue
            case .ritsu: return Color(red: 0.95, green: 0.75, blue: 0.35)   // Golden Amber
            case .mugi: return Color(red: 0.95, green: 0.85, blue: 0.50)    // Warm Tea
            case .azusa: return Color(red: 0.40, green: 0.80, blue: 0.70)   // Mint Green
            case .special: return Color(red: 0.80, green: 0.55, blue: 0.90) // Lavender
            }
        }
        
        var subtitle: String {
            switch self {
            case .yui: return "CV: 丰崎爱生 (196句)"
            case .mio: return "CV: 日笠阳子 (196句)"
            case .ritsu: return "CV: 佐藤聪美 (196句)"
            case .mugi: return "CV: 寿美菜子 (196句)"
            case .azusa: return "CV: 竹达彩奈 (196句)"
            case .special: return "双人/多人互动对话 (142句)"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Card: Cruise Mode / Vehicle Companion
                    cruiseHeaderView
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    
                    // Character Selector Tabs
                    characterTabSelector
                        .padding(.vertical, 8)
                    
                    // Voice Grid / List
                    voiceListSection
                }
            }
            .navigationTitle("放课后茶会 车载伴侣")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if audio.isPlaying {
                        Button(action: { audio.stop() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                Text("停止")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cruise Mode Header
    private var cruiseHeaderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundColor(selectedTab.themeColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("车载巡航陪伴模式")
                        .font(.headline)
                    Text(audio.isCruiseModeActive ? "正在后台定期播报，与导航/音乐共存" : "开启后定时随机播报角色关怀台词")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { audio.isCruiseModeActive },
                    set: { _ in audio.toggleCruiseMode() }
                ))
                .labelsHidden()
            }
            
            if audio.isCruiseModeActive {
                Divider()
                HStack(spacing: 16) {
                    Text("间隔:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("间隔", selection: $audio.cruiseIntervalMinutes) {
                        Text("5分钟").tag(5.0)
                        Text("10分钟").tag(10.0)
                        Text("15分钟").tag(15.0)
                        Text("30分钟").tag(30.0)
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("伴侣", selection: $audio.selectedCruiseCharacter) {
                        ForEach(AudioPlayerManager.CharacterFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Character Tab Selector
    private var characterTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CharacterTab.allCases) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.subheadline.bold())
                                .foregroundColor(selectedTab == tab ? .white : .primary)
                            Text(tab == .special ? "彩蛋" : "196句")
                                .font(.system(size: 10))
                                .foregroundColor(selectedTab == tab ? .white.opacity(0.85) : .secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? tab.themeColor : Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Voice List Section
    private var voiceListSection: some View {
        VStack(spacing: 8) {
            // Quick random play button for this character
            HStack {
                Text(selectedTab.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: {
                    let randomId = Int.random(in: selectedTab.idRange)
                    audio.playVoice(id: randomId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                        Text("随机试听")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selectedTab.themeColor.opacity(0.15))
                    .foregroundColor(selectedTab.themeColor)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            // List of Voices
            List {
                ForEach(filteredVoiceIds, id: \.self) { voiceId in
                    voiceRow(for: voiceId)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    private var filteredVoiceIds: [Int] {
        let range = selectedTab.idRange
        return Array(range)
    }
    
    private func voiceRow(for voiceId: Int) -> some View {
        let isCurrent = audio.currentPlayingId == voiceId && audio.isPlaying
        let characterIndex = voiceId - selectedTab.idRange.lowerBound + 1
        
        return Button(action: {
            if isCurrent {
                audio.stop()
            } else {
                audio.playVoice(id: voiceId)
            }
        }) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isCurrent ? selectedTab.themeColor : Color(UIColor.tertiarySystemFill))
                        .frame(width: 36, height: 36)
                    Image(systemName: isCurrent ? "waveform" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isCurrent ? .white : selectedTab.themeColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("语音片段 #\(characterIndex)")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("全局编号: VOICE_DB-\(String(format: "%010d", voiceId))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isCurrent {
                    Text("正在播放")
                        .font(.caption2.bold())
                        .foregroundColor(selectedTab.themeColor)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
