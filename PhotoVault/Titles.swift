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

    /// 後台 / 兌換碼可以發的（7 / 8 / 9）＋ 管理員
    static var grantable: [TitleDef] { all.filter { ["dad", "grand", "rich", "admin"].contains($0.key) } }
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
        .overlay { if title.tier >= 3 { starField } }
        .clipShape(Capsule())
        .shadow(color: title.glow.opacity(shadowOpacity), radius: shadowRadius)
        .shadow(color: title.glow.opacity(shadowOpacity * 0.55), radius: shadowRadius * 2.1)
        .fixedSize()
        .onAppear {
            guard animated, title.tier >= 1 else { return }
            withAnimation(.easeInOut(duration: title.tier >= 2 ? 3.4 : 4.6)
                .repeatForever(autoreverses: false)) { sweeping = true }
            if title.tier >= 3 {
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) { spin = 360 }
            }
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
        default: return 0.62
        }
    }

    private var shadowRadius: CGFloat {
        switch title.tier {
        case 0:  return 0
        case 1:  return 3.5 * size
        case 2:  return 5 * size
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
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * 0.26)
                    .rotationEffect(.degrees(16))
                    .offset(x: sweeping ? geo.size.width * 1.25 : -geo.size.width * 0.45)
                    .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
        }
    }

    /// 9 號的環形星芒
    @ViewBuilder
    private var starField: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: i == 0 ? 3.4 * size : 2.4 * size,
                           height: i == 0 ? 3.4 * size : 2.4 * size)
                    .shadow(color: title.glow, radius: 3 * size)
                    .offset(x: (i % 2 == 0 ? 1 : -1) * (28 + CGFloat(i) * 7) * size,
                            y: (i % 3 == 0 ? -1 : 1) * (5 + CGFloat(i % 3) * 3) * size)
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
        LazyVGrid(columns: cols, spacing: 6, alignment: .leading) {
            ForEach(list.prefix(9)) { t in
                TitleChip(title: t, size: 0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
