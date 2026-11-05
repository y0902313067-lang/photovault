import SwiftUI
import UIKit

// ============================================================
// MARK: - 為什麼要重寫這一塊
//
// 原本每個稱號是一個 SwiftUI 視圖，裡面疊了：
//   漸層膠囊、漸層描邊、sheen（plusLighter 混合）、文字陰影、
//   外發光陰影（還分兩層）、王爵以上的模糊外環、還有 Canvas 星芒。
//
// 這每一項都會讓那一小塊被「離屏渲染」（先畫進暫存畫布，再合成回來）。
// 一頁二十幾個稱號、每個四到六層，就是一兩百次離屏；而模糊和陰影還要
// 反覆採樣周圍像素。滾動時這些每幀重做一遍 —— 這就是主頁卡的根。
//
// 遊戲不是這樣畫的。遊戲把一張貼圖（texture）丟進場景，剩下的交給 GPU 合成，
// 一幀幾千個 sprite 也照樣跑滿幀。差別只在「誰在每幀重算」。
//
// 這裡改成同一套做法：
//   ① 牌體、描邊、柔光、文字、圖標、外發光 —— 一次性烤成一張圖。
//      顯示時它只是一張貼圖，零離屏、零模糊、零陰影計算。
//   ② 會動的部分（掃光、呼吸、星芒、紫晶）各自是一張小貼圖，
//      用 Core Animation 播放。CA 動畫在渲染伺服器上跑，主執行緒完全不參與。
//
// 結果：特效從「六個輪流動」變成「全部同時動、加到十幾層」，
// 主執行緒的負擔反而不變 —— 因為它一秒只算一次滾動位置。
// ============================================================

// MARK: - 尺寸（烤圖與版面共用同一組數字）

enum TitleMetrics {
    /// 名牌型素材統一 700x158
    static let bannerAspect: CGFloat = 700.0 / 158.0

    static func content(_ t: TitleDef, size: CGFloat) -> CGSize {
        if t.banner != nil {
            let h = max(24, 30 * size)
            return CGSize(width: (h * bannerAspect).rounded(), height: h.rounded())
        }
        let h = 30 * size
        let icon = 18.5 * size
        let f = UIFont.systemFont(ofSize: 13 * size, weight: .heavy)
        let tw = ((t.name as NSString).size(withAttributes: [.font: f]).width).rounded(.up)
        // 7 + 圖標 + 6 + 文字 + 12，再多留 2pt 餘量避免字被切
        let w = 7 * size + icon + 6 * size + tw + 12 * size + 2
        return CGSize(width: w.rounded(.up), height: h.rounded())
    }

    /// 烤圖時四周留給外發光的邊
    static func pad(_ t: TitleDef, size: CGFloat) -> CGFloat {
        if t.banner != nil { return max(8, 13 * size) }
        if t.tier == 0 { return max(3, 4 * size) }
        return max(9, 24 * size)
    }
}

// MARK: - 共用小貼圖（全域只生成一次）

enum TitleTexture {
    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    private static func make(_ key: String, _ build: () -> UIImage) -> UIImage {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let img = build()
        lock.lock(); cache[key] = img; lock.unlock()
        return img
    }

