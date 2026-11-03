import SwiftUI
import Foundation

// MARK: - 測速配色

private enum SpeedTheme {
    static let mint   = Color(red: 0.42, green: 0.96, blue: 0.84)
    static let teal   = Color(red: 0.36, green: 0.86, blue: 0.86)
    static let blue   = Color(red: 0.42, green: 0.70, blue: 1.00)
    static let indigo = Color(red: 0.44, green: 0.42, blue: 1.00)
    static let violet = Color(red: 0.66, green: 0.42, blue: 1.00)
    static let ink    = Color(red: 0.035, green: 0.045, blue: 0.070)

    static var ramp: LinearGradient {
        LinearGradient(colors: [mint, teal, blue, indigo],
                       startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - 網路取樣代理

private final class MeterDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    var onReceive: ((Int64) -> Void)?
    var onSend: ((Int64) -> Void)?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onReceive?(Int64(data.count))
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        onSend?(bytesSent)
    }
}

// MARK: - 測速引擎

final class SpeedEngine: ObservableObject {
    enum Phase: Int {
        case idle = 0, latency = 1, download = 2, upload = 3, done = 4
    }

    @Published var phase: Phase = .idle
    @Published var liveMbps: Double = 0
    @Published var ping: Double = 0
    @Published var jitter: Double = 0
    @Published var downMbps: Double = 0
    @Published var upMbps: Double = 0
    @Published var peakMbps: Double = 0
    @Published var samples: [Double] = Array(repeating: 0, count: 56)
    @Published var logs: [String] = []
    @Published var stageProgress: Double = 0
    @Published var isRunning = false

    private let edge = "https://speed.cloudflare.com"
    private var meter: MeterDelegate?
    private var session: URLSession?
    private var ticker: Timer?
    private var totalBytes: Int64 = 0
    private var lastBytes: Int64 = 0
    private var lastTick = Date()
    private var smooth: Double = 0

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.httpMaximumConnectionsPerHost = 4

        let d = MeterDelegate()
        d.onReceive = { [weak self] n in
            DispatchQueue.main.async { self?.totalBytes += n }
        }
        d.onSend = { [weak self] n in
            DispatchQueue.main.async { self?.totalBytes += n }
        }
        meter = d
        session = URLSession(configuration: cfg, delegate: d, delegateQueue: nil)
    }

    // MARK: 對外

    var phaseTitle: String {
        switch phase {
        case .idle:     return "待機"
        case .latency:  return "延遲測試"
        case .download: return "下載測試"
        case .upload:   return "上傳測試"
        case .done:     return "測試完成"
        }
    }

    var phaseHint: String {
        switch phase {
        case .idle:     return "點下方按鈕開始"
        case .latency:  return "正在量測往返延遲"
        case .download: return "正在拉取測試資料"
        case .upload:   return "正在推送測試資料"
        case .done:     return "已完成本次診斷"
        }
    }

    var qualityTitle: String {
        switch downMbps {
        case 150...:    return "極速"
        case 60..<150:  return "流暢"
        case 20..<60:   return "一般"
        default:        return "較慢"
        }
    }

    var qualityValue: Double {
        switch downMbps {
        case 150...:    return 1.0
        case 60..<150:  return 0.76
        case 20..<60:   return 0.5
        default:        return 0.26
        }
    }

    var qualityColor: Color {
        switch downMbps {
        case 150...:    return SpeedTheme.mint
        case 60..<150:  return SpeedTheme.teal
        case 20..<60:   return SpeedTheme.blue
        default:        return SpeedTheme.violet
        }
    }

    func start() {
        guard !isRunning else { return }
        reset()
        isRunning = true
        Task { await runAll() }
    }

