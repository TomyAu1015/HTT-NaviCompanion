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
    
    private func tr(_ hans: String, _ hant: String, _ en: String) -> String {
        switch manager.language {
        case .zhHans: return hans
        case .zhHant: return hant
        case .en: return en
        }
    }
    
    var body: some View {
        ZStack {
            httDarkPanel.ignoresSafeArea()
            
            VStack(spacing: 8) {
                // 1. Top Bezel Header (with Language Switcher, HUD Mirror, Soundboard)
                topBezelBar
                
                // 2. Main Speedometer & GPS HUD Cockpit (with GPS Poor Signal & Speed Limit Broadcast)
                speedometerCockpit
                
                // 3. Official K-ON Desktop Pet Interactive Stage (Supports All 5 Members Together!)
                mascotInteractiveStage
                
                // 4. Character Switcher Bar (All 5 Together + 5 Individual Members)
                characterSelectorStrip
                
                // 5. RM-500HTT Tactical Utility Control Grid & Reliable Cruise Mode
                utilityControlGrid
                
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .scaleEffect(x: manager.isHUDMirrored ? -1 : 1, y: 1)
        }
        .sheet(isPresented: $showSoundboardSheet) {
            SoundboardSheetView(manager: manager)
        }
    }
    
    // MARK: - 1. Top Bezel Header
    private var topBezelBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundColor(httGold)
                Text(tr("HTT 车载桌宠", "HTT 車載桌寵", "HTT NAVI PET"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(httCream)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(httCrimson)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(httGold, lineWidth: 1.5)
            )
            
            Spacer()
            
            // 3-Language Switcher (简体 / 繁體 / EN)
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button(action: { manager.language = lang }) {
                        HStack {
                            Text(lang.rawValue)
                            if manager.language == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                    Text(manager.language.rawValue)
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14))
                .foregroundColor(httGold)
                .cornerRadius(8)
            }
            
            // HUD Windshield Mirror Toggle
            Button(action: {
                withAnimation { manager.isHUDMirrored.toggle() }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "flip.horizontal.fill")
                    Text(manager.isHUDMirrored ? tr("镜像中", "鏡像中", "Mirrored") : "HUD")
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(manager.isHUDMirrored ? httGold : Color.white.opacity(0.12))
                .foregroundColor(manager.isHUDMirrored ? .black : httCream)
                .cornerRadius(8)
            }
            
            // Full Soundboard Button
            Button(action: { showSoundboardSheet = true }) {
                HStack(spacing: 3) {
                    Image(systemName: "music.note.list")
                    Text(tr("语音库", "語音庫", "Voices"))
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .foregroundColor(httCream)
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - 2. GPS Speedometer & Telemetry Cockpit
    private var speedometerCockpit: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(manager.currentSpeedKmh))")
                            .font(.system(size: 52, weight: .black, design: .monospaced))
                            .foregroundColor(manager.isOverspeeding ? .red : Color(red: 0.35, green: 0.98, blue: 0.65))
                            .shadow(color: (manager.isOverspeeding ? Color.red : Color.green).opacity(0.5), radius: 6)
                        
                        Text("km/h")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(httCream.opacity(0.7))
                    }
                    
                    // Interactive GPS & Speed Status Row
                    HStack(spacing: 8) {
                        Button(action: {
                            manager.triggerGPSSignalPoorAlert()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: manager.isGPSSignalPoor ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                                Text(manager.isGPSSignalPoor
                                     ? tr("GPS信号弱(点击播报)", "GPS訊號弱(點擊播報)", "GPS Weak (Tap)")
                                     : tr("GPS信号正常", "GPS訊號正常", "GPS OK"))
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(manager.isGPSSignalPoor ? Color.orange.opacity(0.3) : Color.green.opacity(0.18))
                            .foregroundColor(manager.isGPSSignalPoor ? .orange : .green)
                            .cornerRadius(5)
                        }
                        
                        if manager.isOverspeeding {
                            Text(tr("⚠️ 已超速!", "⚠️ 已超速!", "⚠️ OVERSPEED!"))
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    telemetryBadge(icon: "location.north.circle.fill", label: tr("方向", "方向", "DIR"), value: manager.compassDirectionString)
                    telemetryBadge(icon: "road.lanes", label: tr("里程", "里程", "TRIP"), value: String(format: "%.1f km", manager.tripDistanceKm))
                    telemetryBadge(icon: "clock.fill", label: tr("时长", "時長", "TIME"), value: manager.formattedDrivingTime)
                }
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            // Speed Limit Selector (Tapping any limit sets it & broadcasts built-in traffic regulation prompt!)
            HStack(spacing: 6) {
                Button(action: { manager.triggerSpeedLimitPrompt() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "speedometer")
                        Text(tr("限速播报:", "限速播報:", "Limit:"))
                    }
                    .font(.caption2.bold())
                    .foregroundColor(httGold)
                }
                
                ForEach([60.0, 80.0, 100.0, 120.0], id: \.self) { limit in
                    Button(action: {
                        if manager.speedLimitKmh == limit {
                            manager.triggerSpeedLimitPrompt()
                        } else {
                            manager.speedLimitKmh = limit
                        }
                    }) {
                        Text("\(Int(limit))")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(manager.speedLimitKmh == limit ? httCrimson : Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
                Spacer()
                Text("\(tr("最高", "最高", "MAX")): \(Int(manager.maxSpeedKmh))")
                    .font(.caption2)
                    .foregroundColor(httGold)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(manager.isOverspeeding ? Color.red : httGold.opacity(0.6), lineWidth: 2)
                )
        )
    }
    
    private func telemetryBadge(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(httGold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(httCream)
        }
    }
    
    // MARK: - 3. Official K-ON Windows Desktop Pet Stage (5-Member Simultaneous or Solo!)
    private var mascotInteractiveStage: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                characterThemeColor(manager.selectedCharacter).opacity(0.35),
                                Color.black.opacity(0.78)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(httGold, lineWidth: 2)
                    )
                
                // Official MascotTable Tea Table & Cake Prop in Background
                if let deskImg = manager.deskSpriteFrame {
                    Image(uiImage: deskImg)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(height: manager.selectedCharacter == .all ? 90 : 80)
                        .opacity(manager.selectedCharacter == .all ? 0.85 : 0.45)
                        .padding(.bottom, 8)
                }
                
                // Pose Quick Switcher Pills at Top of Stage
                VStack {
                    HStack(spacing: 5) {
                        posePill(title: tr("待机", "待機", "Idle"), state: .idle)
                        posePill(title: tr("散步", "散步", "Walk"), state: .walkRight)
                        posePill(title: tr("招牌动作", "招牌動作", "Dance"), state: .special)
                        posePill(title: tr("顶蛋糕", "頂蛋糕", "Cake"), state: .teaCake)
                        Spacer()
                        Text(manager.isDraggingMascot
                             ? tr("提起挣扎!", "提起掙扎!", "Lifted!")
                             : manager.mascotAction.localizedTitle(manager.language))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(httCrimson)
                            .foregroundColor(httCream)
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 7)
                    Spacer()
                }
                
                // Render ALL 5 HTT MEMBERS TOGETHER when .all is selected, or solo member!
                if manager.selectedCharacter == .all {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(AudioPlayerManager.CharacterFilter.fiveIndividuals) { member in
                            if let frame = manager.allMemberFrames[member.charId] {
                                let isThisDragged = manager.isDraggingMascot && manager.draggedMemberId == member.charId
                                VStack(spacing: 0) {
                                    Image(uiImage: frame)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 86)
                                    Text(member.displayName(manager.language))
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(characterThemeColor(member).opacity(0.85))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                                .offset(
                                    x: isThisDragged ? dragOffset.width : (manager.mascotOffsetX * 0.35),
                                    y: isThisDragged ? dragOffset.height : 0
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if !manager.isDraggingMascot {
                                                manager.isDraggingMascot = true
                                                manager.draggedMemberId = member.charId
                                                manager.playMascotVoice(for: member)
                                            }
                                            dragOffset = value.translation
                                        }
                                        .onEnded { _ in
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                                manager.isDraggingMascot = false
                                                manager.draggedMemberId = nil
                                                dragOffset = .zero
                                                manager.mascotAction = .idle
                                            }
                                        }
                                )
                                .onTapGesture {
                                    manager.triggerCharacterTap(member: member)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 5)
                } else if let sprite = manager.currentSpriteFrame {
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
                                        manager.playMascotVoice()
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
            .frame(height: 150)
            
            // RM-500HTT Speech Bubble Box
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(manager.selectedCharacter.roleTag(manager.language))
                            .font(.caption2.bold())
                            .foregroundColor(httCrimson)
                        Spacer()
                        Text(tr("点击或拖拽任意角色互动", "點擊或拖拽任意角色互動", "Tap or drag character"))
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    
                    Text(manager.currentSpeechBubble)
                        .font(.system(size: 12, weight: .bold))
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
            .padding(.vertical, 7)
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
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(manager.mascotAction == state ? httGold : Color.black.opacity(0.55))
                .foregroundColor(manager.mascotAction == state ? .black : httCream)
                .cornerRadius(6)
        }
    }
    
    // MARK: - 4. Character Switcher Strip
    private var characterSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(AudioPlayerManager.CharacterFilter.allCases) { char in
                    Button(action: {
                        manager.selectedCharacter = char
                        manager.mascotOffsetX = 0
                        manager.triggerCharacterTap(member: char)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: char == .all ? "person.3.fill" : "person.fill")
                                .font(.system(size: 10))
                            Text(char.displayName(manager.language))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 11)
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
    
    // MARK: - 5. RM-500HTT Tactical Utility Control Grid & Cruise Timer
    private var utilityControlGrid: some View {
        VStack(spacing: 7) {
            // Row 1: 4 Direct Action Buttons (Departure, Banter, GPS/Speed Alert, Tea Time)
            HStack(spacing: 7) {
                tacticalButton(
                    title: tr("出発進行", "出發進行", "Depart"),
                    subtitle: tr("点火出发音", "點火出發音", "Start Guide"),
                    icon: "flag.checkered.2.crossed",
                    color: httCrimson
                ) {
                    manager.triggerDepartureGreeting()
                }
                
                tacticalButton(
                    title: tr("掛け合い", "雙人相聲", "Banter"),
                    subtitle: tr("多人对话彩蛋", "多人對話彩蛋", "Group Talk"),
                    icon: "bubble.left.and.bubble.right.fill",
                    color: Color(red: 0.58, green: 0.32, blue: 0.78)
                ) {
                    manager.triggerBanter()
                }
                
                tacticalButton(
                    title: tr("顶蛋糕下午茶", "頂蛋糕下午茶", "Tea Time"),
                    subtitle: tr("桌宠蛋糕休息", "桌寵蛋糕休息", "Cake Break"),
                    icon: "birthday.cake.fill",
                    color: Color(red: 0.82, green: 0.56, blue: 0.18)
                ) {
                    manager.triggerTeaTimeReminder()
                }
            }
            
            // Row 2: Cruise Mode (with Live Countdown & Interval Menu) + Gaode Map Launcher
            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    Button(action: { manager.toggleCruiseMode() }) {
                        HStack(spacing: 6) {
                            Image(systemName: manager.isCruiseModeActive ? "timer" : "play.circle.fill")
                                .font(.title3)
                                .foregroundColor(manager.isCruiseModeActive ? .green : httGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manager.isCruiseModeActive
                                     ? "\(tr("巡航中", "巡航中", "Cruise")): \(manager.formattedCruiseCountdown)"
                                     : tr("开启巡航陪伴", "開啟巡航陪伴", "Start Cruise"))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text(tr("后台保活·定时播报", "後台保活·定時播報", "Background Active"))
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                    }
                    
                    Spacer(minLength: 2)
                    
                    // Interval Selector Menu (1 / 3 / 5 / 10 / 15 / 30 mins)
                    Menu {
                        ForEach([1.0, 3.0, 5.0, 10.0, 15.0, 30.0], id: \.self) { mins in
                            Button(action: { manager.cruiseIntervalMinutes = mins }) {
                                HStack {
                                    Text("\(Int(mins)) \(tr("分钟", "分鐘", "min"))")
                                    if manager.cruiseIntervalMinutes == mins {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("\(Int(manager.cruiseIntervalMinutes))m ▾")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.35))
                            .foregroundColor(httGold)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(manager.isCruiseModeActive ? Color.green.opacity(0.28) : Color.white.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(manager.isCruiseModeActive ? Color.green : httGold.opacity(0.4), lineWidth: 1.5)
                )
                
                // 1-Tap Gaode Map Companion Launch
                Button(action: {
                    if !manager.isCruiseModeActive { manager.startCruiseMode() }
                    manager.openGaodeMap()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill.viewfinder")
                            .font(.title3)
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("联动高德导航", "聯動高德導航", "Open Amap"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text(tr("后台伴侣+高德指路", "後台伴侶+高德指路", "Voice + Navigation"))
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
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
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(httCream)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(httCream.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
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

// MARK: - Verified Character-Matched Soundboard (Excludes IDs 1..156 Generic Announcer!)
struct SoundboardSheetView: View {
    @ObservedObject var manager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedSection: Int = 0
    
    private var sections: [(title: String, ids: [Int])] {
        let lang = manager.language
        return [
            ("\(AudioPlayerManager.CharacterFilter.yui.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.yui.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.mio.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.mio.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.ritsu.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.ritsu.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.mugi.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.mugi.verifiedVoiceIds),
            ("\(AudioPlayerManager.CharacterFilter.azusa.displayName(lang)) (192)", AudioPlayerManager.CharacterFilter.azusa.verifiedVoiceIds),
            (lang == .en ? "Bonus & Birthdays (11)" : (lang == .zhHant ? "全收集與生日彩蛋 (11)" : "全收集与生日彩蛋 (11)"), Array(1112...1122))
        ]
    }
    
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
                
                List(sections[selectedSection].ids, id: \.self) { voiceId in
                    Button(action: { manager.playVoice(id: voiceId) }) {
                        HStack {
                            Image(systemName: manager.currentPlayingId == voiceId && manager.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text("[\(manager.characterForVoiceId(voiceId).displayName(manager.language))] #\(voiceId)")
                                    .font(.subheadline.bold())
                                Text("VOICE_DB-\(String(format: "%010d", voiceId))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if manager.currentPlayingId == voiceId && manager.isPlaying {
                                Text(manager.language == .en ? "Playing" : (manager.language == .zhHant ? "播放中" : "播放中"))
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle(manager.language == .en ? "Verified Character Voice DB" : (manager.language == .zhHant ? "已校準純享角色語音庫" : "已校准纯享角色语音库"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(manager.language == .en ? "Done" : "完成") { dismiss() }
                }
            }
        }
    }
}
