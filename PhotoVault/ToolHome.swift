import SwiftUI

// MARK: - 工具路由

enum ToolRoute: String, Identifiable, CaseIterable {
    case speed, link, qrscan, password
    case level, compass, magnet, gravity, barometer, decibel
    case device, location, motionSpeed, lostDevice
    case ocr, qrgen, units, time
    case wifiCheck, docScan, idPhoto, recorder
    case qrStudio, apiLab, domainInfo, baseConv, decider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed:     return "網路診斷"
        case .link:      return "連結安全"
        case .qrscan:    return "掃描二維碼"
        case .password:  return "密碼強度"
        case .level:     return "水平儀"
        case .compass:   return "指南針"
        case .magnet:    return "磁力計"
        case .gravity:   return "重力感測"
        case .barometer: return "氣壓海拔"
        case .decibel:   return "分貝計"
        case .device:    return "設備資訊"
        case .location:  return "定位資訊"
        case .motionSpeed: return "薄荷測速"
        case .lostDevice:  return "遺失找回"
        case .time:      return "時間工具"
        case .ocr:       return "文字辨識"
        case .qrgen:     return "二維碼生成"
        case .units:     return "單位換算"
        case .wifiCheck: return "Wi-Fi 安全檢測"
        case .docScan:   return "文件掃描"
        case .idPhoto:   return "證件照製作"
        case .recorder:  return "錄音機"
        case .qrStudio:  return "QR 工作室"
        case .apiLab:    return "API 測試台"
        case .domainInfo: return "網域資訊"
        case .baseConv:  return "進制轉換"
        case .decider:   return "隨機決策"
        }
    }

    var subtitle: String {
        switch self {
        case .speed:     return "SPEED TEST"
        case .link:      return "LINK GUARD"
        case .qrscan:    return "QR SCANNER"
        case .password:  return "PASSWORD LAB"
        case .level:     return "PRECISION LEVEL"
        case .compass:   return "COMPASS"
        case .magnet:    return "MAGNETOMETER"
        case .gravity:   return "G-FORCE"
        case .barometer: return "BAROMETER"
        case .decibel:   return "SOUND METER"
        case .device:    return "DEVICE SPEC"
        case .location:  return "GPS"
        case .motionSpeed: return "MOTION SPEED"
        case .lostDevice:  return "FIND MY PHONE"
        case .time:      return "TIME TOOLS"
        case .ocr:       return "ON-DEVICE OCR"
        case .qrgen:     return "QR GENERATOR"
        case .units:     return "CONVERTER"
        case .wifiCheck: return "WI-FI SECURITY"
        case .docScan:   return "DOC SCANNER"
        case .idPhoto:   return "ID PHOTO"
        case .recorder:  return "VOICE RECORDER"
        case .qrStudio:  return "QRCODE STUDIO"
        case .apiLab:    return "API WORKBENCH"
        case .domainInfo: return "DOMAIN INTEL"
        case .baseConv:  return "BASE CONVERTER"
        case .decider:   return "DECISION ENGINE"
        }
    }

    var icon: String {
        switch self {
        case .speed:     return "dot.radiowaves.left.and.right"
        case .link:      return "link.badge.plus"
        case .qrscan:    return "qrcode.viewfinder"
        case .password:  return "lock.shield"
        case .level:     return "level"
        case .compass:   return "location.north.circle"
        case .magnet:    return "waveform.path"
        case .gravity:   return "arrow.down.to.line"
        case .barometer: return "barometer"
        case .decibel:   return "speaker.wave.3"
        case .device:    return "iphone"
        case .location:  return "location.fill"
        case .motionSpeed: return "speedometer"
        case .lostDevice:  return "location.magnifyingglass"
        case .time:      return "clock.badge.checkmark"
        case .ocr:       return "text.viewfinder"
        case .qrgen:     return "qrcode"
        case .units:     return "arrow.left.arrow.right"
        case .wifiCheck: return "wifi.exclamationmark"
        case .docScan:   return "doc.viewfinder"
        case .idPhoto:   return "person.crop.rectangle"
        case .recorder:  return "waveform"
        case .qrStudio:  return "wand.and.stars"
        case .apiLab:    return "chevron.left.forwardslash.chevron.right"
        case .domainInfo: return "globe"
        case .baseConv:  return "number"
        case .decider:   return "die.face.5"
        }
    }

    var accent: Color {
        switch self {
        case .speed:     return TT.teal
        case .link:      return TT.mint
        case .qrscan:    return TT.blue
        case .password:  return TT.rose
        case .level:     return TT.mint
        case .compass:   return TT.blue
        case .magnet:    return TT.indigo
        case .gravity:   return TT.violet
        case .barometer: return TT.teal
        case .decibel:   return TT.amber
        case .device:    return TT.blue
        case .location:  return TT.lime
        case .motionSpeed: return TT.amber
        case .lostDevice:  return TT.mint
        case .time:      return TT.teal
        case .ocr:       return TT.blue
        case .qrgen:     return TT.indigo
        case .units:     return TT.amber
        case .wifiCheck: return TT.rose
        case .docScan:   return TT.blue
        case .idPhoto:   return TT.amber
        case .recorder:  return TT.violet
        case .qrStudio:  return TT.violet
        case .apiLab:    return TT.teal
        case .domainInfo: return TT.blue
        case .baseConv:  return TT.amber
        case .decider:   return TT.lime
        }
    }
}