    func stop() {
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        session?.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    // MARK: 內部流程

    private func reset() {
        phase = .idle
        liveMbps = 0
        ping = 0
        jitter = 0
        downMbps = 0
        upMbps = 0
        peakMbps = 0
        stageProgress = 0
        samples = Array(repeating: 0, count: 56)
        logs = []
        smooth = 0
    }

    private func runAll() async {
        await latencyStage()
        guard isRunning else { return }
        await downloadStage()
        guard isRunning else { return }
        await uploadStage()
        guard isRunning else { return }
        finish()
    }

    private func addLog(_ text: String) {
        logs.append(text)
        if logs.count > 24 { logs.removeFirst(logs.count - 24) }
    }

    private func latencyStage() async {
        phase = .latency
        stageProgress = 0
        addLog("節點 MINT-EDGE 已連線")
        addLog("開始量測往返延遲")

        var rtts: [Double] = []
        for i in 0..<8 {
            guard isRunning else { return }
            let t0 = Date()
            await pingOnce()
            let ms = Date().timeIntervalSince(t0) * 1000
            if i >= 2 { rtts.append(ms) }
            stageProgress = Double(i + 1) / 8.0
            addLog(String(format: "延遲取樣 %d/8 · %.0f ms", i + 1, ms))
            try? await Task.sleep(nanoseconds: 70_000_000)
        }

        let sorted = rtts.sorted()
        ping = sorted.isEmpty ? 0 : sorted[sorted.count / 2]

        if rtts.count > 1 {
            var diffs: [Double] = []
            for i in 1..<rtts.count { diffs.append(abs(rtts[i] - rtts[i - 1])) }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        } else {
            jitter = 0
        }

        liveMbps = 0
        addLog(String(format: "延遲 %.0f ms · 抖動 %.0f ms", ping, jitter))
    }

    private func pingOnce() async {
        var req = URLRequest(url: URL(string: edge + "/__down?bytes=0")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: req)
    }

    private func downloadStage() async {
        phase = .download
        stageProgress = 0
        addLog("開始量測下載帶寬")
        totalBytes = 0
        smooth = 0
        beginSampling()

        let want: Int64 = 60_000_000
        var req = URLRequest(url: URL(string: edge + "/__down?bytes=\(want)")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 30

        let task = session?.dataTask(with: req)
        let started = Date()
        task?.resume()

        var lastSeen: Int64 = 0
        var idleTicks = 0
        while Date().timeIntervalSince(started) < 10 {
            guard isRunning else { break }
            try? await Task.sleep(nanoseconds: 220_000_000)
            stageProgress = min(1, Date().timeIntervalSince(started) / 7.0)
            if totalBytes > 48_000_000 { break }
            if totalBytes == lastSeen {
                idleTicks += 1
                if idleTicks >= 4 { break }
            } else {
                idleTicks = 0
                lastSeen = totalBytes
            }
        }
        task?.cancel()

        let elapsed = max(Date().timeIntervalSince(started) - 0.35, 0.35)
        endSampling()

        let speed = Double(totalBytes) * 8.0 / 1_000_000.0 / elapsed
        downMbps = speed
        peakMbps = max(peakMbps, speed)
        liveMbps = speed
        stageProgress = 1
        addLog(String(format: "下載 %.1f Mbps", speed))
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    private func uploadStage() async {
        phase = .upload
        stageProgress = 0
        addLog("開始量測上傳帶寬")
        totalBytes = 0
        smooth = 0
        beginSampling()

        let payload = Data(count: 12_000_000)
        var req = URLRequest(url: URL(string: edge + "/__up")!)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 30

        let task = session?.uploadTask(with: req, from: payload)
        let started = Date()
        task?.resume()

        var lastSeen: Int64 = 0
        var idleTicks = 0
        while Date().timeIntervalSince(started) < 12 {
            guard isRunning else { break }
            try? await Task.sleep(nanoseconds: 220_000_000)
            stageProgress = min(1, Date().timeIntervalSince(started) / 8.0)
            if totalBytes >= Int64(payload.count) { break }
            if totalBytes == lastSeen {
                idleTicks += 1
                if idleTicks >= 6 { break }
            } else {
                idleTicks = 0
                lastSeen = totalBytes
            }
        }
        task?.cancel()

        let elapsed = max(Date().timeIntervalSince(started) - 0.35, 0.35)
        endSampling()

        let speed = Double(totalBytes) * 8.0 / 1_000_000.0 / elapsed
        upMbps = speed
        peakMbps = max(peakMbps, speed)
        liveMbps = speed
        stageProgress = 1
        addLog(String(format: "上傳 %.1f Mbps", speed))
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func finish() {
        NotificationCenter.default.post(name: .pvNetDiag, object: nil)
        phase = .done
        isRunning = false
        stageProgress = 1
        liveMbps = downMbps
        if downMbps < 0.05 && upMbps < 0.05 {
            addLog("測試節點無回應，請確認網路後重試")
        } else {
            addLog("診斷完成 · 品質 " + qualityTitle)
        }
    }

    // MARK: 取樣

    private func beginSampling() {
        lastBytes = totalBytes
        lastTick = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = ticker { RunLoop.main.add(t, forMode: .common) }
    }

    private func endSampling() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        guard dt > 0.001 else { return }
        let total = totalBytes
        let delta = max(total - lastBytes, 0)
        lastBytes = total
        lastTick = now

        let instant = Double(delta) * 8.0 / 1_000_000.0 / dt
        smooth = smooth == 0 ? instant : smooth * 0.55 + instant * 0.45
        if smooth > peakMbps { peakMbps = smooth }
        if phase == .download || phase == .upload {
            liveMbps = smooth
        }

        samples.removeFirst()
        samples.append(smooth)
    }
}

// MARK: - 儀表盤

private struct SpeedDialCanvas: View {
    var value: Double
    var phase: SpeedEngine.Phase
    @State private var spin: Double = 0

    private let scaleMax: Double = 350

    private func fraction(_ v: Double) -> Double {
        let x = min(max(v, 0), scaleMax)
        return log(1 + x) / log(1 + scaleMax)
    }

    var body: some View {
        ZStack {
            // 外圈虛線軌道（緩慢旋轉）
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1.5, 7]))
                .foregroundStyle(SpeedTheme.mint.opacity(0.28))
                .padding(2)
                .rotationEffect(.degrees(spin))
                .onAppear {
                    withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
                        spin = 360
                    }
                }

            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 20
                let start = 135.0
                let total = 270.0

                var track = Path()
                track.addArc(center: center, radius: radius,
                             startAngle: .degrees(start),
                             endAngle: .degrees(start + total),
                             clockwise: false)
                ctx.stroke(track, with: .color(.white.opacity(0.095)),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round))

