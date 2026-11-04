import SwiftUI

// MARK: - 稱號膠囊
//
// 效能重點（v37）：
// 原本每個動畫都用 withAnimation(.repeatForever) 各自跑，一個稱號就三、四條動畫，
// 主頁同時掛十幾個稱號就是幾十條永遠在跑的動畫；切頁回來時又整批重新啟動，
// 所以會看到「點別的再回來卡一下」。
// 現在改成：整個稱號只開一條時間軸，所有光效用同一個時間算相位，
// 而且時間用絕對時間推導，切頁回來不會重新從 0 開始，也就沒有跳格。

struct TitleChip: View {
    let title: TitleDef
    var size: CGFloat = 1        // 縮放係數
    var animated: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = false

    private var h: CGFloat { 30 * size }
    private var icon: CGFloat { 18.5 * size }

    /// 只有真的在畫面上、App 在前景、而且這階有光效時才跑時間軸
    private var live: Bool {
        animated && onScreen && scenePhase == .active && title.tier >= 1
    }

    var body: some View {
        if let banner = title.banner {
            bannerBody(banner)
        } else {
            capsuleBody
        }
    }

    // MARK: 名牌型（整條圖，文字與雕件都畫在圖裡）
    //
    // 這幾款是限量名牌，不是「小圖標 + 文字」的膠囊，
    // 所以直接照原圖比例擺，長得比一般稱號稍大一點，
    // 光暈是圖裡自帶的，這裡只補一層會呼吸的外發光。

    /// 名牌型稱號的顯示高度
    /// 這幾款的字是畫在圖裡的，佔圖高約 20%，所以要比一般膠囊大一點才看得清；
    /// 太小的地方（動態卡片）就讓它維持在 30 上下，不去硬撐版面。
    private var bannerH: CGFloat { max(30, 56 * size) }

