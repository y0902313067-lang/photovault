import SwiftUI

// MARK: - 工具路由

enum ToolRoute: String, Identifiable, CaseIterable {
    case speed, link, qrscan, password
    case level, compass, magnet, gravity, barometer, decibel
    case device, location, time
    case ocr, qrgen, units

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
        case .time:      return "時間工具"
        case .ocr:       return "文字辨識"
        case .qrgen:     return "二維碼生成"
        case .units:     return "單位換算"
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
        case .time:      return "TIME TOOLS"
        case .ocr:       return "ON-DEVICE OCR"
        case .qrgen:     return "QR GENERATOR"
        case .units:     return "CONVERTER"
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
        case .time:      return "clock.badge.checkmark"
        case .ocr:       return "text.viewfinder"
        case .qrgen:     return "qrcode"
        case .units:     return "arrow.left.arrow.right"
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
        case .time:      return TT.teal
        case .ocr:       return TT.blue
        case .qrgen:     return TT.indigo
        case .units:     return TT.amber
        }
    }
}

// MARK: - 分組

private struct ToolGroup: Identifiable {
    let id = UUID()
    let name: String
    let en: String
    let accent: Color
    let tools: [ToolRoute]
}

// MARK: - 主頁

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showProfile = false
    @State private var route: ToolRoute?
    @State private var appeared = false

    private let groups: [ToolGroup] = [
        ToolGroup(name: "網路與安全", en: "NETWORK & SECURITY", accent: TT.teal,
                  tools: [.speed, .link, .qrscan, .password]),
        ToolGroup(name: "感測器", en: "SENSORS", accent: TT.violet,
                  tools: [.level, .compass, .magnet, .gravity, .barometer, .decibel]),
        ToolGroup(name: "資訊與位置", en: "DEVICE & POSITION", accent: TT.blue,
                  tools: [.device, .location, .time]),
        ToolGroup(name: "影像與計算", en: "IMAGING & MATH", accent: TT.amber,
                  tools: [.ocr, .qrgen, .units])
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Backdrop()
            TechGrid()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    featured
                    ForEach(groups) { group in
                        groupSection(group)
                    }
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 124)
            }

            avatarButton
        }
        .sheet(isPresented: $showProfile) {
            ProfileView().environmentObject(store)
        }
        .fullScreenCover(item: $route) { r in
            destination(r)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
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
                HStack(spacing: 8) {
                    MintDragonMark(size: 30)
                    Text("薄荷工具箱")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 7) {
                    Text("MINT DRAGON TOOLKIT")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(TT.mint.opacity(0.7))
                    Rectangle()
                        .fill(TT.mint.opacity(0.25))
                        .frame(width: 22, height: 1)
                    Text("\(ToolRoute.allCases.count) 個工具")
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

    // MARK: 主推卡片

    private var featured: some View {
        Button {
            route = .speed
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(colors: [TT.teal.opacity(0.22),
                                                TT.blue.opacity(0.14),
                                                Color.white.opacity(0.04)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [TT.teal.opacity(0.55),
                                                        TT.blue.opacity(0.22),
                                                        Color.white.opacity(0.05)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                lineWidth: 1)
                    )

                HStack(spacing: 15) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [TT.teal, TT.blue],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                            .shadow(color: TT.blue.opacity(0.5), radius: 16, y: 6)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(TT.ink)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("網路診斷")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text("下載 · 上傳 · 延遲 · 抖動")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                        HStack(spacing: 5) {
                            Circle()
                                .fill(TT.mint)
                                .frame(width: 4.5, height: 4.5)
                            Text("即時速度曲線")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(TT.mint.opacity(0.75))
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .shadow(color: TT.blue.opacity(0.2), radius: 24, y: 12)
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
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
                    toolCard(tool)
                }
            }
        }
    }

    private func toolCard(_ tool: ToolRoute) -> some View {
        Button {
            route = tool
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(colors: [tool.accent.opacity(0.9),
                                                        tool.accent.opacity(0.45)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                            .frame(width: 38, height: 38)
                            .shadow(color: tool.accent.opacity(0.35), radius: 10, y: 4)
                        Image(systemName: tool.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TT.ink)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.16))
                        .padding(.top, 3)
                }

                Spacer(minLength: 10)

                Text(tool.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(tool.subtitle)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.22))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(13)
            .frame(height: 112)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [tool.accent.opacity(0.22),
                                                Color.white.opacity(0.05)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            Text("MINT DRAGON TECHNOLOGY · v1.0")
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.13))
        }
        .padding(.top, 6)
    }

    // MARK: 頭像

    private var avatarButton: some View {
        Button {
            showProfile = true
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.62, blue: 1.0),
                                                  Color(red: 0.5, green: 0.4, blue: 0.95)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 58, height: 58)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                if let img = store.avatarImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    .frame(width: 58, height: 58)
            )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 30)
    }

    // MARK: 目的地

    @ViewBuilder
    private func destination(_ r: ToolRoute) -> some View {
        switch r {
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
        case .time:      TimeToolsView()
        case .ocr:       OCRView()
        case .qrgen:     QRGenerateView()
        case .units:     UnitConvertView()
        }
    }
}
