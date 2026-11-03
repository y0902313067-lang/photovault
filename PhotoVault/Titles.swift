import SwiftUI

// MARK: - 稱號定義

struct TitleDef: Identifiable, Hashable {
    let key: String
    let name: String
    let image: String
    let colors: [Color]
    let edge: Color
    let glow: Color
    let tier: Int          // 0 = 樸素, 1 = 一層金光, 2 = 雙層輝光, 3 = 最強輝光
    let how: String        // 取得方式

    var id: String { key }

    static func == (a: TitleDef, b: TitleDef) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

enum Titles {
    static let all: [TitleDef] = [
        TitleDef(key: "speed", name: "測速達人", image: "tt1",
                 colors: [Color(red: 0.12, green: 0.31, blue: 0.53),
                          Color(red: 0.25, green: 0.56, blue: 0.77),
                          Color(red: 0.40, green: 0.76, blue: 0.88)],
                 edge: Color(red: 0.62, green: 0.86, blue: 1.0),
                 glow: Color(red: 0.45, green: 0.78, blue: 1.0),
                 tier: 0,
                 how: "累積經過 10 個限速路段"),

        TitleDef(key: "diag", name: "診斷專家", image: "tt2",
                 colors: [Color(red: 0.05, green: 0.35, blue: 0.31),
                          Color(red: 0.09, green: 0.63, blue: 0.55),
                          Color(red: 0.25, green: 0.85, blue: 0.72)],
                 edge: Color(red: 0.55, green: 0.95, blue: 0.85),
                 glow: Color(red: 0.35, green: 0.90, blue: 0.78),
                 tier: 0,
                 how: "完成一次網路診斷"),

        TitleDef(key: "pw", name: "安全密碼", image: "tt3",
                 colors: [Color(red: 0.10, green: 0.36, blue: 0.23),
                          Color(red: 0.18, green: 0.61, blue: 0.37),
                          Color(red: 0.33, green: 0.79, blue: 0.50)],
                 edge: Color(red: 0.60, green: 0.96, blue: 0.74),
                 glow: Color(red: 0.38, green: 0.88, blue: 0.58),
                 tier: 0,
                 how: "輸入一組 81 分的密碼"),

        TitleDef(key: "walk", name: "健走達人", image: "tt4",
                 colors: [Color(red: 0.42, green: 0.23, blue: 0.07),
                          Color(red: 0.72, green: 0.45, blue: 0.20),
                          Color(red: 0.88, green: 0.63, blue: 0.35)],
                 edge: Color(red: 1.0, green: 0.84, blue: 0.62),
                 glow: Color(red: 1.0, green: 0.72, blue: 0.42),
                 tier: 0,
                 how: "累積步行 10 公里"),

        TitleDef(key: "db", name: "獅吼功", image: "tt5",
                 colors: [Color(red: 0.43, green: 0.12, blue: 0.16),
                          Color(red: 0.70, green: 0.23, blue: 0.28),
                          Color(red: 0.88, green: 0.38, blue: 0.44)],
                 edge: Color(red: 1.0, green: 0.66, blue: 0.70),
                 glow: Color(red: 1.0, green: 0.45, blue: 0.52),
                 tier: 0,
                 how: "使用分貝計測到 100 分貝以上"),

        TitleDef(key: "fx", name: "外交官", image: "tt6",
                 colors: [Color(red: 0.16, green: 0.21, blue: 0.38),
                          Color(red: 0.29, green: 0.37, blue: 0.66),
                          Color(red: 0.49, green: 0.56, blue: 0.85)],
                 edge: Color(red: 0.72, green: 0.79, blue: 1.0),
                 glow: Color(red: 0.60, green: 0.68, blue: 1.0),
                 tier: 0,
                 how: "查看即時匯率 3 次"),

        TitleDef(key: "dad", name: "金主爸爸", image: "tt7",
                 colors: [Color(red: 0.55, green: 0.38, blue: 0.08),
                          Color(red: 0.86, green: 0.66, blue: 0.22),
                          Color(red: 0.98, green: 0.84, blue: 0.44)],
                 edge: Color(red: 1.0, green: 0.88, blue: 0.56),
                 glow: Color(red: 1.0, green: 0.78, blue: 0.32),
                 tier: 1,
                 how: "由官方贈與，或輸入兌換碼"),

        TitleDef(key: "grand", name: "金主爺爺", image: "tt8",
                 colors: [Color(red: 0.62, green: 0.42, blue: 0.05),
                          Color(red: 0.95, green: 0.72, blue: 0.20),
                          Color(red: 1.0, green: 0.92, blue: 0.62)],
                 edge: Color(red: 1.0, green: 0.93, blue: 0.70),
                 glow: Color(red: 1.0, green: 0.82, blue: 0.36),
                 tier: 2,
                 how: "由官方贈與，或輸入兌換碼"),

        TitleDef(key: "rich", name: "超級富豪", image: "tt9",
                 colors: [Color(red: 0.30, green: 0.16, blue: 0.52),
                          Color(red: 0.62, green: 0.42, blue: 0.80),
                          Color(red: 1.0, green: 0.95, blue: 0.78),
                          Color(red: 0.86, green: 0.66, blue: 0.24)],
                 edge: Color(red: 1.0, green: 0.96, blue: 0.82),
                 glow: Color(red: 0.86, green: 0.72, blue: 1.0),
                 tier: 3,
                 how: "由官方贈與，或輸入兌換碼"),

        // 三階王爵：黑金一星／二星 → 金，三星／四星再疊血鑽，五星三個全拿
        TitleDef(key: "duke1", name: "黑金王爵", image: "tt11",
                 colors: [Color(red: 0.09, green: 0.07, blue: 0.06),
                          Color(red: 0.24, green: 0.18, blue: 0.07),
                          Color(red: 0.55, green: 0.40, blue: 0.12),
                          Color(red: 0.93, green: 0.74, blue: 0.32)],
                 edge: Color(red: 1.0, green: 0.90, blue: 0.60),
                 glow: Color(red: 1.0, green: 0.78, blue: 0.30),
                 tier: 4,
                 how: "黑金一星／二星自動獲得"),

        TitleDef(key: "duke2", name: "血鑽王爵", image: "tt12",
                 colors: [Color(red: 0.08, green: 0.03, blue: 0.04),
                          Color(red: 0.30, green: 0.04, blue: 0.08),
                          Color(red: 0.55, green: 0.09, blue: 0.14),
                          Color(red: 0.82, green: 0.22, blue: 0.26)],
                 edge: Color(red: 1.0, green: 0.72, blue: 0.62),
                 glow: Color(red: 1.0, green: 0.25, blue: 0.32),
                 tier: 5,
                 how: "黑金三星／四星自動獲得"),

        TitleDef(key: "duke3", name: "深淵王爵", image: "tt13",
                 colors: [Color(red: 0.04, green: 0.03, blue: 0.09),
                          Color(red: 0.14, green: 0.08, blue: 0.28),
                          Color(red: 0.33, green: 0.18, blue: 0.60),
                          Color(red: 0.62, green: 0.42, blue: 0.94)],
                 edge: Color(red: 0.86, green: 0.76, blue: 1.0),
                 glow: Color(red: 0.62, green: 0.42, blue: 1.0),
                 tier: 6,
                 how: "黑金五星自動獲得（最高階）"),

        TitleDef(key: "admin", name: "官方管理員", image: "tt10",
                 colors: [Color(red: 0.10, green: 0.24, blue: 0.48),
                          Color(red: 0.24, green: 0.46, blue: 0.82),
                          Color(red: 0.72, green: 0.85, blue: 1.0)],
                 edge: Color(red: 0.80, green: 0.90, blue: 1.0),
                 glow: Color(red: 0.55, green: 0.75, blue: 1.0),
                 tier: 1,
                 how: "僅由官方後台授予")
    ]

