import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioPlayerManager.shared
    @State private var showSoundboardSheet: Bool = false
    @State private var avatarBounce: Bool = false
    
    // RM-500HTT Classic Tea-Time Palette
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httDarkPanel = Color(red: 0.14, green: 0.12, blue: 0.13)
    
    var body: some View {
        ZStack {
            // Retro Tea-Tin Dark Background
            httDarkPanel.ignoresSafeArea()
            
            VStack(spacing: 12) {
                // 1. RM-500HTT Top Bezel Header
                topBezelBar
                
                // 2. Main Speedometer & GPS HUD Cockpit
                speedometerCockpit
                
                // 3. Interactive Character Stage & Dialog Box
                characterInteractiveStage
                
                // 4. Character Switcher Bar (5 HTT Members)
                characterSelectorStrip
                
                // 5. RM-500HTT Tactical Utility Buttons
                utilityControlGrid
                
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            // Support Windshield HUD Mirror Mode
            .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
        }
        .sheet(isPresented: $showSoundboardSheet) {
            SoundboardSheetView(manager: manager)
        }
    }
    
    // MARK: - 1. Top Bezel Header
    private var topBezelBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundColor(httGold)
                Text("HTT NAVI RM-500HTT")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(httCream)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(httCrimson)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(httGold, lineWidth: 1.5)
            )
            
            Spacer()
            
            // HUD Windshield Mirror Toggle
            Button(action: {
                withAnimation {
                    manager.isHUDMirrored.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "flip.horizontal.fill")
                    Text(manager.isHUDMirrored ? "HUD镜像中" : "HUD投影")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(manager.isHUDMirrored ? httGold : Color.white.opacity(0.12))
                .foregroundColor(manager.isHUDMirrored ? .black : httCream)
                .cornerRadius(8)
            }
            
            // Full Soundboard Button
            Button(action: {
                showSoundboardSheet = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                    Text("语音库")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundColor(httCream)
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - 2. GPS Speedometer & Telemetry Cockpit
    private var speedometerCockpit: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                // Digital Speed Readout
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(manager.currentSpeedKmh))")
                            .font(.system(size: 64, weight: .black, design: .monospaced))
                            .foregroundColor(manager.isOverspeeding ? .red : Color(red: 0.35, green: 0.98, blue: 0.65))
                            .shadow(color: (manager.isOverspeeding ? Color.red : Color.green).opacity(0.5), radius: 8)
                        
                        Text("km/h")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.7))
                    }
                    
                    HStack(spacing: 8) {
                        Text(manager.isOverspeeding ? "⚠️ 超速警告 OVER SPEED" : "● GPS 实时测速正常")
                            .font(.caption2.bold())
                            .foregroundColor(manager.isOverspeeding ? .red : .green)
                    }
                }
                
                Spacer()
                
                // Telemetry Grid (Compass, Distance, Time)
                VStack(alignment: .trailing, spacing: 6) {
                    telemetryBadge(icon: "location.north.circle.fill", label: "方向", value: manager.compassDirectionString)
                    telemetryBadge(icon: "road.lanes", label: "里程", value: String(format: "%.1f km", manager.tripDistanceKm))
                    telemetryBadge(icon: "clock.fill", label: "时长", value: manager.formattedDrivingTime)
                }
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            // Speed Limit Selector
            HStack {
                Text("超速报警阈值:")
                    .font(.caption)
                    .foregroundColor(httCream.opacity(0.8))
                
                ForEach([60.0, 80.0, 100.0, 120.0], id: \.self) { limit in
                    Button(action: {
                        manager.speedLimitKmh = limit
                    }) {
                        Text("\(Int(limit))")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(manager.speedLimitKmh == limit ? httCrimson : Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                Text("最高: \(Int(manager.maxSpeedKmh)) km/h")
                    .font(.caption2)
                    .foregroundColor(httGold)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(manager.isOverspeeding ? Color.red : httGold.opacity(0.6), lineWidth: 2)
                )
        )
    }
    
    private func telemetryBadge(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(httGold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(httCream)
        }
    }
    
    // MARK: - 3. Interactive Character Stage (RM-500HTT Dialog + Avatar)
    private var characterInteractiveStage: some View {
        HStack(spacing: 12) {
            // Tappable Character Chibi Card
            Button(action: {
                triggerBounce()
                manager.triggerCharacterTap()
            }) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [characterThemeColor(manager.selectedCharacter), characterThemeColor(manager.selectedCharacter).opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 118)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(httCream, lineWidth: 2)
                        )
                    
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(httCream)
                                .frame(width: 62, height: 62)
                                .shadow(radius: 3)
                            
                            Image(systemName: manager.selectedCharacter.instrumentIcon)
                                .font(.system(size: 30))
                                .foregroundColor(characterThemeColor(manager.selectedCharacter))
                                .scaleEffect(avatarBounce || manager.isPlaying ? 1.18 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.4), value: avatarBounce)
                        }
                        
                        Text(manager.selectedCharacter.rawValue)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                        
                        Text("点击互动")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.4))
                            .foregroundColor(httGold)
                            .cornerRadius(4)
                    }
                    .padding(.bottom, 8)
                }
            }
            .buttonStyle(.plain)
            
            // RM-500HTT Classic Speech Bubble Box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(manager.selectedCharacter.roleTag)
                        .font(.caption.bold())
                        .foregroundColor(httCrimson)
                    
                    Spacer()
                    
                    Text(manager.currentMood.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(httCrimson.opacity(0.15))
                        .foregroundColor(httCrimson)
                        .cornerRadius(4)
                }
                
                Text(manager.currentSpeechBubble)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
                
                HStack {
                    if manager.isPlaying {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                            Text("正在播报原声...")
                        }
                        .font(.caption2.bold())
                        .foregroundColor(httCrimson)
                    } else {
                        Text("轻点左侧角色头像随时触发专属语音")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if manager.isPlaying {
                        Button("停止") {
                            manager.stop()
                        }
                        .font(.caption2.bold())
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118)
            .background(httCream)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(httGold, lineWidth: 2.5)
            )
        }
    }
    
    // MARK: - 4. Character Switcher Bar
    private var characterSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AudioPlayerManager.CharacterFilter.allCases) { char in
                    Button(action: {
                        manager.selectedCharacter = char
                        triggerBounce()
                        manager.triggerCharacterTap()
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(characterThemeColor(char))
                                .frame(width: 8, height: 8)
                            Text(char.rawValue)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            manager.selectedCharacter == char
                            ? characterThemeColor(char)
                            : Color.white.opacity(0.1)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(manager.selectedCharacter == char ? httGold : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - 5. RM-500HTT Tactical Utility Control Grid
    private var utilityControlGrid: some View {
        VStack(spacing: 10) {
            // Row 1: Action Sound Triggers
            HStack(spacing: 10) {
                tacticalButton(
                    title: "出発進行",
                    subtitle: "点火问候音",
                    icon: "flag.checkered.2.crossed",
                    color: httCrimson
                ) {
                    let startId = manager.selectedCharacter.idRange.lowerBound
                    manager.playVoice(id: startId, customQuote: "出発進行～！安全運転でレッツゴー！", mood: .excited)
                }
                
                tacticalButton(
                    title: "掛け合い",
                    subtitle: "双人相声彩蛋",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: Color(red: 0.58, green: 0.32, blue: 0.78)
                ) {
                    manager.triggerBanter()
                }
                
                tacticalButton(
                    title: "下午茶休息",
                    subtitle: "紬的红茶提醒",
                    icon: "cup.and.saucer.fill",
                    color: Color(red: 0.82, green: 0.56, blue: 0.18)
                ) {
                    manager.triggerTeaTimeReminder()
                }
            }
            
            // Row 2: Cruise Mode & 1-Tap Gaode Navigation Integration
            HStack(spacing: 10) {
                // Cruise Mode Toggle Button
                Button(action: {
                    manager.toggleCruiseMode()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: manager.isCruiseModeActive ? "Smallcircle.filled.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(manager.isCruiseModeActive ? .green : httGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.isCruiseModeActive ? "巡航陪伴: 开启中" : "开启巡航陪伴")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text(manager.isCruiseModeActive ? "后台每\(Int(manager.cruiseIntervalMinutes))分钟自动搭话" : "锁屏/后台定时触发语音")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(manager.isCruiseModeActive ? Color.green.opacity(0.28) : Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(manager.isCruiseModeActive ? Color.green : httGold.opacity(0.4), lineWidth: 1.5)
                    )
                }
                
                // 1-Tap Gaode Map Companion Launch
                Button(action: {
                    if !manager.isCruiseModeActive {
                        manager.startCruiseMode()
                    }
                    manager.openGaodeMap()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill.viewfinder")
                            .font(.title2)
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("联动高德导航")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("后台伴侣 + 高德指路")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(httGold, lineWidth: 1.5)
                    )
                }
            }
        }
    }
    
    private func tacticalButton(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            triggerBounce()
            action()
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(httCream)
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(httCream.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(httGold.opacity(0.8), lineWidth: 1.5)
            )
        }
    }
    
    private func triggerBounce() {
        avatarBounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            avatarBounce = false
        }
    }
    
    private func characterThemeColor(_ char: AudioPlayerManager.CharacterFilter) -> Color {
        switch char {
        case .yui: return Color(red: 0.90, green: 0.32, blue: 0.38)
        case .mio: return Color(red: 0.25, green: 0.48, blue: 0.82)
        case .ritsu: return Color(red: 0.85, green: 0.58, blue: 0.15)
        case .mugi: return Color(red: 0.78, green: 0.52, blue: 0.68)
        case .azusa: return Color(red: 0.22, green: 0.65, blue: 0.52)
        case .all: return httCrimson
        }
    }
}

// MARK: - Full 1,122 Encrypted Soundboard Drawer
struct SoundboardSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedSection: Int = 0
    
    private let sections: [(title: String, range: ClosedRange<Int>)] = [
        ("平泽唯 (1-196)", 1...196),
        ("秋山澪 (197-392)", 197...392),
        ("田井中律 (393-588)", 393...588),
        ("琴吹紬 (589-784)", 589...784),
        ("中野梓 (785-980)", 785...980),
        ("互动彩蛋 (981-1122)", 981...1122)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<sections.count, id: \.self) { idx in
                            Button(action: { selectedSection = idx }) {
                                Text(sections[idx].title)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedSection == idx ? Color.red : Color.gray.opacity(0.2))
                                    .foregroundColor(selectedSection == idx ? .white : .primary)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
                
                List(Array(sections[selectedSection].range), id: \.self) { voiceId in
                    Button(action: {
                        manager.playVoice(id: voiceId)
                    }) {
                        HStack {
                            Image(systemName: manager.currentPlayingId == voiceId && manager.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text("RM-500HTT 原声片段 #\(voiceId)")
                                    .font(.subheadline.bold())
                                Text("加密索引: VOICE_DB-\(String(format: "%010d", voiceId))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if manager.currentPlayingId == voiceId && manager.isPlaying {
                                Text("播放中")
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("RM-500HTT 全量加密语音库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
