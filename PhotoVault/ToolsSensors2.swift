import SwiftUI
import Foundation
import CoreMotion
import AVFoundation
import UIKit

// MARK: - 重力感測

final class GravityModel: ObservableObject {
    @Published var gx: Double = 0
    @Published var gy: Double = 0
    @Published var gz: Double = 0
    @Published var magnitude: Double = 1
    @Published var userAccel: Double = 0
    @Published var impactPeak: Double = 0
    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    @Published var yaw: Double = 0
    @Published var available = true
    @Published var shakes = 0

    private let mm = CMMotionManager()
    private var lastImpact = Date.distantPast

    func start() {
        guard mm.isDeviceMotionAvailable else {
            available = false
            return
        }
        mm.deviceMotionUpdateInterval = 1.0 / 50.0
        mm.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let d = data else { return }
            self.gx = d.gravity.x
            self.gy = d.gravity.y
            self.gz = d.gravity.z
            self.magnitude = sqrt(d.gravity.x * d.gravity.x +
                                  d.gravity.y * d.gravity.y +
                                  d.gravity.z * d.gravity.z)
            let ua = sqrt(d.userAcceleration.x * d.userAcceleration.x +
                          d.userAcceleration.y * d.userAcceleration.y +
                          d.userAcceleration.z * d.userAcceleration.z)
            self.userAccel = ua
            if ua > self.impactPeak { self.impactPeak = ua }
            if ua > 1.2 && Date().timeIntervalSince(self.lastImpact) > 0.45 {
                self.lastImpact = Date()
                self.shakes += 1
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
            self.pitch = d.attitude.pitch * 180.0 / Double.pi
            self.roll = d.attitude.roll * 180.0 / Double.pi
            self.yaw = d.attitude.yaw * 180.0 / Double.pi
        }
    }

    func stop() { mm.stopDeviceMotionUpdates() }

    func reset() {
        impactPeak = 0
        shakes = 0
    }
}

struct GravityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @StateObject private var model = GravityModel()

    private var impactColor: Color {
        if model.userAccel > 1.2 { return TT.rose }
        if model.userAccel > 0.45 { return TT.amber }
        return TT.mint
    }

    var body: some View {
        TTScreen(title: "重力感測",
                 subtitle: "G-FORCE SENSOR",
                 badge: model.available ? String(format: "%.2f G", model.magnitude) : "N/A",
                 badgeOn: model.available,
                 accent: TT.violet) {
            if model.available {
                ballBlock
                HStack(spacing: 10) {
                    TTStat(title: "X", value: String(format: "%+.2f", model.gx), unit: "g", accent: TT.rose)
                    TTStat(title: "Y", value: String(format: "%+.2f", model.gy), unit: "g", accent: TT.mint)
                    TTStat(title: "Z", value: String(format: "%+.2f", model.gz), unit: "g", accent: TT.blue)
                }
                TTPanel(accent: impactColor) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("即時加速度")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text(String(format: "%.2f g", model.userAccel))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(impactColor)
                        }
                        TTMeterBar(ratio: min(model.userAccel / 3.0, 1), accent: impactColor)
                        HStack {
                            Text("峰值 \(String(format: "%.2f", model.impactPeak)) g · 晃動 \(model.shakes) 次")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                            Spacer()
                            Button {
                                model.reset()
                            } label: {
                                Text("重置")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(impactColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 10) {
                    TTStat(title: "PITCH", value: String(format: "%+.0f", model.pitch), unit: "°", accent: TT.violet)
                    TTStat(title: "ROLL", value: String(format: "%+.0f", model.roll), unit: "°", accent: TT.violet)
                    TTStat(title: "YAW", value: String(format: "%+.0f", model.yaw), unit: "°", accent: TT.violet)
                }
            } else {
                TTPanel(accent: TT.amber) { TTEmptyHint(icon: "gyroscope", text: "此裝置沒有動作感測器") }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.shakes) { v in
            // 每晃一下記一次，「6767」要累積 67 下
            if v > 0 { store.bumpTask("shake67", add: 1) }
        }
    }

    private var ballBlock: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.008)],
                                     center: .center, startRadius: 4, endRadius: 130))
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 232, height: 232)
            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                .frame(width: 160, height: 160)
            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                .frame(width: 86, height: 86)

            // 十字
            Path { p in
                p.move(to: CGPoint(x: 116, y: 0)); p.addLine(to: CGPoint(x: 116, y: 232))
                p.move(to: CGPoint(x: 0, y: 116)); p.addLine(to: CGPoint(x: 232, y: 116))
            }
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
            .frame(width: 232, height: 232)

            // 重力小球
            Circle()
                .fill(RadialGradient(colors: [TT.violet, TT.indigo.opacity(0.7)],
                                     center: .init(x: 0.34, y: 0.3),
                                     startRadius: 1, endRadius: 22))
                .frame(width: 44, height: 44)
                .shadow(color: TT.violet.opacity(0.75), radius: 16)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .offset(x: CGFloat(model.gx) * 88,
                        y: CGFloat(model.gy) * 88)
                .animation(.linear(duration: 0.05), value: model.gx)
                .animation(.linear(duration: 0.05), value: model.gy)

            VStack {
                Spacer()
                Text(String(format: "%.2f g", model.magnitude))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(height: 232)
            .padding(.bottom, 8)
        }
        .frame(width: 232, height: 232)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - 氣壓與海拔

