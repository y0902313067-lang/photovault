import SwiftUI

// MARK: - 會員等級

enum MemberLevel: Int, CaseIterable, Identifiable, Codable {
    case common    = 0
    case silver    = 1
    case gold      = 2
    case platinum  = 3
    case black1    = 4
    case black2    = 5
    case black3    = 6
    case black4    = 7
    case black5    = 8

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .common:   return "普通會員"
        case .silver:   return "白銀會員"
        case .gold:     return "黃金會員"
        case .platinum: return "白金會員"
        case .black1:   return "黑金會員一星"
        case .black2:   return "黑金會員二星"
        case .black3:   return "黑金會員三星"
        case .black4:   return "黑金會員四星"
        case .black5:   return "黑金會員五星"
        }
    }

    /// 徽章列表用的短名
    var shortName: String {
        switch self {
        case .common:   return "普通"
        case .silver:   return "白銀"
        case .gold:     return "黃金"
        case .platinum: return "白金"
        case .black1:   return "黑金一星"
        case .black2:   return "黑金二星"
        case .black3:   return "黑金三星"
        case .black4:   return "黑金四星"
        case .black5:   return "黑金五星"
        }
    }

    var imageName: String { "lv\(rawValue + 1)" }

    /// 這個等級怎麼取得（會員分級說明頁用）
    var rule: String {
        switch self {
        case .common:   return "預設等級。App Store 上架後下載即為此級；目前開放下載期間一律給白銀。"
        case .silver:   return "目前下載 App 即為此級。"
        case .gold:     return "由官方贈與，或輸入兌換碼取得。"
        case .platinum: return "由官方贈與，或輸入兌換碼取得。"
        default:        return "由官方贈與，或輸入兌換碼取得。"
        }
    }

    /// 徽章外層光效參數
    var glow: GlowSpec {
        switch self {
        case .common:
            return GlowSpec()
        case .silver:
            return GlowSpec(halo: 0.56, haloOpacity: 0.13,
                            haloColor: Color(red: 0.80, green: 0.88, blue: 1.0))
        case .gold:
            return GlowSpec(halo: 0.60, haloOpacity: 0.26,
                            haloColor: Color(red: 1.0, green: 0.82, blue: 0.42))
        case .platinum:
            return GlowSpec(halo: 0.66, haloOpacity: 0.30,
                            haloColor: Color(red: 1.0, green: 0.36, blue: 0.46))
        case .black1:
            return GlowSpec(halo: 0.58, haloOpacity: 0.22,
                            haloColor: Color(red: 1.0, green: 0.82, blue: 0.44))
        case .black2:
            return GlowSpec(halo: 0.66, haloOpacity: 0.30,
                            haloColor: Color(red: 1.0, green: 0.82, blue: 0.44))
        case .black3:
            return GlowSpec(halo: 0.74, haloOpacity: 0.36,
                            haloColor: Color(red: 1.0, green: 0.84, blue: 0.47),
                            rays: 12, rayOpacity: 0.30, rayColor: Color(red: 1.0, green: 0.90, blue: 0.62))
        case .black4:
            return GlowSpec(halo: 0.82, haloOpacity: 0.42,
                            haloColor: Color(red: 1.0, green: 0.86, blue: 0.51),
                            rays: 12, rayOpacity: 0.46, rayColor: Color(red: 1.0, green: 0.92, blue: 0.68),
                            spinSeconds: 26, ring: true, sparks: 8)
        default:
            return GlowSpec(halo: 0.92, haloOpacity: 0.50,
                            haloColor: Color(red: 1.0, green: 0.89, blue: 0.57),
                            rays: 24, rayOpacity: 0.62, rayColor: Color(red: 1.0, green: 0.94, blue: 0.76),
                            spinSeconds: 18, ring: true, ring2: true, sparks: 14)
        }
    }
}

// MARK: - 光效參數