                // 待機時的底層微光，避免表盤過空
                if fraction(value) <= 0.004 {
                    var idleArc = Path()
                    idleArc.addArc(center: center, radius: radius,
                                   startAngle: .degrees(start + 12),
                                   endAngle: .degrees(start + total - 12),
                                   clockwise: false)
                    ctx.stroke(idleArc, with: .color(SpeedTheme.teal.opacity(0.10)),
                               style: StrokeStyle(lineWidth: 9, lineCap: .round))
                }

                let f = fraction(value)
                if f > 0.004 {
                    var arc = Path()
                    arc.addArc(center: center, radius: radius,
                               startAngle: .degrees(start),
                               endAngle: .degrees(start + total * f),
                               clockwise: false)
                    ctx.stroke(arc,
                               with: .linearGradient(
                                    Gradient(colors: [SpeedTheme.mint, SpeedTheme.teal,
                                                      SpeedTheme.blue, SpeedTheme.indigo]),
                                    startPoint: CGPoint(x: center.x - radius, y: center.y + radius * 0.4),
                                    endPoint: CGPoint(x: center.x + radius, y: center.y - radius * 0.4)),
                               style: StrokeStyle(lineWidth: 9, lineCap: .round))

                    // 弧末端光點
                    let ang = (start + total * f) * Double.pi / 180
                    let px = center.x + CGFloat(cos(ang)) * radius
                    let py = center.y + CGFloat(sin(ang)) * radius
                    let dot = CGRect(x: px - 4.5, y: py - 4.5, width: 9, height: 9)
                    ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.92)))
                    let glow = CGRect(x: px - 10, y: py - 10, width: 20, height: 20)
                    ctx.fill(Path(ellipseIn: glow), with: .color(SpeedTheme.mint.opacity(0.22)))
                }

                // 刻度
                for i in 0...54 {
                    let p = Double(i) / 54.0
                    let ang = (start + total * p) * Double.pi / 180
                    let major = i % 6 == 0
                    let inner = radius - 20
                    let outer = radius - (major ? 11 : 16)
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + CGFloat(cos(ang)) * inner,
                                          y: center.y + CGFloat(sin(ang)) * inner))
                    tick.addLine(to: CGPoint(x: center.x + CGFloat(cos(ang)) * outer,
                                             y: center.y + CGFloat(sin(ang)) * outer))
                    ctx.stroke(tick,
                               with: .color(.white.opacity(major ? 0.38 : 0.17)),
                               lineWidth: major ? 1.4 : 1)
                }

                // 刻度數字
                let marks: [(Double, String)] = [(0, "0"), (50, "50"), (100, "100"), (200, "200"), (350, "350")]
                for (v, label) in marks {
                    let a = (start + total * fraction(v)) * Double.pi / 180
                    let rr = radius - 30
                    ctx.draw(Text(label)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.26)),
                             at: CGPoint(x: center.x + CGFloat(cos(a)) * rr,
                                         y: center.y + CGFloat(sin(a)) * rr))
                }
            }
            .padding(10)
        }
    }
}