    private static func renderer(_ w: CGFloat, _ h: CGFloat) -> UIGraphicsImageRenderer {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f)
    }

    /// 斜向光帶：中間亮、兩端完全透明。會被拉伸使用，所以只要一條細的。
    static func band(_ color: UIColor, peak: CGFloat) -> UIImage {
        let key = "band|\(color.description)|\(peak)"
        return make(key) {
            let w: CGFloat = 160, h: CGFloat = 8
            return renderer(w, h).image { ctx in
                let c = ctx.cgContext
                let cs = CGColorSpaceCreateDeviceRGB()
                let cols = [color.withAlphaComponent(0).cgColor,
                            color.withAlphaComponent(peak * 0.45).cgColor,
                            color.withAlphaComponent(peak).cgColor,
                            color.withAlphaComponent(peak * 0.45).cgColor,
                            color.withAlphaComponent(0).cgColor] as CFArray
                let locs: [CGFloat] = [0, 0.30, 0.50, 0.70, 1]
                guard let g = CGGradient(colorsSpace: cs, colors: cols, locations: locs) else { return }
                c.drawLinearGradient(g, start: .zero,
                                     end: CGPoint(x: w, y: 0), options: [])
            }
        }
    }

    /// 牌後柔光：徑向，邊緣完全透明，不會出現方塊
    static func halo(_ color: UIColor, alpha: CGFloat) -> UIImage {
        let key = "halo|\(color.description)|\(alpha)"
        return make(key) {
            let s: CGFloat = 128
            return renderer(s, s).image { ctx in
                let c = ctx.cgContext
                let cs = CGColorSpaceCreateDeviceRGB()
                let cols = [color.withAlphaComponent(alpha).cgColor,
                            color.withAlphaComponent(alpha * 0.45).cgColor,
                            color.withAlphaComponent(0).cgColor] as CFArray
                let locs: [CGFloat] = [0, 0.55, 1]
                guard let g = CGGradient(colorsSpace: cs, colors: cols, locations: locs) else { return }
                let m = s / 2
                c.drawRadialGradient(g, startCenter: CGPoint(x: m, y: m), startRadius: 0,
                                     endCenter: CGPoint(x: m, y: m), endRadius: m, options: [])
            }
        }
    }

    /// 單顆十字星芒
    static func sparkle(_ color: UIColor) -> UIImage {
        let key = "spark|\(color.description)"
        return make(key) {
            let s: CGFloat = 32
            return renderer(s, s).image { ctx in
                let c = ctx.cgContext
                let m = s / 2
                c.setFillColor(color.withAlphaComponent(0.28).cgColor)
                c.fillEllipse(in: CGRect(x: m - 6, y: m - 6, width: 12, height: 12))
                c.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor)
                c.fillEllipse(in: CGRect(x: m - 1.8, y: m - 1.8, width: 3.6, height: 3.6))
                c.setStrokeColor(UIColor.white.withAlphaComponent(0.75).cgColor)
                c.setLineWidth(0.9)
                c.move(to: CGPoint(x: m - 6.5, y: m)); c.addLine(to: CGPoint(x: m + 6.5, y: m))
                c.move(to: CGPoint(x: m, y: m - 6.5)); c.addLine(to: CGPoint(x: m, y: m + 6.5))
                c.strokePath()
            }
        }
    }
}

// MARK: - 烤圖（一次性，之後永遠只是貼圖）

final class TitleArtStore: @unchecked Sendable {
    static let shared = TitleArtStore()

    private var memo: [String: UIImage] = [:]
    private let lock = NSLock()

    private func key(_ t: TitleDef, _ size: CGFloat) -> String {
        "\(t.key)|\(Int((size * 100).rounded()))"
    }