struct GlowSpec {
    var halo: CGFloat = 0
    var haloOpacity: Double = 0
    var haloColor: Color = .clear
    var rays: Int = 0
    var rayOpacity: Double = 0
    var rayColor: Color = .clear
    var spinSeconds: Double = 0
    var ring: Bool = false
    var ring2: Bool = false
    var sparks: Int = 0

    var hasGlow: Bool { haloOpacity > 0 || rays > 0 }
}

// MARK: - 徽章

struct MemberBadge: View {
    let level: MemberLevel
    var size: CGFloat = 56
    var animated: Bool = true
    /// 光暈可以額外放大，聊天室小尺寸時關掉避免糊
    var glowScale: CGFloat = 1

    @State private var spin: Double = 0
    @State private var pulse = false

    private var g: GlowSpec { level.glow }

    var body: some View {
        ZStack {
            if g.haloOpacity > 0 {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: g.haloColor.opacity(g.haloOpacity), location: 0.0),
                            .init(color: g.haloColor.opacity(g.haloOpacity * 0.42), location: 0.46),
                            .init(color: .clear, location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: size * g.halo * glowScale))
                    .frame(width: size * g.halo * 2 * glowScale,
                           height: size * g.halo * 2 * glowScale)
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .opacity(pulse ? 1 : 0.85)
            }

            if g.rays > 0 {
                RayBurst(count: g.rays, color: g.rayColor, opacity: g.rayOpacity,
                         length: size * 0.62, width: max(1.0, size * 0.013))
                    .rotationEffect(.degrees(spin))
            }

            if g.ring {
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [g.rayColor.opacity(0.85),
                                                g.rayColor.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: max(0.8, size * 0.014),
                                           dash: g.ring2 ? [1.5, size * 0.075] : []))
                    .frame(width: size * 1.24, height: size * 1.24)
                    .shadow(color: g.rayColor.opacity(0.55), radius: size * 0.10)
                    .rotationEffect(.degrees(-spin * 1.6))
            }

            if g.ring2 {
                Circle()
                    .strokeBorder(g.rayColor.opacity(0.35),
                                  lineWidth: max(0.6, size * 0.008))
                    .frame(width: size * 1.06, height: size * 1.06)
            }

            if g.sparks > 0 {
                Sparks(count: g.sparks, radius: size * 0.72, dot: max(1.4, size * 0.045),
                       color: g.rayColor, animated: animated)
            }

            Image(level.imageName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: g.rayColor.opacity(g.rays > 0 ? 0.55 : 0),
                        radius: size * 0.10)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            if g.spinSeconds > 0 {
                withAnimation(.linear(duration: g.spinSeconds).repeatForever(autoreverses: false)) {
                    spin = 360
                }
            }
            if g.haloOpacity > 0 && g.rays > 0 {
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

// MARK: - 放射光線

struct RayBurst: View {
    let count: Int
    let color: Color
    let opacity: Double
    let length: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(colors: [color.opacity(opacity),
                                                color.opacity(opacity * 0.15),
                                                .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: width, height: length)
                    .offset(y: -length * 0.52)
                    .rotationEffect(.degrees(Double(i) * 360.0 / Double(max(count, 1))))
            }
        }
        .mask(
            RadialGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.40),
                .init(color: .black, location: 0.58),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1.0)
            ], center: .center, startRadius: 0, endRadius: length * 1.02)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - 細碎星點

struct Sparks: View {
    let count: Int
    let radius: CGFloat
    let dot: CGFloat
    let color: Color
    var animated: Bool = true
    @State private var on = false

    private var points: [(CGFloat, CGFloat, CGFloat)] {
        var out: [(CGFloat, CGFloat, CGFloat)] = []
        for i in 0..<count {
            let a = Double(i) * 2.399963  // 黄金角，分布均匀不扎堆
            let r = 0.62 + Double((i * 37) % 100) / 100.0 * 0.42
            let x = CGFloat(cos(a)) * radius * CGFloat(r)
            let y = CGFloat(sin(a)) * radius * CGFloat(r)
            let s = (i % 4 == 0) ? 1.35 : 0.85
            out.append((x, y, s))
        }
        return out
    }

