import SwiftUI
import Foundation
import CoreMotion
import CoreLocation
import UIKit

// MARK: - 水平儀

final class LevelModel: ObservableObject {
    @Published var gx: Double = 0
    @Published var gy: Double = 0
    @Published var available = true
    @Published var zeroX: Double = 0
    @Published var zeroY: Double = 0
    @Published var calibrating = false

    private let mm = CMMotionManager()

    var tilt: Double {
        let dx = gx - zeroX
        let dy = gy - zeroY
        return asin(min(1.0, sqrt(dx * dx + dy * dy))) * 180.0 / Double.pi
    }

    var isLevel: Bool { tilt < 0.8 }

    func start() {
        guard mm.isDeviceMotionAvailable else {
            available = false
            return
        }
        mm.deviceMotionUpdateInterval = 1.0 / 60.0
        mm.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let g = data?.gravity else { return }
            self.gx = g.x
            self.gy = g.y
        }
    }

    func stop() { mm.stopDeviceMotionUpdates() }

    func calibrate() {
        zeroX = gx
        zeroY = gy
        calibrating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.calibrating = false }
    }
}

struct LevelView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = LevelModel()
    @State private var wasLevel = false
    @State private var pulse = false

    var body: some View {
        TTScreen(title: "電子水平儀",
                 subtitle: "PRECISION LEVEL",
                 badge: model.available ? (model.isLevel ? "LEVEL" : "TILT") : "N/A",
                 badgeOn: model.available && model.isLevel,
                 accent: TT.mint) {
            if !model.available {
                unavailable
            } else {
                bubbleBlock
                readoutBlock
                calibrateBlock
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.isLevel) { level in
            if level && !wasLevel {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
            }
            wasLevel = level
        }
    }

    private var bubbleBlock: some View {
        let accent = model.isLevel ? TT.mint : TT.amber
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.012)],
                                     center: .center, startRadius: 4, endRadius: 150))

            // 同心環
            ForEach(1..<5, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: CGFloat(i) * 54, height: CGFloat(i) * 54)
            }

            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.5)
                .frame(width: 268, height: 268)

            // 十字準線
            Path { p in
                p.move(to: CGPoint(x: 134, y: 6)); p.addLine(to: CGPoint(x: 134, y: 38))
                p.move(to: CGPoint(x: 134, y: 230)); p.addLine(to: CGPoint(x: 134, y: 262))
                p.move(to: CGPoint(x: 6, y: 134)); p.addLine(to: CGPoint(x: 38, y: 134))
                p.move(to: CGPoint(x: 230, y: 134)); p.addLine(to: CGPoint(x: 262, y: 134))
            }
            .stroke(Color.white.opacity(0.20), lineWidth: 1)
            .frame(width: 268, height: 268)

            // 中央目標圈
            Circle()
                .strokeBorder(accent.opacity(model.isLevel ? 0.85 : 0.25), lineWidth: 1.4)
                .frame(width: 62, height: 62)
                .scaleEffect(model.isLevel && pulse ? 1.18 : 1.0)
                .opacity(model.isLevel && pulse ? 0.4 : 1.0)

            // 水泡
            Circle()
                .fill(RadialGradient(colors: [accent, accent.opacity(0.55)],
                                     center: .init(x: 0.35, y: 0.3),
                                     startRadius: 1, endRadius: 20))
                .frame(width: 40, height: 40)
                .shadow(color: accent.opacity(0.8), radius: 14)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                .offset(x: bubbleOffset.width, y: bubbleOffset.height)
                .animation(.linear(duration: 0.06), value: model.gx)
                .animation(.linear(duration: 0.06), value: model.gy)

            VStack {
                Spacer()
                Text(model.calibrating ? "已校準為基準 0°" : (model.isLevel ? "已水平" : "調整直到水泡進圈"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 14)
            }
            .frame(height: 268)
        }
        .frame(width: 268, height: 268)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var bubbleOffset: CGSize {
        let dx = model.gx - model.zeroX
        let dy = model.gy - model.zeroY
        let limit = 108.0
        let scale = 240.0
        var ox = dx * scale
        var oy = dy * scale
        let mag = sqrt(ox * ox + oy * oy)
        if mag > limit {
            ox = ox / mag * limit
            oy = oy / mag * limit
        }
        return CGSize(width: ox, height: oy)
    }

    private var readoutBlock: some View {
        HStack(spacing: 10) {
            TTStat(title: "傾角", value: String(format: "%.2f", model.tilt), unit: "°",
                   accent: model.isLevel ? TT.mint : TT.amber)
            TTStat(title: "X 軸", value: String(format: "%+.3f", (model.gx - model.zeroX) * 90), unit: "°", accent: TT.blue)
            TTStat(title: "Y 軸", value: String(format: "%+.3f", (model.gy - model.zeroY) * 90), unit: "°", accent: TT.violet)
        }
    }

    private var calibrateBlock: some View {
        VStack(spacing: 10) {
            TTButton(title: "以此角度校準為 0°", icon: "scope", accent: TT.mint) {
                model.calibrate()
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
            }
            Text("把手機貼在要測的平面上，再按校準；之後顯示的就是相對該平面的傾斜。")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var unavailable: some View {
        TTPanel(accent: TT.amber) {
            TTEmptyHint(icon: "gyroscope", text: "這台裝置沒有可用的動作感測器")
        }
    }
}

// MARK: - 指南針

final class CompassModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var magnetic: Double = 0
    @Published var trueNorth: Double = -1
    @Published var accuracy: Double = -1
    @Published var status: String = "待機"
    @Published var available = true

    private let lm = CLLocationManager()

    override init() {
        super.init()
        lm.delegate = self
        lm.headingFilter = 0.8
    }

    var directionName: String {
        let names = ["北", "東北", "東", "東南", "南", "西南", "西", "西北"]
        let idx = Int((magnetic + 22.5) / 45.0) % 8
        return names[idx]
    }

    var directionEn: String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((magnetic + 22.5) / 45.0) % 8
        return names[idx]
    }

    func start() {
        guard CLLocationManager.headingAvailable() else {
            available = false
            status = "此裝置不支援"
            return
        }
        switch lm.authorizationStatus {
        case .notDetermined:
            lm.requestWhenInUseAuthorization()
        default:
            break
        }
        lm.startUpdatingHeading()
        lm.startUpdatingLocation()
        status = "校正中"
    }

    func stop() {
        lm.stopUpdatingHeading()
        lm.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        magnetic = newHeading.magneticHeading
        accuracy = newHeading.headingAccuracy
        if newHeading.trueHeading >= 0 {
            trueNorth = newHeading.trueHeading
        }
        status = accuracy < 0 ? "需要校正" : (accuracy < 10 ? "訊號良好" : "精度偏低")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingHeading()
        } else if manager.authorizationStatus == .denied {
            status = "未授權定位"
        }
    }
}