    @ViewBuilder
    private func bannerBody(_ name: String) -> some View {
        if live {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
                bannerImage(name, t: ctx.date.timeIntervalSince1970)
            }
            .fixedSize()
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
        } else {
            bannerImage(name, t: 0)
                .fixedSize()
        }
    }

    // MARK: 名牌動效（v43）
    //
    // 上一版只有 1% 縮放 + 極輕的陰影變化，肉眼等於不動；而且素材 PNG 裡帶著
    // 一整塊深紫底（含三圈鋪滿畫面的光暈），貼在稱號格上就是一張貼紙。
    // 現在素材只留牌體（真透明），這裡改成四層真的會動的東西：
    //   ① 牌後柔光：徑向光暈隨呼吸明暗，牌子像是自己發光，不是貼上去
    //   ② 流光：一道斜向亮帶週期性掃過，只用牌形做遮罩，光不會跑到牌外
    //   ③ 描邊發光：外圈陰影兩層一起呼吸，邊緣會亮起來
    //   ④ 微浮動：上下 1pt 擺動 + 0.8% 縮放，靜止畫面也有生命感

    private func bannerImage(_ name: String, t: Double) -> some View {
        let breathe = t == 0 ? 0.5 : (sin(t * 1.55) + 1) / 2
        let floatY = t == 0 ? 0 : CGFloat(sin(t * 1.05)) * (0.9 * size)
        let sweep = CGFloat((t * 0.34).truncatingRemainder(dividingBy: 1))

        return Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: bannerH)
            .background {
                // ① 牌後柔光：橢圓徑向，範圍只到牌外一圈，不會形成方塊
                RadialGradient(colors: [title.glow.opacity(0.34 + 0.26 * breathe),
                                        title.glow.opacity(0.0)],
                               center: .center,
                               startRadius: 0,
                               endRadius: bannerH * 1.35)
                    .scaleEffect(x: 0.92, y: 0.82)
                    .blur(radius: bannerH * 0.10)
                    .opacity(t == 0 ? 0.55 : 1)
            }
            .overlay {
                // ② 流光掃過（t == 0 時不畫，避免靜態場合多一層）
                if t != 0 {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            stops: [.init(color: .white.opacity(0.0), location: 0.00),
                                    .init(color: .white.opacity(0.30), location: 0.38),
                                    .init(color: .white.opacity(0.78), location: 0.50),
                                    .init(color: .white.opacity(0.30), location: 0.62),
                                    .init(color: .white.opacity(0.0), location: 1.00)],
                            startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.44)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -w * 0.55 + sweep * (w * 1.70))
                        .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                    .mask {
                        Image(name)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    }
                }
            }
            .shadow(color: title.glow.opacity(0.24 + 0.52 * breathe),
                    radius: 3 + 9 * breathe, y: 0.5)
            .shadow(color: title.glow.opacity(0.10 + 0.30 * breathe),
                    radius: 9 + 17 * breathe)
            .scaleEffect(1 + 0.008 * breathe)
            .offset(y: floatY)
    }

    private var capsuleBody: some View {
        core
            .overlay {
                if live {
                    TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                        insideEffects(t: ctx.date.timeIntervalSince1970)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(Capsule())
            .overlay {
                if live, title.tier >= 6 {
                    TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                        shardEffects(t: ctx.date.timeIntervalSince1970)
                    }
                    .padding(-10 * size)
                    .allowsHitTesting(false)
                }
            }
            .overlay { if title.tier >= 4 { outerRing } }
            .shadow(color: title.glow.opacity(shadowOpacity), radius: shadowRadius)
            .shadow(color: title.glow.opacity(shadowOpacity * 0.55), radius: shadowRadius * 2.1)
            .fixedSize()
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }

    // MARK: 本體

    private var core: some View {
        HStack(spacing: 6 * size) {
            Image(title.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: icon, height: icon)

            nameLabel
        }
        .padding(.leading, 7 * size)
        .padding(.trailing, 12 * size)
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
    }

    // MARK: 相位（全部由絕對時間推導，切頁回來接著走，不會重播）

    private func sweepProgress(_ t: Double) -> CGFloat {
        let d = sweepDuration
        let r = t.truncatingRemainder(dividingBy: d)
        return CGFloat(r / d)
    }

    private func spinAngle(_ t: Double) -> Double {
        let period: Double = title.tier >= 6 ? 14 : 20
        return 360 * (t.truncatingRemainder(dividingBy: period) / period)
    }

    private func blinkValue(_ t: Double) -> Double {
        (1 - cos(2 * .pi * t / 2.3)) / 2
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

    // MARK: 內層光效

    private func insideEffects(t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let ht = geo.size.height
            let p = sweepProgress(t)

            ZStack {
                if title.tier >= 1 { sweepBand(w: w, p: p) }
                if title.tier >= 5 { backSweepBand(w: w, p: p) }
                if title.tier >= 6 { abyssStreamBand(w: w, p: p) }
                if title.tier >= 3 { starField(angle: spinAngle(t)) }
                if title.tier >= 6 { obsidianSparkle(t: t) }
            }
            .frame(width: w, height: ht)
        }
    }

    private func sweepBand(w: CGFloat, p: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear,
                                           .white.opacity(title.tier >= 4 ? 0.72 : 0.55),
                                           .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: w * (title.tier >= 4 ? 0.32 : 0.26), height: h * 2.4)
            .rotationEffect(.degrees(16))
            .offset(x: -w * 0.95 + p * w * 1.7)
            .blendMode(.plusLighter)
    }

    private func backSweepBand(w: CGFloat, p: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, title.edge.opacity(0.45), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: w * 0.22, height: h * 2.4)
            .rotationEffect(.degrees(-16))
            .offset(x: w * 0.75 - p * w * 1.75)
            .blendMode(.plusLighter)
    }

    /// 深淵內緣：一道沿著膠囊流動的紫金光帶
    private func abyssStreamBand(w: CGFloat, p: CGFloat) -> some View {
        Capsule()
            .strokeBorder(
                LinearGradient(colors: [.clear,
                                        Color(red: 0.92, green: 0.82, blue: 1.0).opacity(0.95),
                                        Color(red: 1.0, green: 0.90, blue: 0.70).opacity(0.75),
                                        .clear],
                               startPoint: .leading, endPoint: .trailing),
                lineWidth: 1.7 * size)
            .blur(radius: 1.0 * size)
            .frame(width: w, height: h)
            .offset(x: -w * 0.7 + p * w * 1.4)
    }

    /// 環形星芒
    private func starField(angle: Double) -> some View {
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
        .rotationEffect(.degrees(angle))
    }

    /// 黑曜石面上的紫晶碎點，一閃一閃
    private func obsidianSparkle(t: Double) -> some View {
        Canvas { g, sz in
            for i in 0..<16 {
                let ph = t * (1.05 + Double(i % 5) * 0.22) + Double(i) * 1.63
                let a = (sin(ph) + 1) / 2
                let fx = 0.08 + Double((i * 37) % 86) / 100.0
                let fy = 0.12 + Double((i * 61) % 74) / 100.0
                let x = sz.width * fx
                let y = sz.height * fy
                let r = (0.5 + a * 1.45) * max(sz.height / 30, 0.7)
                let col = (i % 3 == 0)
                    ? Color(red: 1.0, green: 0.88, blue: 0.66)
                    : Color(red: 0.78, green: 0.62, blue: 1.0)
                g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(col.opacity(0.08 + a * 0.85)))
                if i % 4 == 0 && a > 0.55 {
                    let L = r * 3.4
                    var cross = Path()
                    cross.move(to: CGPoint(x: x - L, y: y))
                    cross.addLine(to: CGPoint(x: x + L, y: y))
                    cross.move(to: CGPoint(x: x, y: y - L * 0.62))
                    cross.addLine(to: CGPoint(x: x, y: y + L * 0.62))
                    g.stroke(cross,
                             with: .color(col.opacity((a - 0.55) * 1.5)),
                             lineWidth: max(0.6, sz.height / 60))
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    // MARK: 外層紫晶（畫在膠囊之外）

    private func shardEffects(t: Double) -> some View {
        GeometryReader { geo in
            Canvas { g, sz in
                for i in 0..<14 {
                    drawShard(g, sz: sz, t: t, i: i)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// 單顆紫晶
    private func drawShard(_ g: GraphicsContext, sz: CGSize, t: Double, i: Int) {
        let ph: Double = t * (0.75 + Double(i % 5) * 0.26) + Double(i) * 1.37
        let a: Double = (sin(ph) + 1) / 2
        let u: Double = Double((i * 47) % 100) / 100.0
        let dx: Double = (u - 0.5) * 2.0
        let edge: Double = max(0.0, 1.0 - dx * dx).squareRoot()

        let x: CGFloat = sz.width * CGFloat(u)
        let mid: CGFloat = sz.height / 2
        let sign: CGFloat = (i % 2 == 0) ? -1 : 1
        let spread: CGFloat = 0.62 + CGFloat(edge) * 0.42
        let y: CGFloat = mid + sign * mid * spread
        let base: CGFloat = max(sz.height / 34, 0.6)
        let r: CGFloat = (0.9 + CGFloat(a) * 2.1) * base

        let col: Color = (i % 5 == 0)
            ? Color(red: 1.0, green: 0.90, blue: 0.70)
            : Color(red: 0.74, green: 0.55, blue: 1.0)
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        g.fill(Path(ellipseIn: rect), with: .color(col.opacity(0.05 + a * 0.8)))

        if i % 4 == 0 {
            let L: CGFloat = r * 3.0
            var cross = Path()
            cross.move(to: CGPoint(x: x - L, y: y))
            cross.addLine(to: CGPoint(x: x + L, y: y))
            cross.move(to: CGPoint(x: x, y: y - L * 0.66))
            cross.addLine(to: CGPoint(x: x, y: y + L * 0.66))
            let glow = Color(red: 0.90, green: 0.80, blue: 1.0).opacity(0.10 + a * 0.6)
            g.stroke(cross, with: .color(glow), lineWidth: max(0.6, sz.height / 52))
        }
    }

    // MARK: 靜態裝飾

    /// 稱號文字：普通是素色，深淵王爵跟著圖標一起跑紫金漸層
    @ViewBuilder
    private var nameLabel: some View {
        if title.tier >= 6 {
            Text(title.name)
                .font(.system(size: 13 * size, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.96, blue: 1.0),
                                 Color(red: 0.86, green: 0.70, blue: 1.0),
                                 Color(red: 0.56, green: 0.34, blue: 0.98),
                                 Color(red: 0.80, green: 0.60, blue: 1.0),
                                 Color(red: 1.0, green: 0.92, blue: 0.74)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .lineLimit(1)
                .fixedSize()
                .shadow(color: Color(red: 0.60, green: 0.40, blue: 1.0).opacity(0.85),
                        radius: 5.5 * size)
                .shadow(color: Color(red: 0.92, green: 0.80, blue: 1.0).opacity(0.38),
                        radius: 1.6 * size)
        } else {
            Text(title.name)
                .font(.system(size: 13 * size, weight: .heavy))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize()
                .shadow(color: title.glow.opacity(title.tier >= 2 ? 0.9 : 0.45), radius: 3 * size)
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

    /// 外圈光環（王爵以上）
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
}

// MARK: - 稱號展示（無框、無上限、自動換行、置中）

struct TitleFlow: View {
    let owned: [String]
    var size: CGFloat = 1.0
    var spacing: CGFloat = 9

    private var list: [TitleDef] {
        owned.compactMap { Titles.find($0) }
    }

    var body: some View {
        FlowLayout(spacing: spacing, lineSpacing: 10, alignment: .center) {
            ForEach(list) { t in
                TitleChip(title: t, size: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// 由左到右排、排不下就換行；每一行可以置中
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [[(LayoutSubview, CGSize)]] {
        var out: [[(LayoutSubview, CGSize)]] = []
        var row: [(LayoutSubview, CGSize)] = []
        var x: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                out.append(row)
                row = []
                x = 0
            }
            row.append((sv, s))
            x += s.width + spacing
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let grouped = rows(maxWidth: maxW, subviews: subviews)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for row in grouped {
            let rowW = row.reduce(CGFloat(0)) { $0 + $1.1.width }
                + spacing * CGFloat(max(0, row.count - 1))
            widest = max(widest, rowW)
            height += (row.map { $0.1.height }.max() ?? 0)
        }
        if grouped.count > 1 {
            height += lineSpacing * CGFloat(grouped.count - 1)
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grouped = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in grouped {
            let rowW = row.reduce(CGFloat(0)) { $0 + $1.1.width }
                + spacing * CGFloat(max(0, row.count - 1))
            let rowH = row.map { $0.1.height }.max() ?? 0

            var x: CGFloat
            switch alignment {
            case .center:  x = bounds.minX + max(0, (bounds.width - rowW) / 2)
            case .trailing: x = bounds.maxX - rowW
            default:       x = bounds.minX
            }

            for (sv, s) in row {
                sv.place(at: CGPoint(x: x, y: y + (rowH - s.height) / 2),
                         anchor: .topLeading,
                         proposal: ProposedViewSize(width: s.width, height: s.height))
                x += s.width + spacing
            }
            y += rowH + lineSpacing
        }
    }
}

/// 舊名字保留，避免其他地方引用不到
typealias TitleGrid = TitleFlow