    /// 可以從任何執行緒同步查（先查有沒有烤過，決定第一幀要不要留白）
    func cached(_ t: TitleDef, size: CGFloat) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return memo[key(t, size)]
    }

    /// 把一個稱號的整個靜態外觀烤成一張圖。視覺與原本 SwiftUI 版本完全一致
    /// （因為就是用同一套視圖渲染的），但之後顯示只剩一次貼圖。
    @MainActor
    @discardableResult
    func bake(_ t: TitleDef, size: CGFloat) -> UIImage? {
        let k = key(t, size)
        if let hit = cached(t, size: size) { return hit }

        let m = TitleMetrics.content(t, size: size)
        let pad = TitleMetrics.pad(t, size: size)
        let body = TitleChip(title: t, size: size, animated: false, baked: true)
            .frame(width: m.width, height: m.height)
            .padding(pad)
            .frame(width: m.width + pad * 2, height: m.height + pad * 2)

        let renderer = ImageRenderer(content: body)
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        guard let img = renderer.uiImage else { return nil }
        lock.lock(); memo[k] = img; lock.unlock()
        return img
    }

    /// 進頁面前先把要用的都烤好，避免第一幀空白
    @MainActor
    func warm(_ list: [TitleDef], size: CGFloat) {
        for t in list where cached(t, size: size) == nil {
            bake(t, size: size)
        }
    }

    /// 開機後在背景分片烤——每次只烤兩張就讓出主執行緒，
    /// 這樣點進「我的」時貼圖早就備好了，也不會有一口氣卡住的感覺。
    @MainActor
    func warmDeferred(_ list: [TitleDef], size: CGFloat) {
        Task { @MainActor in
            var n = 0
            for t in list where cached(t, size: size) == nil {
                bake(t, size: size)
                n += 1
                if n % 2 == 0 {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }
}

// MARK: - 動效層（Core Animation，主執行緒零負擔）

final class TitleLayerUIView: UIView {
    private var built = false
    private var lastBounds: CGRect = .zero

    private var art: UIImage?
    private var title: TitleDef?
    private var size: CGFloat = 1
    private var animated = true

    private var base: CALayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        layer.allowsGroupOpacity = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ t: TitleDef, art: UIImage, size: CGFloat, animated: Bool) {
        let same = (title?.key == t.key) && (self.art === art) && self.animated == animated
        self.title = t
        self.art = art
        self.size = size
        self.animated = animated
        if same, built, lastBounds == bounds { return }
        built = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 2, bounds.height > 2, let t = title, let img = art else { return }
        if built && lastBounds == bounds { return }
        rebuild(t, img)
    }

    private func rebuild(_ t: TitleDef, _ img: UIImage) {
        built = true
        lastBounds = bounds

        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let b = bounds
        let scale = contentScaleFactor
        let pad = TitleMetrics.pad(t, size: size)
        let inner = b.insetBy(dx: pad, dy: pad)   // 真正的牌體區域
        let dur = sweepDuration(t)
        let strong = t.tier >= 4

        // ① 呼吸柔光（最底層，徑向，邊緣透明）
        if animated, t.tier >= 1 {
            let halo = CALayer()
            let hs = inner.width * 1.55
            halo.frame = CGRect(x: b.midX - hs / 2, y: b.midY - hs * 0.5,
                                width: hs, height: hs)
            halo.contents = TitleTexture.halo(UIColor(t.glow), alpha: strong ? 0.55 : 0.34).cgImage
            halo.opacity = 0.8
            layer.addSublayer(halo)
            breathe(halo, from: 0.55, to: 1.0, period: 2.6 + Double(t.tier % 3) * 0.3)
        }

        // ② 牌體貼圖（含描邊、柔光、文字、圖標、外發光 —— 全部已在像素裡）
        let base = CALayer()
        base.frame = b
        base.contents = img.cgImage
        base.contentsGravity = .resize
        base.contentsScale = scale
        base.magnificationFilter = .linear
        base.minificationFilter = .linear
        base.edgeAntialiasingMask = []
        layer.addSublayer(base)
        self.base = base

        // ③ 微浮動（名牌型才有，膠囊型靜止更穩）
        if animated, t.banner != nil {
            let float = CABasicAnimation(keyPath: "transform.translation.y")
            float.fromValue = -1.1
            float.toValue = 1.1
            float.duration = 2.9
            float.autoreverses = true
            float.repeatCount = .infinity
            float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            base.add(float, forKey: "float")
        }

        guard animated, t.tier >= 1 else {
            CATransaction.commit()
            return
        }

        // ④ 掃光 —— 這層被牌體圖的 alpha 遮住，光不會溢到牌子外面
        addSweep(host: b, mask: img, inner: inner, t: t, dur: dur,
                 peak: strong ? 0.85 : 0.62, reverse: false, delay: 0)

        // 高階再加一道反向掃光，兩道光交錯而過
        if t.tier >= 5 {
            addSweep(host: b, mask: img, inner: inner, t: t, dur: dur * 1.55,
                     peak: 0.42, reverse: true, delay: dur * 0.35)
        }

        // ⑤ 星點流動 —— 星星從牌面一側飄到另一側，各自閃爍。
        //    每一顆都是一個小貼圖 + 一條 CA 動畫，與牌寬自適應。
        if t.tier >= 3 {
            addStars(t, host: b, maskImg: img)
        }

        // ⑥ 外圈靈氣（王爵以上）—— 兩圈純描邊，靠呼吸明暗做出「靈氣」，
        //    完全不用模糊，也就沒有離屏渲染。
        if t.tier >= 4 {
            let ringW = inner.width + pad * 0.9
            let ringH = inner.height + pad * 0.9
            let edge = UIColor(t.edge)

            let wide = CALayer()
            wide.frame = CGRect(x: b.midX - ringW / 2, y: b.midY - ringH / 2,
                                width: ringW, height: ringH)
            wide.cornerRadius = ringH / 2
            wide.borderWidth = 3.0
            wide.borderColor = edge.withAlphaComponent(0.22).cgColor
            wide.opacity = 0.5
            layer.addSublayer(wide)
            breathe(wide, from: 0.25, to: 1.0, period: 3.1)

            let thin = CALayer()
            thin.frame = CGRect(x: b.midX - ringW / 2, y: b.midY - ringH / 2,
                                width: ringW, height: ringH)
            thin.cornerRadius = ringH / 2
            thin.borderWidth = 0.9
            thin.borderColor = edge.withAlphaComponent(0.85).cgColor
            thin.opacity = 0.7
            layer.addSublayer(thin)
            breathe(thin, from: 0.4, to: 1.0, period: 3.1)
        }

        CATransaction.commit()
    }

    // MARK: 掃光

    private func addSweep(host: CGRect, mask img: UIImage, inner: CGRect,
                          t: TitleDef, dur: Double,
                          peak: CGFloat, reverse: Bool, delay: Double) {
        let hostLayer = CALayer()
        hostLayer.anchorPoint = .zero
        hostLayer.position = .zero
        hostLayer.bounds = host
        layer.addSublayer(hostLayer)

        let bandW = inner.width * 0.30
        let bandH = host.height * 1.6
        let band = CALayer()
        band.bounds = CGRect(x: 0, y: 0, width: bandW, height: bandH)
        band.position = CGPoint(x: host.midX, y: host.midY)
        band.contents = TitleTexture.band(.white, peak: peak).cgImage
        band.contentsGravity = .resize
        band.contentsScale = contentScaleFactor
        band.setAffineTransform(CGAffineTransform(rotationAngle: (reverse ? -16 : 16) * .pi / 180))
        hostLayer.addSublayer(band)

        // 光只准留在牌體像素上
        let mp = CALayer()
        mp.frame = host
        mp.contents = img.cgImage
        mp.contentsGravity = .resize
        mp.contentsScale = contentScaleFactor
        hostLayer.mask = mp

        let from = CGPoint(x: reverse ? host.maxX + bandW : host.minX - bandW, y: host.midY)
        let to = CGPoint(x: reverse ? host.minX - bandW : host.maxX + bandW, y: host.midY)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(cgPoint: from)
        move.toValue = NSValue(cgPoint: to)
        move.duration = dur
        move.repeatCount = .infinity
        move.timeOffset = delay
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        band.position = to
        band.add(move, forKey: "sweep")
    }

    // MARK: 星點流動

    /// 一排小星點各自從牌面一側漂到另一側，同時明暗閃爍。
    /// 每顆星就是一張小貼圖 + 一條 CA 動畫，牌面多寬都能自適應，
    /// 而且全部在渲染伺服器上跑，主執行緒一點負擔都沒有。
    private func addStars(_ t: TitleDef, host: CGRect, maskImg img: UIImage) {
        let hostLayer = CALayer()
        hostLayer.anchorPoint = .zero
        hostLayer.position = .zero
        hostLayer.bounds = host
        layer.addSublayer(hostLayer)

        let mp = CALayer()
        mp.frame = host
        mp.contents = img.cgImage
        mp.contentsGravity = .resize
        mp.contentsScale = contentScaleFactor
        hostLayer.mask = mp

        var specs: [(color: UIColor, count: Int, dir: CGFloat, scale: CGFloat)] = []
        let base = UIColor(t.glow)
        specs.append((base, t.tier >= 6 ? 10 : (t.tier >= 5 ? 8 : 6), 1, 1.0))
        if t.tier >= 5 {
            specs.append((UIColor(t.edge), 5, -1, 0.8))
        }
        if t.tier >= 6 {
            specs.append((UIColor(red: 1.0, green: 0.87, blue: 0.62, alpha: 1.0), 6, 1, 0.72))
        }

        var i = 0
        for spec in specs {
            let cg = TitleTexture.sparkle(spec.color).cgImage
            for _ in 0..<spec.count {
                let seed = Double((i * 37 + 11) % 97) / 97.0
                let s = (0.34 + seed * 0.62) * spec.scale
                let node = CALayer()
                node.bounds = CGRect(x: 0, y: 0, width: 32 * s, height: 32 * s)
                node.contents = cg
                node.contentsScale = contentScaleFactor
                let y = host.minY + host.height * CGFloat(0.16 + seed * 0.68)
                node.position = CGPoint(x: host.width + 40, y: y)
                hostLayer.addSublayer(node)

                let travel = CABasicAnimation(keyPath: "position.x")
                let w = Double(host.width)
                if spec.dir > 0 {
                    travel.fromValue = -30.0
                    travel.toValue = w + 30.0
                } else {
                    travel.fromValue = w + 30.0
                    travel.toValue = -30.0
                }
                travel.duration = 3.6 + seed * 4.8
                travel.repeatCount = .infinity
                travel.timeOffset = seed * 7.0
                travel.timingFunction = CAMediaTimingFunction(name: .linear)
                node.add(travel, forKey: "travel")

                let tw = CABasicAnimation(keyPath: "opacity")
                tw.fromValue = 0.10
                tw.toValue = 0.95
                tw.duration = 0.75 + seed * 1.3
                tw.autoreverses = true
                tw.repeatCount = .infinity
                tw.timeOffset = seed * 2.4
                tw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                node.opacity = 0.9
                node.add(tw, forKey: "tw")
                i += 1
            }
        }
    }

    // MARK: CA 動畫小工具

    private func breathe(_ l: CALayer, from: CGFloat, to: CGFloat, period: Double) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.duration = period
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.opacity = to
        l.add(a, forKey: "breathe")
    }

    private func sweepDuration(_ t: TitleDef) -> Double {
        switch t.tier {
        case 0, 1: return 4.6
        case 2, 3: return 3.4
        case 4:    return 2.9
        case 5:    return 2.5
        default:   return 2.0
        }
    }
}