final class BarometerModel: ObservableObject {
    @Published var pressureKPa: Double = 0
    @Published var relativeAltitude: Double = 0
    @Published var history: [Double] = Array(repeating: 0, count: 50)
    @Published var available = true
    @Published var running = false
    @Published var samples = 0

    private let altimeter = CMAltimeter()
    private var basePressure: Double = 0

    var hPa: Double { pressureKPa * 10.0 }

    var estimatedAltitude: Double {
        guard hPa > 100 else { return 0 }
        return 44330.0 * (1.0 - pow(hPa / 1013.25, 1.0 / 5.255))
    }

    var trend: String {
        let h = history.filter { $0 != 0 }
        guard h.count >= 6 else { return "穩定" }
        let first = h.prefix(3).reduce(0, +) / 3.0
        let last = h.suffix(3).reduce(0, +) / 3.0
        let diff = last - first
        if diff > 0.35 { return "上升中" }
        if diff < -0.35 { return "下降中" }
        return "穩定"
    }

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            available = false
            return
        }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let d = data else { return }
            self.pressureKPa = d.pressure.doubleValue
            self.relativeAltitude = d.relativeAltitude.doubleValue
            if self.basePressure == 0 { self.basePressure = self.pressureKPa }
            self.samples += 1
            self.running = true
            self.history.removeFirst()
            self.history.append(self.relativeAltitude)
        }
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        running = false
    }
}