    static let order: [String: Int] = {
        var m: [String: Int] = [:]
        for (i, t) in all.enumerated() { m[t.key] = i }
        return m
    }()

    static func find(_ key: String) -> TitleDef? { all.first { $0.key == key } }

    /// 後台 / 兌換碼可以發的（7 / 8 / 9 ＋ 三階王爵）＋ 管理員
    static var grantable: [TitleDef] {
        all.filter { ["dad", "grand", "rich", "duke1", "duke2", "duke3", "admin"].contains($0.key) }
    }

    /// 會員等級自動帶的王爵稱號（只往上疊，升星不收回）
    static func dukeTitles(for level: MemberLevel) -> [String] {
        switch level {
        case .black1, .black2:  return ["duke1"]
        case .black3, .black4:  return ["duke1", "duke2"]
        case .black5:           return ["duke1", "duke2", "duke3"]
        default:                return []
        }
    }

    /// 把後台／兌換碼發的稱號，與等級自動獲得的王爵合併（去重）
    static func resolved(_ owned: [String], level: MemberLevel) -> [String] {
        var list = owned
        for k in dukeTitles(for: level) where !list.contains(k) { list.append(k) }
        return list
    }
}

// MARK: - 稱號膠囊

struct TitleChip: View {
    let title: TitleDef
    var size: CGFloat = 1        // 縮放係數
    var animated: Bool = true

    @State private var sweeping = false
    @State private var spin: Double = 0

    private var h: CGFloat { 26 * size }
    private var icon: CGFloat { 16 * size }