    var body: some View {
        ZStack {
            ForEach(0..<points.count, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: dot * points[i].2, height: dot * points[i].2)
                    .shadow(color: color, radius: dot * 0.9)
                    .offset(x: points[i].0, y: points[i].1)
                    .opacity(on ? 1 : 0.22)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard animated else { on = true; return }
            withAnimation(.easeInOut(duration: 2.2 + Double(count) * 0.06)
                .repeatForever(autoreverses: true)) { on = true }
        }
    }
}

// MARK: - 會員等級膠囊（名字後面那個小標）

struct MemberPill: View {
    let level: MemberLevel
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            MemberBadge(level: level, size: compact ? 13 : 16, animated: false)
            Text(level.shortName)
                .font(.system(size: compact ? 9.5 : 11, weight: .bold))
                .foregroundStyle(level == .common || level == .silver
                                 ? Color(red: 0.80, green: 0.85, blue: 0.92)
                                 : textColor)
                .lineLimit(1)
        }
        .padding(.leading, compact ? 3 : 4)
        .padding(.trailing, compact ? 7 : 9)
        .padding(.vertical, compact ? 2.5 : 3.5)
        .background(
            Capsule().fill(
                LinearGradient(colors: bg, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        )
        .overlay(
            Capsule().strokeBorder(strokeColor, lineWidth: 0.8)
        )
        // 列表裡的小標籤不畫陰影：聊天室動輒數十行，陰影是離屏渲染，滾動時很吃效能
        .shadow(color: compact ? .clear : shadowColor, radius: compact ? 0 : 5)
    }

    private var textColor: Color {
        switch level {
        case .gold, .black1, .black2, .black3, .black4, .black5:
            return Color(red: 1.0, green: 0.93, blue: 0.72)
        case .platinum:
            return Color(red: 0.96, green: 0.90, blue: 0.95)
        default:
            return Color(red: 0.85, green: 0.90, blue: 0.97)
        }
    }

    private var bg: [Color] {
        switch level {
        case .common:
            return [Color(red: 0.30, green: 0.34, blue: 0.42).opacity(0.55),
                    Color(red: 0.18, green: 0.21, blue: 0.27).opacity(0.55)]
        case .silver:
            return [Color(red: 0.44, green: 0.50, blue: 0.60).opacity(0.45),
                    Color(red: 0.24, green: 0.28, blue: 0.36).opacity(0.45)]
        case .gold:
            return [Color(red: 0.62, green: 0.44, blue: 0.10).opacity(0.55),
                    Color(red: 0.34, green: 0.24, blue: 0.06).opacity(0.55)]
        case .platinum:
            return [Color(red: 0.52, green: 0.26, blue: 0.34).opacity(0.55),
                    Color(red: 0.28, green: 0.15, blue: 0.21).opacity(0.55)]
        default:
            return [Color(red: 0.30, green: 0.24, blue: 0.08).opacity(0.72),
                    Color(red: 0.14, green: 0.11, blue: 0.03).opacity(0.72)]
        }
    }

    private var strokeColor: Color {
        switch level {
        case .common:   return Color.white.opacity(0.14)
        case .silver:   return Color(red: 0.85, green: 0.90, blue: 0.98).opacity(0.35)
        case .gold:     return Color(red: 1.0, green: 0.86, blue: 0.50).opacity(0.45)
        case .platinum: return Color(red: 1.0, green: 0.55, blue: 0.62).opacity(0.50)
        default:        return Color(red: 1.0, green: 0.84, blue: 0.46).opacity(0.55)
        }
    }

    private var shadowColor: Color {
        switch level {
        case .common, .silver: return .clear
        case .gold:     return Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.28)
        case .platinum: return Color(red: 1.0, green: 0.32, blue: 0.42).opacity(0.32)
        default:        return Color(red: 1.0, green: 0.78, blue: 0.32).opacity(0.42)
        }
    }
}