// MARK: - 分組

struct ToolGroup: Identifiable {
    let id = UUID()
    let name: String
    let en: String
    let accent: Color
    let tools: [ToolRoute]
}

// MARK: - 主頁

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var route: ToolRoute?
    @State private var appeared = false

    private let groups: [ToolGroup] = [
        ToolGroup(name: "網路與安全", en: "NETWORK & SECURITY", accent: TT.teal,
                  tools: [.speed, .link, .qrscan, .password]),
        ToolGroup(name: "感測器", en: "SENSORS", accent: TT.violet,
                  tools: [.level, .compass, .magnet, .gravity, .barometer, .decibel]),
        ToolGroup(name: "資訊與位置", en: "DEVICE & POSITION", accent: TT.blue,
                  tools: [.device, .location, .motionSpeed, .lostDevice]),
        ToolGroup(name: "影像與計算", en: "IMAGING & MATH", accent: TT.amber,
                  tools: [.ocr, .qrgen, .units, .time])
    ]

    private var localToolCount: Int {
        groups.reduce(0) { $0 + $1.tools.count }
    }

    var body: some View {
        ZStack {
            Backdrop()
            TechGrid()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    FavoriteSection { tool in
                        route = tool
                    }
                    ForEach(groups) { group in
                        groupSection(group)
                    }
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 132)
            }
        }
        .fullScreenCover(item: $route) { r in
            ToolDestinationView(route: r)
                .environmentObject(store)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            LostModeManager.shared.configure(store: store)
            LocationBeacon.shared.ping { lat, lon, alt, acc, spd, crs, addr, place in
                Task { @MainActor in
                    store.reportLocation(lat: lat, lon: lon, alt: alt, acc: acc,
                                         speed: spd, course: crs,
                                         address: addr, place: place)
                }
            }
        }
    }

    // MARK: 標題

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    MintDragonMark(size: 44)
                    Text("源孑工具箱")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 7) {
                    Text("YUANJIE TOOLKIT")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(TT.mint.opacity(0.7))
                    Rectangle()
                        .fill(TT.mint.opacity(0.25))
                        .frame(width: 22, height: 1)
                    Text("\(localToolCount) 個工具")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text("測速、感測器、影像辨識與小算盤，全部在手機本機完成")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    // MARK: 分組區塊

    private func groupSection(_ group: ToolGroup) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(group.accent)
                    .frame(width: 3, height: 13)
                    .shadow(color: group.accent.opacity(0.7), radius: 5)
                Text(group.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(group.en)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.2))
                Rectangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.09),
                                                  Color.white.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11),
                                GridItem(.flexible(), spacing: 11)],
                      spacing: 11) {
                ForEach(group.tools) { tool in
                    ToolCard(tool: tool) {
                        route = tool
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
        }
    }

    // MARK: 底部

    private var footerNote: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9.5))
                Text("所有量測與辨識都在本機處理，不上傳伺服器")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.22))
            Text("YUANJIE TECHNOLOGY · v1.0")
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.13))
        }
        .padding(.top, 6)
    }

}

// MARK: - 目的地

struct ToolDestinationView: View {
    let route: ToolRoute
    @EnvironmentObject var store: AppStore

    var body: some View {
        switch route {
        case .speed:     SpeedTestView()
        case .link:      LinkCheckView()
        case .qrscan:    QRScanView()
        case .password:  PasswordCheckView()
        case .level:     LevelView()
        case .compass:   CompassView()
        case .magnet:    MagnetView()
        case .gravity:   GravityView()
        case .barometer: BarometerView()
        case .decibel:   DecibelView()
        case .device:    DeviceInfoView()
        case .location:  LocationView()
        case .motionSpeed: MotionSpeedView()
        case .lostDevice:  LostDeviceView()
        case .time:      TimeToolsView()
        case .ocr:       OCRView()
        case .qrgen:     QRGenerateView()
        case .units:     UnitConvertView()
        case .wifiCheck: WifiCheckView()
        case .docScan:   DocScanView()
        case .idPhoto:   IDPhotoView()
        case .recorder:  RecorderView()
        case .qrStudio:  QRStudioView()
        case .apiLab:    APILabView()
        case .domainInfo: DomainInfoView()
        case .baseConv:  BaseConvertView()
        case .decider:   DecisionEngineView()
        }
    }
}