struct TitleLayerView: UIViewRepresentable {
    let title: TitleDef
    let size: CGFloat
    let art: UIImage
    let animated: Bool

    func makeUIView(context: Context) -> TitleLayerUIView {
        let v = TitleLayerUIView()
        v.configure(title, art: art, size: size, animated: animated)
        return v
    }

    func updateUIView(_ v: TitleLayerUIView, context: Context) {
        v.configure(title, art: art, size: size, animated: animated)
    }
}

// MARK: - 對外的稱號 view

struct TitleArtChip: View {
    let title: TitleDef
    var size: CGFloat = 1
    var animated: Bool = true

    @State private var art: UIImage?
    @State private var failed = false

    init(title: TitleDef, size: CGFloat = 1, animated: Bool = true) {
        self.title = title
        self.size = size
        self.animated = animated
        _art = State(initialValue: TitleArtStore.shared.cached(title, size: size))
    }

    private var m: CGSize { TitleMetrics.content(title, size: size) }
    private var pad: CGFloat { TitleMetrics.pad(title, size: size) }

    var body: some View {
        Group {
            if failed {
                // 烤圖失敗就退回原本的渲染，功能不受影響
                TitleChip(title: title, size: size, animated: animated)
            } else if let art {
                TitleLayerView(title: title, size: size, art: art, animated: animated)
                    .frame(width: m.width + pad * 2, height: m.height + pad * 2)
            } else {
                Color.clear
                    .frame(width: m.width + pad * 2, height: m.height + pad * 2)
            }
        }
        .task(id: title.key) {
            guard art == nil, !failed else { return }
            if let hit = TitleArtStore.shared.cached(title, size: size) {
                art = hit
                return
            }
            if let made = TitleArtStore.shared.bake(title, size: size) {
                art = made
            } else {
                failed = true
            }
        }
    }
}
