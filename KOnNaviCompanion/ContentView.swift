import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioPlayerManager.shared
    @State private var showSoundboardSheet: Bool = false
    @State private var dragOffset: CGSize = .zero
    
    // RM-500HTT Classic Tea-Time Palette
    private let httCrimson = Color(red: 0.78, green: 0.18, blue: 0.22)
    private let httCream = Color(red: 0.99, green: 0.96, blue: 0.90)
    private let httGold = Color(red: 0.88, green: 0.68, blue: 0.24)
    private let httDarkPanel = Color(red: 0.14, green: 0.12, blue: 0.13)
    
    var body: some View {
        ZStack {
            httDarkPanel.ignoresSafeArea()
            
            VStack(spacing: 10) {
                // 1. RM-500HTT Top Bezel Header
                topBezelBar
                
                // 2. Main Speedometer & GPS HUD Cockpit
                speedometerCockpit
                
                // 3. Official K-ON Desktop Pet Interactive Stage + RM-500HTT Dialog
                mascotInteractiveStage
                
                // 4. Character Switcher Bar (5 HTT Members)
                characterSelectorStrip
                
                // 5. RM-500HTT Tactical Utility Buttons
                utilityControlGrid
                
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
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
                Text("HTT NAVI × 軽音部桌宠")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
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
            
            Button(action: {
                withAnimation { manager.isHUDMirrored.toggle() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "flip.horizontal.fill")
                    Text(manager.isHUDMirrored ? "HUD镜像中" : "HUD投影")
                }
                .font(.caption.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(manager.isHUDMirrored ? httGold : Color.white.opacity(0.12))
                .foregroundColor(manager.isHUDMirrored ? .black : httCream)
                .cornerRadius(8)
            }
            
            Button(action: { showSoundboardSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                    Text("语音库")
                }
                .font(.caption.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundColor(httCream)
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - 2. GPS Speedometer & Telemetry Cockpit
    private var speedometerCockpit: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(manager.currentSpeedKmh))")
                            .font(.system(size: 58, weight: .black, design: .monospaced))
                            .foregroundColor(manager.isOverspeeding ? .red : Color(red: 0.35, green: 0.98, blue: 0.65))
                            .shadow(color: (manager.isOverspeeding ? Color.red : Color.green).opacity(0.5), radius: 8)
                        
                        Text("km/h")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.7))
                    }
                    
                    Text(manager.isOverspeeding ? "⚠️ 超速警告 OVER SPEED" : "● GPS 实时测速正常")
                        .font(.caption2.bold())
                        .foregroundColor(manager.isOverspeeding ? .red : .green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 5) {
                    telemetryBadge(icon: "location.north.circle.fill", label: "方向", value: manager.compassDirectionString)
                    telemetryBadge(icon: "road.lanes", label: "里程", value: String(format: "%.1f km", manager.tripDistanceKm))
                    telemetryBadge(icon: "clock.fill", label: "时长", value: manager.formattedDrivingTime)
                }
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            HStack {
                Text("限速阈值:")
                    .font(.caption2)
                    .foregroundColor(httCream.opacity(0.8))
                
                ForEach([60.0, 80.0, 100.0, 120.0], id: \.self) { limit in
                    Button(action: { manager.speedLimitKmh = limit }) {
                        Text("\(Int(limit))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
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
        .padding(12)
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
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(httGold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(httCream)
        }
    }
    
    // MARK: - 3. Official K-ON Windows Desktop Pet Stage & Dialog
    private var mascotInteractiveStage: some View {
        VStack(spacing: 8) {
            // Top Stage: Real Animated Official K-ON Desktop Pet Sprite
            ZStack(alignment: .bottom) {
                // Retro Checkered Stage Floor
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                characterThemeColor(manager.selectedCharacter).opacity(0.35),
                                Color.black.opacity(0.75)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 146)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(httGold, lineWidth: 2)
                    )
                
                // Tea Table background when in Tea Time or Idle
                if let deskImg = manager.deskSpriteFrame {
                    Image(uiImage: deskImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 82)
                        .opacity(0.45)
                        .padding(.bottom, 8)
                }
                
                // Pose Quick Switcher Pills (Top-Left & Top-Right of Stage)
                VStack {
                    HStack(spacing: 6) {
                        posePill(title: "待机", state: .idle)
                        posePill(title: "散步", state: .walkRight)
                        posePill(title: "招牌动作", state: .special)
                        posePill(title: "顶蛋糕", state: .teaCake)
                        Spacer()
                        Text(manager.isDraggingMascot ? "提起中!" : manager.mascotAction.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(httCrimson)
                            .foregroundColor(httCream)
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    Spacer()
                }
                
                // Official Animated Desktop Pet Character Sprite (Draggable & Tappable!)
                if let sprite = manager.currentSpriteFrame {
                    Image(uiImage: sprite)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 112)
                        .offset(
                            x: manager.isDraggingMascot ? dragOffset.width : manager.mascotOffsetX,
                            y: manager.isDraggingMascot ? dragOffset.height : 0
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !manager.isDraggingMascot {
                                        manager.isDraggingMascot = true
                                        manager.playMascotVoice(customQuote: "わぁっ！引っ張らないでよ～！(别揪我呀~)")
                                    }
                                    dragOffset = value.translation
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                        manager.isDraggingMascot = false
                                        dragOffset = .zero
                                        manager.mascotAction = .idle
                                    }
                                }
                        )
                        .onTapGesture {
                            manager.triggerCharacterTap()
                        }
                        .padding(.bottom, 4)
                }
            }
            .frame(height: 146)
            
            // Bottom RM-500HTT Dialog Bubble Box
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(manager.selectedCharacter.roleTag)
                            .font(.caption2.bold())
                            .foregroundColor(httCrimson)
                        Spacer()
                        Text("轻点或按住拖拽桌宠触发原版动作与语音")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    
                    Text(manager.currentSpeechBubble)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black.opacity(0.88))
                        .lineLimit(2)
                }
                
                if manager.isPlaying {
                    Button(action: { manager.stop() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(httCream)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(httGold, lineWidth: 2)
            )
        }
    }
    
    private func posePill(title: String, state: MascotActionState) -> some View {
        Button(action: {
            manager.mascotOffsetX = 0
            manager.mascotAction = state
            manager.playMascotVoice()
        }) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(manager.mascotAction == state ? httGold : Color.black.opacity(0.55))
                .foregroundColor(manager.mascotAction == state ? .black : httCream)
                .cornerRadius(6)
        }
    }
    
    // MARK: - 4. Character Switcher Bar
    private var characterSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AudioPlayerManager.CharacterFilter.allCases) { char in
                    Button(action: {
                        manager.selectedCharacter = char
                        manager.mascotOffsetX = 0
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
                        .padding(.vertical, 7)
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tacticalButton(
                    title: "出発進行",
                    subtitle: "导航问候音",
                    icon: "flag.checkered.2.crossed",
                    color: httCrimson
                ) {
                    let startId = manager.selectedCharacter.idRange.lowerBound
                    manager.playVoice(id: startId, customQuote: "出発進行～！安全運転でレッツゴー！")
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
                    title: "顶蛋糕下午茶",
                    subtitle: "桌宠蛋糕模式",
                    icon: "birthday.cake.fill",
                    color: Color(red: 0.82, green: 0.56, blue: 0.18)
                ) {
                    manager.triggerTeaTimeReminder()
                }
            }
            
            HStack(spacing: 8) {
                Button(action: { manager.toggleCruiseMode() }) {
                    HStack(spacing: 8) {
                        Image(systemName: manager.isCruiseModeActive ? "checkmark.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(manager.isCruiseModeActive ? .green : httGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.isCruiseModeActive ? "巡航陪伴: 开启中" : "开启巡航陪伴")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("导航+桌宠双语音库混播")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(manager.isCruiseModeActive ? Color.green.opacity(0.28) : Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(manager.isCruiseModeActive ? Color.green : httGold.opacity(0.4), lineWidth: 1.5)
                    )
                }
                
                Button(action: {
                    if !manager.isCruiseModeActive { manager.startCruiseMode() }
                    manager.openGaodeMap()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill.viewfinder")
                            .font(.title3)
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("联动高德导航")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("后台伴侣 + 高德指路")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(10)
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
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(httCream)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(httCream.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(httGold.opacity(0.8), lineWidth: 1.5)
            )
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

// MARK: - Full Encrypted Soundboard Drawer
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
                    Button(action: { manager.playVoice(id: voiceId) }) {
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
            .navigationTitle("RM-500HTT × 桌宠加密语音库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