struct BarometerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BarometerModel()

    var body: some View {
        TTScreen(title: "氣壓與海拔",
                 subtitle: "BAROMETRIC ALTIMETER",
                 badge: model.available ? (model.running ? "LIVE" : "INIT") : "N/A",
                 badgeOn: model.running,
                 accent: TT.teal) {
            if model.available {
                pressureBlock
                HStack(spacing: 10) {
                    TTStat(title: "相對高度", value: String(format: "%+.2f", model.relativeAltitude), unit: "m", accent: TT.mint)
                    TTStat(title: "估算海拔", value: String(format: "%.0f", model.estimatedAltitude), unit: "m", accent: TT.teal)
                    TTStat(title: "取樣", value: "\(model.samples)", unit: "次", accent: TT.blue)
                }
                trendBlock
                TTPanel(accent: TT.amber, padding: 14) {
                    Text("氣壓高度以標準大氣壓換算，會隨天氣變化而有 ±數十公尺誤差；需要精確高度請用 GPS 頁。相對高度（從啟動那刻算起）才是氣壓計最準的部分。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                TTPanel(accent: TT.amber) { TTEmptyHint(icon: "barometer", text: "此裝置沒有氣壓計") }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var pressureBlock: some View {
        TTPanel(accent: TT.teal) {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.1f", model.hPa))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .shadow(color: TT.teal.opacity(0.35), radius: 14)
                    Text("hPa")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TT.teal.opacity(0.8))
                        .padding(.bottom, 6)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.trend)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(TT.mint)
                        Text(String(format: "%.2f kPa", model.pressureKPa))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                Text(weatherHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var weatherHint: String {
        let p = model.hPa
        if p <= 0 { return "正在讀取感測器…" }
        if p < 980 { return "氣壓偏低，常見於颱風或強低壓系統" }
        if p < 1000 { return "氣壓略低，天氣可能轉壞" }
        if p < 1020 { return "標準範圍" }
        if p < 1035 { return "氣壓偏高，天氣通常穩定" }
        return "高壓明顯，晴朗穩定"
    }

    private var trendBlock: some View {
        TTPanel(accent: TT.mint, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("相對高度變化")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text(String(format: "%+.1f m", model.relativeAltitude))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(TT.mint.opacity(0.8))
                }
                Canvas { ctx, size in
                    let vals = model.history
                    let lo = min(vals.min() ?? 0, -0.5)
                    let hi = max(vals.max() ?? 0, 0.5)
                    let span = max(hi - lo, 0.8)
                    let step = size.width / CGFloat(max(vals.count - 1, 1))
                    var line = Path()
                    var zeroLine = Path()
                    zeroLine.move(to: CGPoint(x: 0, y: size.height - CGFloat((0 - lo) / span) * size.height))
                    zeroLine.addLine(to: CGPoint(x: size.width, y: size.height - CGFloat((0 - lo) / span) * size.height))
                    for (i, v) in vals.enumerated() {
                        let x = CGFloat(i) * step
                        let y = size.height - CGFloat((v - lo) / span) * size.height
                        if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                        else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(zeroLine, with: .color(.white.opacity(0.10)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    ctx.stroke(line,
                               with: .linearGradient(Gradient(colors: [TT.teal, TT.mint]),
                                                     startPoint: .zero,
                                                     endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 80)
            }
        }
    }
}

// MARK: - 分貝計

final class DecibelModel: ObservableObject {
    @Published var db: Double = 0
    @Published var peak: Double = 0
    @Published var avg: Double = 0
    @Published var history: [Double] = Array(repeating: 0, count: 60)
    @Published var running = false
    @Published var status = "待機"
    @Published var denied = false

    private let engine = AVAudioEngine()
    private var tapped = false
    private var sum: Double = 0
    private var count: Double = 0

    var levelTitle: String {
        switch db {
        case 0..<30:   return "極安靜"
        case 30..<45:  return "安靜"
        case 45..<60:  return "一般交談"
        case 60..<75:  return "吵雜"
        case 75..<90:  return "很吵"
        case 90..<105: return "吵到傷耳"
        default:       return "危險音量"
        }
    }

    var levelColor: Color {
        switch db {
        case 0..<45:   return TT.mint
        case 45..<65:  return TT.teal
        case 65..<85:  return TT.amber
        case 85..<100: return Color(red: 1.0, green: 0.55, blue: 0.3)
        default:       return TT.rose
        }
    }

    func request() {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            start()
        case .denied:
            denied = true
            status = "麥克風權限被關閉"
        case .undetermined:
            session.requestRecordPermission { [weak self] ok in
                DispatchQueue.main.async {
                    if ok { self?.start() }
                    else {
                        self?.denied = true
                        self?.status = "麥克風權限被關閉"
                    }
                }
            }
        @unknown default:
            start()
        }
    }

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            status = "音訊初始化失敗"
            return
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            status = "麥克風不可用"
            return
        }

        if !tapped {
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self = self,
                      let ch = buffer.floatChannelData?[0] else { return }
                let n = Int(buffer.frameLength)
                guard n > 0 else { return }
                var acc: Float = 0
                for i in 0..<n {
                    let v = ch[i]
                    acc += v * v
                }
                let rms = sqrt(acc / Float(n))
                let dbfs = 20.0 * log10(max(Double(rms), 1e-8))
                // 以 100 dB 動態範圍映射，安靜環境約 30、講話約 60
                let mapped = max(0, min(120, dbfs + 100.0))
                DispatchQueue.main.async {
                    self.push(mapped)
                }
            }
            tapped = true
        }

        engine.prepare()
        do {
            try engine.start()
            running = true
            status = "量測中"
            denied = false
        } catch {
            status = "無法啟動麥克風"
        }
    }

    private func push(_ v: Double) {
        let smoothed = db == 0 ? v : db * 0.72 + v * 0.28
        db = smoothed
        peak = max(peak, v)
        sum += v
        count += 1
        avg = sum / max(count, 1)
        history.removeFirst()
        history.append(smoothed)
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
        running = false
        status = "已暫停"
    }

    func reset() {
        peak = 0
        sum = 0
        count = 0
        avg = 0
        history = Array(repeating: 0, count: 60)
    }
}

struct DecibelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = DecibelModel()

    var body: some View {
        TTScreen(title: "分貝計",
                 subtitle: "SOUND LEVEL METER",
                 badge: model.running ? "REC" : "IDLE",
                 badgeOn: model.running,
                 accent: TT.amber) {
            meterBlock
            HStack(spacing: 10) {
                TTStat(title: "峰值", value: String(format: "%.0f", model.peak), unit: "dB", accent: TT.rose)
                TTStat(title: "平均", value: String(format: "%.0f", model.avg), unit: "dB", accent: TT.teal)
                TTStat(title: "狀態", value: model.levelTitle, accent: model.levelColor)
            }
            waveBlock
            controlBlock
            TTPanel(accent: TT.amber, padding: 14) {
                Text("手機麥克風沒有經過聲壓計校準，讀數是相對音量（已對齊到常見環境級別），可以看出「現在比剛才吵多少」，但不等於專業分貝計的絕對值。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { model.request() }
        .onDisappear { model.stop() }
        .onReceive(model.$peak) { p in
            if p >= 100 { store.peakTask("db", value: p) }
        }
    }

    private var meterBlock: some View {
        TTPanel(accent: model.levelColor) {
            VStack(spacing: 13) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.0f", model.db))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .shadow(color: model.levelColor.opacity(0.45), radius: 18)
                    Text("dB")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.levelColor.opacity(0.85))
                        .padding(.bottom, 10)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(model.levelTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(model.levelColor)
                        Text(model.status)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                // 分段音量條
                HStack(spacing: 2.5) {
                    ForEach(0..<40, id: \.self) { i in
                        let lit = Double(i) / 40.0 * 120.0 < model.db
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(lit ? segmentColor(i) : Color.white.opacity(0.07))
                            .frame(height: CGFloat(10 + i / 4))
                    }
                }
                .frame(height: 20, alignment: .bottom)
            }
        }
    }

    private func segmentColor(_ i: Int) -> Color {
        if i >= 33 { return TT.rose }
        if i >= 25 { return Color(red: 1.0, green: 0.55, blue: 0.3) }
        if i >= 16 { return TT.amber }
        return TT.mint
    }

    private var waveBlock: some View {
        TTPanel(accent: TT.amber, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("即時波形")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.35))
                Canvas { ctx, size in
                    let step = size.width / CGFloat(max(model.history.count - 1, 1))
                    var line = Path()
                    for (i, v) in model.history.enumerated() {
                        let x = CGFloat(i) * step
                        let y = size.height - CGFloat(min(max(v / 110.0, 0), 1)) * size.height
                        if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                        else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(line,
                               with: .linearGradient(Gradient(colors: [TT.amber.opacity(0.5), TT.rose]),
                                                     startPoint: .zero,
                                                     endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 78)
            }
        }
    }

    private var controlBlock: some View {
        VStack(spacing: 9) {
            if model.denied {
                TTPanel(accent: TT.rose) {
                    VStack(spacing: 7) {
                        Text("需要麥克風權限")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("請到「設定 → 隱私權與安全性 → 麥克風」開啟後回來")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("前往設定", destination: url)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TT.mint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                TTButton(title: model.running ? "暫停量測" : "開始量測",
                         icon: model.running ? "pause.fill" : "waveform",
                         accent: TT.amber) {
                    if model.running { model.stop() } else { model.request() }
                }
                if model.avg > 0 {
                    Button {
                        model.reset()
                    } label: {
                        Text("重置峰值與平均")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