// MARK: - 即時波形

private struct SpeedWave: View {
    var samples: [Double]
    var accent: Color

    var body: some View {
        Canvas { ctx, size in
            let peak = max(samples.max() ?? 1, 8)
            let count = max(samples.count - 1, 1)
            let stepX = size.width / CGFloat(count)

            var line = Path()
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))

            for (i, v) in samples.enumerated() {
                let x = CGFloat(i) * stepX
                let ratio = CGFloat(min(v / peak, 1))
                let y = size.height - ratio * (size.height - 8) - 4
                if i == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
                area.addLine(to: CGPoint(x: x, y: y))
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()

            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [accent.opacity(0.30), accent.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)))

            ctx.stroke(line, with: .linearGradient(
                Gradient(colors: [accent.opacity(0.35), accent]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - 主畫面

struct SpeedTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = SpeedEngine()
    @State private var appear = false

    var body: some View {
        ZStack {
            Backdrop()
            TechGrid()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        dialBlock
                        waveBlock
                        stageRail
                        resultGrid
                        qualityBlock
                        consoleBlock
                        actionButton
                            .padding(.top, 4)
                        Text("測試經第三方公共節點量測，結果僅供參考")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.22))
                            .padding(.bottom, 26)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appear = true } }
        .onDisappear { engine.stop() }
    }

    // MARK: 頂欄

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                engine.stop()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("網路診斷")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text("NETWORK DIAGNOSTICS")
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.8)
                    .foregroundStyle(SpeedTheme.mint.opacity(0.55))
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(engine.isRunning ? SpeedTheme.mint : Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(engine.isRunning ? "LIVE" : "IDLE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: 儀表

    private var dialBlock: some View {
        ZStack {
            SpeedDialCanvas(value: engine.liveMbps, phase: engine.phase)
                .frame(width: 252, height: 252)

            VStack(spacing: 3) {
                Text(String(format: "%.1f", engine.liveMbps))
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .shadow(color: SpeedTheme.mint.opacity(0.35), radius: 18)

                Text("Mbps")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.35))

                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.isRunning ? SpeedTheme.mint : Color.white.opacity(0.35))
                        .frame(width: 4, height: 4)
                    Text(engine.phaseTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.top, 8)
            }
        }
        .opacity(appear ? 1 : 0)
        .scaleEffect(appear ? 1 : 0.94)
    }

    // MARK: 波形

    private var waveBlock: some View {
        VStack(spacing: 7) {
            HStack {
                Text("即時吞吐")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.34))
                Spacer()
                Text(String(format: "峰值 %.1f Mbps", engine.peakMbps))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.30))
            }
            SpeedWave(samples: engine.samples, accent: SpeedTheme.teal)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
        }
    }

    // MARK: 階段條

    private var stageRail: some View {
        HStack(spacing: 6) {
            stageNode(index: 1, title: "延遲")
            stageBar(active: engine.phase == .latency)
            stageNode(index: 2, title: "下載")
            stageBar(active: engine.phase == .download)
            stageNode(index: 3, title: "上傳")
        }
        .padding(.horizontal, 4)
    }

    private func stageNode(index: Int, title: String) -> some View {
        let cur = engine.phase.rawValue
        let done = cur > index
        let active = cur == index
        return HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(done ? SpeedTheme.mint.opacity(0.9) : (active ? SpeedTheme.teal.opacity(0.22) : Color.white.opacity(0.07)))
                    .frame(width: 15, height: 15)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(SpeedTheme.ink)
                } else {
                    Circle()
                        .fill(active ? SpeedTheme.teal : Color.white.opacity(0.25))
                        .frame(width: 4.5, height: 4.5)
                }
            }
            Text(title)
                .font(.system(size: 11, weight: active || done ? .semibold : .regular))
                .foregroundStyle(active ? Color.white.opacity(0.95) : Color.white.opacity(done ? 0.6 : 0.32))
        }
    }

    private func stageBar(active: Bool) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2)
            Capsule()
                .fill(SpeedTheme.ramp)
                .frame(width: active ? 28 : 0, height: 2)
                .animation(.easeInOut(duration: 0.4), value: active)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 結果

    private var resultGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            resultCell(icon: "waveform.path.ecg", label: "延遲",
                       value: engine.ping > 0 ? String(format: "%.0f", engine.ping) : "--",
                       unit: "ms", sub: "往返時間")
            resultCell(icon: "arrow.left.arrow.right", label: "抖動",
                       value: engine.jitter > 0 ? String(format: "%.0f", engine.jitter) : "--",
                       unit: "ms", sub: "延遲波動")
            resultCell(icon: "arrow.down.circle", label: "下載",
                       value: engine.downMbps > 0 ? String(format: "%.1f", engine.downMbps) : "--",
                       unit: "Mbps", sub: "下行帶寬")
            resultCell(icon: "arrow.up.circle", label: "上傳",
                       value: engine.upMbps > 0 ? String(format: "%.1f", engine.upMbps) : "--",
                       unit: "Mbps", sub: "上行帶寬")
        }
    }

    private func resultCell(icon: String, label: String, value: String, unit: String, sub: String) -> some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(LinearGradient(colors: [SpeedTheme.mint.opacity(0.9), SpeedTheme.teal.opacity(0.25)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(SpeedTheme.teal.opacity(0.85))
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.46))
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.20))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: 品質

    private var qualityBlock: some View {
        VStack(spacing: 9) {
            HStack {
                Text("連線品質")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.34))
                Spacer()
                Text(engine.downMbps > 0 ? engine.qualityTitle : "待量測")
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(engine.downMbps > 0 ? engine.qualityColor : Color.white.opacity(0.3))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(colors: [SpeedTheme.blue, SpeedTheme.teal, SpeedTheme.mint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * engine.qualityValue, engine.downMbps > 0 ? 12 : 0))
                        .animation(.easeOut(duration: 0.6), value: engine.qualityValue)
                }
            }
            .frame(height: 5)

            HStack {
                Text("較慢").font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.2))
                Spacer()
                Text("一般").font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.2))
                Spacer()
                Text("流暢").font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.2))
                Spacer()
                Text("極速").font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: 終端日誌

    private var consoleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(SpeedTheme.mint.opacity(0.8)).frame(width: 4, height: 4)
                Text("DIAGNOSTIC LOG")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.28))
                Spacer()
            }
            ForEach(Array(engine.logs.suffix(3).enumerated()), id: \.offset) { _, line in
                Text("› " + line)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.40))
                    .lineLimit(1)
            }
            if engine.logs.isEmpty {
                Text("› 等待開始 …")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.22))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
        )
    }

    // MARK: 按鈕

    private var actionButton: some View {
        Button {
            if engine.isRunning {
                engine.stop()
            } else {
                engine.start()
            }
        } label: {
            HStack(spacing: 8) {
                if engine.isRunning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: engine.phase == .done ? "arrow.clockwise" : "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(buttonTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(1)
            }
            .foregroundStyle(SpeedTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [SpeedTheme.mint, SpeedTheme.teal, SpeedTheme.blue],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: SpeedTheme.teal.opacity(0.35), radius: 18, y: 8)
            .opacity(engine.isRunning ? 0.85 : 1)
        }
        .disabled(engine.isRunning)
    }

    private var buttonTitle: String {
        if engine.isRunning { return "測試中…" }
        return engine.phase == .done ? "重新測試" : "開始測試"
    }
}