struct CompassView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CompassModel()

    var body: some View {
        TTScreen(title: "指南針",
                 subtitle: "MAGNETIC COMPASS",
                 badge: model.available ? model.status : "N/A",
                 badgeOn: model.available,
                 accent: TT.blue) {
            if model.available {
                dial
                HStack(spacing: 10) {
                    TTStat(title: "磁北", value: String(format: "%.0f", model.magnetic), unit: "°", accent: TT.blue)
                    TTStat(title: "真北",
                           value: model.trueNorth >= 0 ? String(format: "%.0f", model.trueNorth) : "—",
                           unit: model.trueNorth >= 0 ? "°" : "", accent: TT.violet)
                    TTStat(title: "精度", value: String(format: "±%.0f", max(model.accuracy, 0)), unit: "°",
                           accent: model.accuracy >= 0 && model.accuracy < 15 ? TT.mint : TT.amber)
                }
                TTPanel(accent: TT.amber) {
                    Text("金屬、磁鐵、音響與手機殼都可能干擾讀數；遇到「需要校正」時，拿手機在空中畫 8 字幾次。")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                TTPanel(accent: TT.amber) { TTEmptyHint(icon: "location.slash", text: "此裝置沒有磁力計") }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)],
                                     center: .center, startRadius: 5, endRadius: 150))
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.2)
                .frame(width: 280, height: 280)

            // 刻度
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2 - 8
                for i in 0..<72 {
                    let ang = Double(i) * 5.0 * Double.pi / 180
                    let major = i % 18 == 0
                    let mid = i % 6 == 0
                    let inner = r - (major ? 18 : (mid ? 12 : 7))
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + CGFloat(sin(ang)) * inner,
                                       y: c.y - CGFloat(cos(ang)) * inner))
                    p.addLine(to: CGPoint(x: c.x + CGFloat(sin(ang)) * r,
                                          y: c.y - CGFloat(cos(ang)) * r))
                    ctx.stroke(p,
                               with: .color(.white.opacity(major ? 0.55 : (mid ? 0.28 : 0.13))),
                               lineWidth: major ? 2 : 1)
                }

                let labels: [(Double, String, Color)] = [
                    (0, "N", TT.rose), (90, "E", Color.white.opacity(0.5)),
                    (180, "S", Color.white.opacity(0.5)), (270, "W", Color.white.opacity(0.5))
                ]
                for (deg, txt, col) in labels {
                    let a = deg * Double.pi / 180
                    let rr = r - 33
                    ctx.draw(Text(txt)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(col),
                             at: CGPoint(x: c.x + CGFloat(sin(a)) * rr,
                                         y: c.y - CGFloat(cos(a)) * rr))
                }
            }
            .frame(width: 280, height: 280)
            .rotationEffect(.degrees(-model.magnetic))
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.magnetic)

            // 固定指針
            VStack(spacing: 0) {
                Triangle()
                    .fill(TT.rose)
                    .frame(width: 13, height: 18)
                    .shadow(color: TT.rose.opacity(0.6), radius: 6)
                Spacer()
            }
            .frame(height: 262)
            .offset(y: 12)

            VStack(spacing: 1) {
                Text(String(format: "%.0f", model.magnetic))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                HStack(spacing: 5) {
                    Text(model.directionName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TT.mint)
                    Text(model.directionEn)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(width: 280, height: 280)
        .frame(maxWidth: .infinity)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 磁力計

final class MagnetModel: ObservableObject {
    @Published var x: Double = 0
    @Published var y: Double = 0
    @Published var z: Double = 0
    @Published var total: Double = 0
    @Published var peak: Double = 0
    @Published var available = true
    @Published var history: [Double] = Array(repeating: 0, count: 48)

    private let mm = CMMotionManager()

    func start() {
        guard mm.isMagnetometerAvailable else {
            available = false
            return
        }
        mm.magnetometerUpdateInterval = 1.0 / 20.0
        mm.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let f = data?.magneticField else { return }
            self.x = f.x
            self.y = f.y
            self.z = f.z
            let t = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
            self.total = t
            self.peak = max(self.peak, t)
            self.history.removeFirst()
            self.history.append(t)
        }
    }

    func stop() { mm.stopMagnetometerUpdates() }

    func resetPeak() { peak = total }
}

struct MagnetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MagnetModel()

    private var fieldLabel: String {
        let t = model.total
        if t < 25 { return "極弱" }
        if t < 45 { return "正常（地磁）" }
        if t < 80 { return "偏強" }
        if t < 200 { return "強磁場" }
        return "極強，請遠離"
    }

    private var fieldColor: Color {
        let t = model.total
        if t < 45 { return TT.mint }
        if t < 80 { return TT.teal }
        if t < 200 { return TT.amber }
        return TT.rose
    }

    var body: some View {
        TTScreen(title: "磁力計",
                 subtitle: "MAGNETOMETER",
                 badge: model.available ? fieldLabel : "N/A",
                 badgeOn: model.available,
                 accent: TT.indigo) {
            if model.available {
                totalBlock
                axisBlock
                historyBlock
                TTPanel(accent: TT.indigo, padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("可以拿它找牆內鋼筋、螺絲或磁鐵：數值明顯跳高就是有金屬。")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                        Text("地球磁場約 25–65 µT，手機喇叭附近會高很多。")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }
            } else {
                TTPanel(accent: TT.amber) { TTEmptyHint(icon: "waveform.path", text: "此裝置沒有磁力計") }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var totalBlock: some View {
        TTPanel(accent: fieldColor) {
            VStack(spacing: 13) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.1f", model.total))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .shadow(color: fieldColor.opacity(0.4), radius: 16)
                    Text("µT")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(fieldColor.opacity(0.8))
                        .padding(.bottom, 8)
                }
                TTMeterBar(ratio: min(model.total / 200.0, 1), accent: fieldColor)
                HStack {
                    Text("峰值 \(String(format: "%.1f", model.peak)) µT")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button {
                        model.resetPeak()
                    } label: {
                        Text("重置峰值")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(fieldColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var axisBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "三軸分量", accent: TT.indigo)
            ForEach(Array([("X", model.x), ("Y", model.y), ("Z", model.z)].enumerated()), id: \.offset) { _, item in
                HStack(spacing: 11) {
                    Text(item.0)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(TT.indigo.opacity(0.9))
                        .frame(width: 16)
                    TTMeterBar(ratio: min(abs(item.1) / 120.0, 1),
                               accent: item.1 >= 0 ? TT.indigo : TT.violet)
                    Text(String(format: "%+.1f", item.1))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }

    private var historyBlock: some View {
        TTPanel(accent: TT.violet, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("場強變化")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.35))
                Canvas { ctx, size in
                    let peak = max(model.history.max() ?? 1, 50)
                    let step = size.width / CGFloat(max(model.history.count - 1, 1))
                    var line = Path()
                    for (i, v) in model.history.enumerated() {
                        let x = CGFloat(i) * step
                        let y = size.height - CGFloat(min(v / peak, 1)) * (size.height - 6) - 3
                        if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                        else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(line,
                               with: .linearGradient(Gradient(colors: [TT.violet.opacity(0.5), TT.mint]),
                                                     startPoint: .zero,
                                                     endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 74)
            }
        }
    }
}