    var body: some View {
        HStack(spacing: 5 * size) {
            Image(title.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: icon, height: icon)

            Text(title.name)
                .font(.system(size: 11.5 * size, weight: .heavy))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize()
                .shadow(color: title.glow.opacity(title.tier >= 2 ? 0.9 : 0.45), radius: 3 * size)
        }
        .padding(.leading, 6 * size)
        .padding(.trailing, 11 * size)
        .frame(height: h)
        .background(
            Capsule().fill(LinearGradient(colors: title.colors,
                                          startPoint: .topLeading,
                                          endPoint: .bottomTrailing))
        )
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [title.edge.opacity(0.85),
                                        title.edge.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.9 * size)
        )
        .overlay(sheen)
        .overlay(alignment: .topLeading) { sweepLayer }
        .overlay(alignment: .topLeading) { if title.tier >= 5 { backSweepLayer } }
        .overlay { if title.tier >= 3 { starField } }
        .clipShape(Capsule())
        .overlay { if title.tier >= 4 { outerRing } }
        .shadow(color: title.glow.opacity(shadowOpacity), radius: shadowRadius)
        .shadow(color: title.glow.opacity(shadowOpacity * 0.55), radius: shadowRadius * 2.1)
        .fixedSize()
        .onAppear {
            guard animated, title.tier >= 1 else { return }
            withAnimation(.easeInOut(duration: sweepDuration)
                .repeatForever(autoreverses: false)) { sweeping = true }
            if title.tier >= 3 {
                withAnimation(.linear(duration: title.tier >= 6 ? 14 : 20)
                    .repeatForever(autoreverses: false)) { spin = 360 }
            }
        }
    }

    /// 掃光週期：越往上越快
    private var sweepDuration: Double {
        switch title.tier {
        case 0, 1: return 4.6
        case 2, 3: return 3.4
        case 4:    return 2.9
        case 5:    return 2.5
        default:   return 2.0
        }
    }

    private var textColor: Color {
        switch title.tier {
        case 0:  return .white
        default: return Color(red: 1.0, green: 0.97, blue: 0.86)
        }
    }

    private var shadowOpacity: Double {
        switch title.tier {
        case 0:  return 0.0
        case 1:  return 0.34
        case 2:  return 0.48
        case 4:  return 0.72
        case 5:  return 0.82
        case 6:  return 0.92
        default: return 0.62
        }
    }

    private var shadowRadius: CGFloat {
        switch title.tier {
        case 0:  return 0
        case 1:  return 3.5 * size
        case 2:  return 5 * size
        case 4:  return 7.5 * size
        case 5:  return 8.5 * size
        case 6:  return 10 * size
        default: return 6.5 * size
        }
    }

    /// 上緣那道柔光
    private var sheen: some View {
        Capsule()
            .fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(title.tier >= 2 ? 0.34 : 0.24), location: 0.0),
                    .init(color: .white.opacity(0.04), location: 0.42),
                    .init(color: .clear, location: 0.62)
                ], startPoint: .top, endPoint: .bottom)
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    /// 掃光
    @ViewBuilder
    private var sweepLayer: some View {
        if title.tier >= 1 {
            GeometryReader { geo in
                Rectangle()
                    .fill(LinearGradient(colors: [.clear,
                                                   .white.opacity(title.tier >= 4 ? 0.72 : 0.55),
                                                   .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * (title.tier >= 4 ? 0.32 : 0.26))
                    .rotationEffect(.degrees(16))
                    .offset(x: sweeping ? geo.size.width * 1.25 : -geo.size.width * 0.45)
                    .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
        }
    }

    /// 第二道反向掃光（血鑽以上）
    @ViewBuilder
    private var backSweepLayer: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, title.edge.opacity(0.45), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * 0.22)
                .rotationEffect(.degrees(-16))
                .offset(x: sweeping ? -geo.size.width * 0.5 : geo.size.width * 1.25)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    /// 外圈光環（王爵以上，深淵再加一圈外擴）
    private var outerRing: some View {
        ZStack {
            Capsule()
                .strokeBorder(title.edge.opacity(title.tier >= 6 ? 0.80 : 0.52),
                              lineWidth: 0.8 * size)
                .blur(radius: 1.6 * size)
            if title.tier >= 6 {
                Capsule()
                    .strokeBorder(title.glow.opacity(0.58), lineWidth: 0.6 * size)
                    .blur(radius: 3.4 * size)
                    .padding(-1.8 * size)
            }
        }
        .allowsHitTesting(false)
    }

    /// 9 號以上的環形星芒
    @ViewBuilder
    private var starField: some View {
        ZStack {
            ForEach(0..<(title.tier >= 6 ? 12 : (title.tier >= 5 ? 10 : 8)), id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: (i == 0 ? 3.4 : 2.4) * (title.tier >= 5 ? 1.18 : 1) * size,
                           height: (i == 0 ? 3.4 : 2.4) * (title.tier >= 5 ? 1.18 : 1) * size)
                    .shadow(color: title.glow, radius: 3 * size)
                    .offset(x: CGFloat(i % 2 == 0 ? 1 : -1) * (28 + CGFloat(i) * 7) * size,
                            y: CGFloat(i % 3 == 0 ? -1 : 1) * (5 + CGFloat(i % 3) * 3) * size)
                    .opacity(0.75)
            }
        }
        .rotationEffect(.degrees(spin))
        .allowsHitTesting(false)
    }
}

// MARK: - 稱號九宮格

struct TitleGrid: View {
    let owned: [String]

    private var list: [TitleDef] {
        owned.compactMap { Titles.find($0) }
            .sorted { (Titles.order[$0.key] ?? 99) < (Titles.order[$1.key] ?? 99) }
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading),
                         count: 3)
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(list.prefix(12)) { t in
                TitleChip(title: t, size: 0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
