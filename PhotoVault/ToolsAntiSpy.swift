import SwiftUI
import AVFoundation
import CoreImage
import UIKit

// MARK: - 掃描模式

enum AntiSpyMode: String, CaseIterable, Identifiable {
    case infrared = "紅外掃描"
    case reflection = "反光掃描"

    var id: String { rawValue }

    var en: String {
        switch self {
        case .infrared:   return "INFRARED"
        case .reflection: return "RETROREFLECTION"
        }
    }

    var icon: String {
        switch self {
        case .infrared:   return "moon.stars.fill"
        case .reflection: return "flashlight.on.fill"
        }
    }

    var summary: String {
        switch self {
        case .infrared:
            return "關燈後把感光拉到極限，找肉眼看不見、只有夜視針孔才會發出的紫紅光點。這一招命中率最高。"
        case .reflection:
            return "開閃光燈掃，找鏡頭玻璃回彈的圓形高光。玻璃杯、金屬、指示燈都會回彈，所以只列「可疑反光」，不下結論。"
        }
    }

    var steps: [String] {
        switch self {
        case .infrared:
            return ["關掉房裡所有燈、拉上窗簾，等眼睛適應十秒",
                    "手機慢慢掃過：煙霧偵測器、電視、插座、冷氣出風口、床頭",
                    "看到亮點先別下結論，靠近看是不是待機指示燈"]
        case .reflection:
            return ["留一盞燈就好，全黑反而沒有環境光可比對",
                    "手機放眼睛高度，慢慢平移，讓閃光燈掃過每個可疑表面",
                    "正對鏡頭時反光最亮，稍微偏一點就滅掉——這是鏡頭的特徵"]
        }
    }
}

// MARK: - 靈敏度

enum AntiSpySensitivity: String, CaseIterable, Identifiable {
    case low = "低"
    case standard = "標準"
    case high = "高"

    var id: String { rawValue }

    var lumaGate: Int {
        switch self {
        case .low:      return 178
        case .standard: return 158
        case .high:     return 142
        }
    }

    var contrastGate: Int {
        switch self {
        case .low:      return 48
        case .standard: return 36
        case .high:     return 28
        }
    }

    var irGate: Int {
        switch self {
        case .low:      return 24
        case .standard: return 16
        case .high:     return 10
        }
    }

    var note: String {
        switch self {
        case .low:      return "最嚴，只抓明顯的持續亮點，誤報最少"
        case .standard: return "平衡，一般房間用這個"
        case .high:     return "最靈敏，雜訊也會進來，只當線索"
        }
    }
}

// MARK: - 光點

struct DetectedSpot {
    var nx: Double          // 0..1，緩衝區座標
    var ny: Double
    var radius: Double      // 佔畫面短邊的比例
    var strength: Double    // 0..1
    var ir: Double          // 紅光超出綠光的程度
    var area: Int
}

private struct SpotTrack {
    var nx: Double
    var ny: Double
    var hits: Int = 0
    var windowHits: Int = 0
    var misses: Int = 0
    var best: DetectedSpot
}

// MARK: - 證據

struct SpotBox: Identifiable {
    let id = UUID()
    var cx: Double      // 0..1，正立影像座標
    var cy: Double
    var r: Double       // 佔短邊比例
    var strength: Double
}

enum EvidenceLevel: String {
    case brief = "間歇亮點"
    case steady = "持續亮點"

    var color: Color {
        switch self {
        case .brief:  return TT.amber
        case .steady: return TT.rose
        }
    }
}

struct EvidenceItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var boxes: [SpotBox]
    var mode: AntiSpyMode
    var level: EvidenceLevel
    var hits: Int
    var date: Date
    var strength: Double
}

// MARK: - 幀分析

enum FrameAnalyzer {
    static let gw = 160
    static let gh = 90

    struct Result {
        var spots: [DetectedSpot] = []
        var medianLuma: Double = 0
        var peakLuma: Double = 0
    }

    static func analyze(_ buffer: CVPixelBuffer,
                        sensitivity: AntiSpySensitivity,
                        mode: AntiSpyMode) -> Result {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return Result() }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 8, h > 8 else { return Result() }

        let p = base.assumingMemoryBound(to: UInt8.self)
        var luma = [UInt8](repeating: 0, count: gw * gh)
        var irMap = [Int](repeating: 0, count: gw * gh)

        let cw = max(1, w / gw)
        let ch = max(1, h / gh)
        let step = max(1, min(cw, ch) / 4)

        for gy in 0..<gh {
            let y0 = gy * ch
            for gx in 0..<gw {
                let x0 = gx * cw
                var sr = 0, sg = 0, sb = 0, n = 0
                var yy = y0
                while yy < min(y0 + ch, h) {
                    let row = p + yy * bytesPerRow
                    var xx = x0
                    while xx < min(x0 + cw, w) {
                        let o = xx * 4
                        sb += Int(row[o])
                        sg += Int(row[o + 1])
                        sr += Int(row[o + 2])
                        n += 1
                        xx += step
                    }
                    yy += step
                }
                guard n > 0 else { continue }
                let r = sr / n, g = sg / n, b = sb / n
                let idx = gy * gw + gx
                let l = (77 * r + 150 * g + 29 * b) >> 8
                luma[idx] = UInt8(max(0, min(255, l)))
                irMap[idx] = r - g
            }
        }

        // 背景亮度（積分圖做方框模糊）
        var integral = [Int](repeating: 0, count: (gw + 1) * (gh + 1))
        for y in 0..<gh {
            var rowSum = 0
            for x in 0..<gw {
                rowSum += Int(luma[y * gw + x])
                integral[(y + 1) * (gw + 1) + (x + 1)] = integral[y * (gw + 1) + (x + 1)] + rowSum
            }
        }

        func boxSum(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int {
            let a = integral[y0 * (gw + 1) + x0]
            let b = integral[y0 * (gw + 1) + x1]
            let c = integral[y1 * (gw + 1) + x0]
            let d = integral[y1 * (gw + 1) + x1]
            return d - b - c + a
        }

        let radius = 6
        var bg = [Int](repeating: 0, count: gw * gh)
        for y in 0..<gh {
            let y0 = max(0, y - radius), y1 = min(gh, y + radius + 1)
            for x in 0..<gw {
                let x0 = max(0, x - radius), x1 = min(gw, x + radius + 1)
                let s = boxSum(x0, y0, x1, y1)
                let c = max(1, (x1 - x0) * (y1 - y0))
                bg[y * gw + x] = s / c
            }
        }

        // 亮度中位數
        var hist = [Int](repeating: 0, count: 256)
        for i in 0..<(gw * gh) { hist[Int(luma[i])] += 1 }
        var acc = 0
        var median = 0
        let half = (gw * gh) / 2
        for v in 0..<256 {
            acc += hist[v]
            if acc >= half { median = v; break }
        }
        var peak = 0
        for i in 0..<(gw * gh) { peak = max(peak, Int(luma[i])) }

        // 候選遮罩
        var mask = [Bool](repeating: false, count: gw * gh)
        for i in 0..<(gw * gh) {
            let l = Int(luma[i])
            let c = l - bg[i]
            if l >= sensitivity.lumaGate && c >= sensitivity.contrastGate && irMap[i] >= sensitivity.irGate {
                mask[i] = true
            }
        }

        // 連通元件
        var visited = [Bool](repeating: false, count: gw * gh)
        var stack = [Int]()
        var spots: [DetectedSpot] = []

        for start in 0..<(gw * gh) {
            if !mask[start] || visited[start] { continue }
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true

            var count = 0, sx = 0, sy = 0
            var minX = gw, maxX = 0, minY = gh, maxY = 0
            var sumL = 0, maxL = 0, sumIR = 0, maxIR = 0

            while let i = stack.popLast() {
                let x = i % gw
                let y = i / gw
                count += 1; sx += x; sy += y
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                let l = Int(luma[i]); sumL += l
                if l > maxL { maxL = l }
                let v = irMap[i]; sumIR += v
                if v > maxIR { maxIR = v }

                if x > 0 {
                    let j = i - 1
                    if mask[j] && !visited[j] { visited[j] = true; stack.append(j) }
                }
                if x < gw - 1 {
                    let j = i + 1
                    if mask[j] && !visited[j] { visited[j] = true; stack.append(j) }
                }
                if y > 0 {
                    let j = i - gw
                    if mask[j] && !visited[j] { visited[j] = true; stack.append(j) }
                }
                if y < gh - 1 {
                    let j = i + gw
                    if mask[j] && !visited[j] { visited[j] = true; stack.append(j) }
                }
            }

            let bw = maxX - minX + 1
            let bh = maxY - minY + 1
            guard count >= 2, count <= 120 else { continue }
            guard bw <= 26, bh <= 26 else { continue }
            guard bw >= 1, bh >= 1 else { continue }

            let fill = Double(count) / Double(bw * bh)
            let aspect = Double(max(bw, bh)) / Double(max(1, min(bw, bh)))
            guard fill >= 0.40, aspect <= 2.8 else { continue }

            let meanL = Double(sumL) / Double(count)
            let meanIR = Double(sumIR) / Double(count)
            guard meanL >= Double(sensitivity.lumaGate) + 12 else { continue }

            let cx = Double(sx) / Double(count)
            let cy = Double(sy) / Double(count)

            // 光暈：真光源會有外擴，感光壞點是硬邊
            let r0 = max(2.6, Double(max(bw, bh)) * 0.85)
            let r1 = r0 + 5.0
            var haloSum = 0.0
            var haloCnt = 0
            for k in 0..<24 {
                let ang = Double(k) * .pi / 12.0
                var rr = r0
                while rr <= r1 {
                    let px = Int(cx + cos(ang) * rr)
                    let py = Int(cy + sin(ang) * rr)
                    if px >= 0, px < gw, py >= 0, py < gh {
                        let i = py * gw + px
                        haloSum += Double(Int(luma[i]) - bg[i])
                        haloCnt += 1
                    }
                    rr += 1.6
                }
            }
            let halo = haloCnt > 0 ? haloSum / Double(haloCnt) : 0

            // 硬邊壞點：面積小、沒有光暈
            guard halo >= 2.0 || count >= 4 else { continue }

            let irBoost = mode == .infrared ? 1.0 : 0.7
            let strength = min(1.0, max(0.0,
                (meanL / 255.0) * 0.55 +
                (min(meanIR, 90.0) / 90.0) * 0.30 * irBoost +
                (min(halo, 40.0) / 40.0) * 0.15))

            let sizeFactor = max(Double(bw), Double(bh)) / Double(gw)
            spots.append(DetectedSpot(nx: cx / Double(gw),
                                      ny: cy / Double(gh),
                                      radius: max(0.012, sizeFactor * 1.6),
                                      strength: strength,
                                      ir: meanIR,
                                      area: count))
        }

        spots.sort { $0.strength > $1.strength }
        return Result(spots: Array(spots.prefix(12)),
                      medianLuma: Double(median),
                      peakLuma: Double(peak))
    }
}

// MARK: - 引擎

enum AntiSpyPhase: String {
    case idle, reference, settle, scanning, finished
}

final class AntiSpyEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published private(set) var phase: AntiSpyPhase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = "待機"
    @Published private(set) var signal: Double = 0
    @Published private(set) var evidence: [EvidenceItem] = []
    @Published private(set) var liveCount: Int = 0
    @Published private(set) var roomTooBright: Bool = false
    @Published private(set) var cameraFailed: Bool = false
    @Published private(set) var torchAvailable: Bool = true
    @Published var sensitivity: AntiSpySensitivity = .standard
    @Published var mode: AntiSpyMode = .infrared

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "yuansun.antispy.session")
    private let analysisQueue = DispatchQueue(label: "yuansun.antispy.analysis", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let stateLock = NSLock()

    private var device: AVCaptureDevice?
    private var configured = false
    private var running = false

    private var _state: AntiSpyPhase = .idle
    private var state: AntiSpyPhase {
        get {
            stateLock.lock()
            let v = _state
            stateLock.unlock()
            return v
        }
        set {
            stateLock.lock()
            _state = newValue
            stateLock.unlock()
            DispatchQueue.main.async { self.phase = newValue }
        }
    }

    private var frameIndex = 0
    private var refFrames = 0
    private var settleFrames = 0
    private var scanStart: Date?
    private let scanLength: TimeInterval = 8

    private var refSpots: [(Double, Double)] = []
    private var tracks: [SpotTrack] = []
    private var accepted: [(Double, Double)] = []
    private var brightFrames = 0
    private var lastPublish = Date.distantPast

    var isScanning: Bool {
        phase == .reference || phase == .settle || phase == .scanning
    }

    // MARK: 生命週期

    func prepare() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if ok { self.configureAndRun() } else { self.fail("沒有相機權限") }
                }
            }
        default:
            fail("相機權限被關閉，請到「設定 → 隱私權與安全性 → 相機」開啟")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setTorch(false)
            self.restoreAutoExposure()
            if self.session.isRunning { self.session.stopRunning() }
            self.running = false
            self.state = .idle
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured {
                guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .back),
                      let input = try? AVCaptureDeviceInput(device: dev) else {
                    DispatchQueue.main.async { self.fail("無法啟動相機") }
                    return
                }
                self.device = dev
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                if self.session.canAddInput(input) { self.session.addInput(input) }
                self.output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.output.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.output) {
                    self.session.addOutput(self.output)
                    self.output.setSampleBufferDelegate(self, queue: self.analysisQueue)
                }
                self.session.commitConfiguration()
                self.configured = true

                let torch = dev.hasTorch && dev.isTorchAvailable
                DispatchQueue.main.async { self.torchAvailable = torch }
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.running = true
            DispatchQueue.main.async { self.statusText = "待機" }
        }
    }

    private func fail(_ msg: String) {
        let text = msg
        DispatchQueue.main.async {
            self.statusText = text
            self.cameraFailed = true
            self.phase = .idle
        }
    }

    // MARK: 曝光 / 閃光燈

    private func applyReferenceExposure() {
        setTorch(false)
        guard let dev = device else { return }
        do {
            try dev.lockForConfiguration()
            defer { dev.unlockForConfiguration() }
            // 參考幀刻意固定短曝光：暗房裡若放任自動曝光，
            // 相機會自己把曝光拉長，真正的紅外光源會被誤記成「本來就看得到」。
            if dev.isExposureModeSupported(.custom) {
                let dur = CMTime(value: 1, timescale: 60)
                let iso = max(dev.activeFormat.minISO,
                              min(dev.activeFormat.maxISO, 220.0))
                dev.setExposureModeCustom(duration: dur, iso: iso, completionHandler: nil)
            } else if dev.isExposureModeSupported(.continuousAutoExposure) {
                dev.exposureMode = .continuousAutoExposure
            }
        } catch { }
    }

    private func applyScanExposure(_ scanMode: AntiSpyMode) {
        guard let dev = device else { return }
        do {
            try dev.lockForConfiguration()
            defer { dev.unlockForConfiguration() }

            if scanMode == .reflection && dev.hasTorch && dev.isTorchAvailable {
                try? dev.setTorchModeOn(level: 1.0)
                if dev.isExposureModeSupported(.custom) {
                    let dur = CMTime(value: 1, timescale: 240)
                    let iso = max(dev.activeFormat.minISO, min(160.0, dev.activeFormat.maxISO))
                    dev.setExposureModeCustom(duration: dur, iso: iso, completionHandler: nil)
                }
            } else {
                dev.torchMode = .off
                if dev.isExposureModeSupported(.custom) {
                    let maxSec = CMTimeGetSeconds(dev.activeFormat.maxExposureDuration)
                    let target = min(maxSec, 0.08)
                    let dur = CMTime(seconds: max(0.008, target), preferredTimescale: 1000)
                    let iso = max(dev.activeFormat.minISO,
                                  min(dev.activeFormat.maxISO, 3200.0))
                    dev.setExposureModeCustom(duration: dur, iso: iso, completionHandler: nil)
                }
            }
        } catch { }
    }

    private func setTorch(_ on: Bool) {
        guard let dev = device, dev.hasTorch, dev.isTorchAvailable else { return }
        do {
            try dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
        } catch { }
    }

    private func restoreAutoExposure() {
        guard let dev = device else { return }
        do {
            try dev.lockForConfiguration()
            if dev.isExposureModeSupported(.continuousAutoExposure) {
                dev.exposureMode = .continuousAutoExposure
            }
            dev.unlockForConfiguration()
        } catch { }
    }

    // MARK: 掃描控制

    func startScan() {
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameIndex = 0
            self.refFrames = 0
            self.settleFrames = 0
            self.refSpots.removeAll()
            self.tracks.removeAll()
            self.accepted.removeAll()
            self.brightFrames = 0
            self.scanStart = nil
            self.lastPublish = Date.distantPast
            self.state = .reference
        }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.applyReferenceExposure()
        }
        DispatchQueue.main.async {
            self.progress = 0
            self.signal = 0
            self.liveCount = 0
            self.roomTooBright = false
            self.statusText = "正在記錄現場光源…"
        }
    }

    func reset() {
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            self.refSpots.removeAll()
            self.tracks.removeAll()
            self.accepted.removeAll()
            self.scanStart = nil
            self.state = .idle
        }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setTorch(false)
            self.restoreAutoExposure()
        }
        progress = 0
        signal = 0
        liveCount = 0
        statusText = "待機"
        evidence.removeAll()
        roomTooBright = false
    }

    // MARK: 幀回呼

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let current = state
        guard current == .reference || current == .settle || current == .scanning else { return }
        guard running, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentMode = mode
        let sens = sensitivity
        let result = FrameAnalyzer.analyze(pb, sensitivity: sens, mode: currentMode)
        frameIndex += 1

        switch current {
        case .reference:
            for s in result.spots { refSpots.append((s.nx, s.ny)) }
            refFrames += 1
            if refFrames >= 10 {
                state = .settle
                settleFrames = 0
                sessionQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.applyScanExposure(currentMode)
                }
                publish(currentMode == .reflection ? "閃光燈已開啟，開始掃描…" : "感光拉到極限，開始掃描…")
            } else {
                publish("正在記錄現場光源…")
            }

        case .settle:
            settleFrames += 1
            if settleFrames >= 6 {
                scanStart = Date()
                state = .scanning
            }
            publish("調整感光中…")

        case .scanning:
            processScan(result, buffer: pb, scanMode: currentMode)

        default:
            break
        }
    }

    private func processScan(_ result: FrameAnalyzer.Result,
                             buffer: CVPixelBuffer,
                             scanMode: AntiSpyMode) {
        guard let start = scanStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        let ratio = min(1.0, elapsed / scanLength)

        if scanMode == .infrared {
            if result.medianLuma > 108 {
                brightFrames += 1
            } else {
                brightFrames = max(0, brightFrames - 1)
            }
            if brightFrames > 12 {
                if roomTooBright == false {
                    DispatchQueue.main.async { self.roomTooBright = true }
                }
            }
        }

        var fresh: [DetectedSpot] = []
        for s in result.spots {
            var isKnown = false
            for r in refSpots where hypot(r.0 - s.nx, r.1 - s.ny) < 0.035 {
                isKnown = true
                break
            }
            if !isKnown { fresh.append(s) }
        }

        for s in fresh {
            var matched = false
            for i in tracks.indices {
                if hypot(tracks[i].nx - s.nx, tracks[i].ny - s.ny) < 0.038 {
                    tracks[i].nx = tracks[i].nx * 0.6 + s.nx * 0.4
                    tracks[i].ny = tracks[i].ny * 0.6 + s.ny * 0.4
                    tracks[i].hits += 1
                    tracks[i].windowHits += 1
                    tracks[i].misses = 0
                    if s.strength > tracks[i].best.strength { tracks[i].best = s }
                    matched = true
                    break
                }
            }
            if !matched {
                tracks.append(SpotTrack(nx: s.nx, ny: s.ny, hits: 1,
                                        windowHits: 1, misses: 0, best: s))
            }
        }

        for i in tracks.indices {
            let hit = fresh.contains { hypot($0.nx - tracks[i].nx, $0.ny - tracks[i].ny) < 0.038 }
            if !hit {
                tracks[i].misses += 1
                tracks[i].windowHits = max(0, tracks[i].windowHits - 1)
            }
        }
        tracks.removeAll { $0.misses > 3 || $0.windowHits == 0 }

        var newlyConfirmed: [SpotTrack] = []
        for t in tracks where t.windowHits >= 12 {
            let dup = accepted.contains { hypot($0.0 - t.nx, $0.1 - t.ny) < 0.06 }
            if !dup { newlyConfirmed.append(t) }
        }

        if let top = newlyConfirmed.max(by: { $0.windowHits < $1.windowHits }),
           let shot = makeEvidence(from: buffer, track: top, scanMode: scanMode) {
            accepted.append((top.nx, top.ny))
            tracks.removeAll { hypot($0.nx - top.nx, $0.ny - top.ny) < 0.06 }
            DispatchQueue.main.async { self.evidence.append(shot) }
        }

        let best = tracks.map { $0.best.strength }.max() ?? 0.0
        let count = tracks.filter { $0.windowHits >= 4 }.count

        if Date().timeIntervalSince(lastPublish) > 0.1 {
            lastPublish = Date()
            let p = ratio
            let b = best
            let c = count
            let remain = max(0, Int(scanLength - ratio * scanLength))
            DispatchQueue.main.async {
                self.progress = p
                self.signal = b
                self.liveCount = c
                if self.state == .scanning {
                    self.statusText = "掃描中…剩 \(remain) 秒"
                }
            }
        }

        if elapsed >= scanLength { finish() }
    }

    private func finish() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.setTorch(false)
            self.restoreAutoExposure()
        }
        state = .finished
        DispatchQueue.main.async {
            self.progress = 1
            self.signal = 0
            self.liveCount = 0
            if self.evidence.isEmpty {
                self.statusText = "掃描完成，本次沒有記錄到可疑光源"
            } else {
                self.statusText = "掃描完成，記錄到 \(self.evidence.count) 個亮點"
            }
        }
    }

    private func publish(_ text: String) {
        let value = text
        DispatchQueue.main.async { self.statusText = value }
    }

    // MARK: 證據

    private func makeEvidence(from buffer: CVPixelBuffer,
                              track: SpotTrack,
                              scanMode: AntiSpyMode) -> EvidenceItem? {
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        let rotated = cg.width > cg.height
        let image = AntiSpyEngine.uprightImage(cg, rotateCW: rotated)

        var bx = track.nx
        var by = track.ny
        if rotated {
            bx = 1.0 - track.ny
            by = track.nx
        }

        let box = SpotBox(cx: bx, cy: by,
                          r: max(0.03, track.best.radius),
                          strength: track.best.strength)

        return EvidenceItem(image: image,
                            boxes: [box],
                            mode: scanMode,
                            level: track.windowHits >= 24 ? .steady : .brief,
                            hits: track.windowHits,
                            date: Date(),
                            strength: track.best.strength)
    }

    static func uprightImage(_ cg: CGImage, rotateCW: Bool) -> UIImage {
        let w = cg.width
        let h = cg.height
        let outSize = rotateCW ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: outSize, format: fmt).image { ctx in
            let c = ctx.cgContext
            if rotateCW {
                c.translateBy(x: CGFloat(h), y: 0)
                c.rotate(by: .pi / 2)
            }
            c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }
}

// MARK: - 檢查清單

struct AntiSpyCheckItem: Identifiable {
    let id: String
    let title: String
    let level: Int
    let detail: String

    static let all: [AntiSpyCheckItem] = [
        AntiSpyCheckItem(id: "smoke", title: "煙霧偵測器", level: 3,
                         detail: "天花板第一名。拿手機貼近看有沒有異常小孔、顏色不均的圓點。真正的偵測器有小縫隙進氣，假的多半是整片平整。"),
        AntiSpyCheckItem(id: "tv", title: "電視與機上盒", level: 3,
                         detail: "電源指示燈旁、喇叭網罩、邊框接縫。用紅外模式貼近掃，越暗越準。"),
        AntiSpyCheckItem(id: "socket", title: "插座與開關面板", level: 3,
                         detail: "面板螺絲有沒有被動過、孔位裡有沒有不該有的反光。床頭那組優先看。"),
        AntiSpyCheckItem(id: "clock", title: "時鐘、鬧鐘、裝飾畫", level: 3,
                         detail: "掛在床正對面的最有動機。看指針中央、畫框邊緣有沒有鏡頭圓點。"),
        AntiSpyCheckItem(id: "ac", title: "冷氣出風口", level: 2,
                         detail: "葉片縫隙正對床的位置。拿手電筒斜照看有沒有玻璃反光。"),
        AntiSpyCheckItem(id: "lamp", title: "床頭燈、立燈", level: 2,
                         detail: "燈罩內側、燈座接縫。燈泡附近的暗角最容易藏。"),
        AntiSpyCheckItem(id: "mirror", title: "鏡子（尤其浴室）", level: 2,
                         detail: "指甲貼鏡面測試只當參考、不能當結論。真正要看的是：鏡面與牆的厚度、邊緣有沒有縫、螺絲是不是新鎖的。"),
        AntiSpyCheckItem(id: "shower", title: "浴室掛勾、蓮蓬頭座", level: 3,
                         detail: "浴室是最高風險區。掛勾孔、沐浴乳架、天花板角落都看一遍。"),
        AntiSpyCheckItem(id: "router", title: "路由器、空氣清淨機", level: 1,
                         detail: "這類設備本身就連網。看機身有沒有多出來的小孔，型號是否對得上。"),
        AntiSpyCheckItem(id: "corner", title: "天花板四角與窗簾盒", level: 2,
                         detail: "抬頭看，很多人只掃視線高度。這些位置的設備通常正對整張床。"),
        AntiSpyCheckItem(id: "door", title: "門鎖、房卡感應器", level: 1,
                         detail: "看外殼有沒有被撬過、螺絲型號與其他五金是否一致。"),
        AntiSpyCheckItem(id: "manual", title: "眼睛再看一遍", level: 1,
                         detail: "手機只是輔助。關燈站五分鐘，讓眼睛適應後用肉眼掃一次——很多鏡頭在暗處會有一點微弱的反光。")
    ]
}

// MARK: - 主畫面

struct AntiSpyView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = AntiSpyEngine()

    @State private var mode: AntiSpyMode = .infrared
    @State private var sensitivity: AntiSpySensitivity = .standard
    @State private var showGuide = true
    @State private var previewItem: EvidenceItem?
    @State private var checks: Set<String> = []

    private var badge: String {
        switch engine.phase {
        case .idle:     return "READY"
        case .finished: return "DONE"
        default:        return "SCAN"
        }
    }

    var body: some View {
        TTScreen(title: "防偷拍掃描",
                 subtitle: "COUNTER-SURVEILLANCE",
                 badge: badge,
                 badgeOn: engine.isScanning,
                 accent: TT.rose) {
            boundaryCard
            modeBlock
            viewfinder
            controlBlock
            evidenceBlock
            checklistBlock
            footnote
        }
        .onAppear {
            engine.mode = mode
            engine.sensitivity = sensitivity
            engine.prepare()
        }
        .onDisappear { engine.stop() }
        .onChange(of: mode) { v in engine.mode = v }
        .onChange(of: sensitivity) { v in engine.sensitivity = v }
        .fullScreenCover(item: $previewItem) { item in
            EvidenceDetailView(item: item) { previewItem = nil }
        }
    }

    // MARK: 邊界說明

    private var boundaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TT.amber)
                Text("先把話說清楚")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showGuide.toggle() }
                } label: {
                    Image(systemName: showGuide ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if showGuide {
                VStack(alignment: .leading, spacing: 7) {
                    bullet("抓得到的才報",
                           "App 只會列出「持續出現在同一位置、而且只在增感下才冒出來」的光點，並附上當下拍到的實際畫面給你核對。")
                    bullet("抓不到的不硬猜",
                           "手機鏡頭沒有紅外發射器，鏡頭藏在玻璃後面、或完全不通電的設備，這支程式看不出來。")
                    bullet("不做「安全」保證",
                           "掃完沒亮點不等於房間沒問題。真正的保險是下面那份逐項清單，用手和眼睛去看。")
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TT.amber.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TT.amber.opacity(0.22), lineWidth: 1)
        )
    }

    private func bullet(_ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(TT.amber.opacity(0.7))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 模式

    private var modeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionTitle(text: "掃描模式", accent: TT.rose)

            HStack(spacing: 9) {
                ForEach(AntiSpyMode.allCases) { m in
                    Button {
                        guard !engine.isScanning else { return }
                        mode = m
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: m.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(m.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(mode == m ? TT.ink : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(mode == m
                                      ? AnyShapeStyle(LinearGradient(colors: [TT.rose, TT.violet],
                                                                     startPoint: .topLeading,
                                                                     endPoint: .bottomTrailing))
                                      : AnyShapeStyle(Color.white.opacity(0.045)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(mode == m ? Color.clear : TT.rose.opacity(0.16),
                                              lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isScanning)
                }
            }

            Text(mode.summary)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(mode.steps.enumerated()), id: \.offset) { idx, s in
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(idx + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(TT.rose)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(TT.rose.opacity(0.14)))
                        Text(s)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.36))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 取景窗

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.6))

            if !engine.cameraFailed {
                CameraPreview(session: engine.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if engine.cameraFailed {
                VStack(spacing: 9) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(engine.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            // 四角框
            cornerMarks

            if engine.isScanning {
                TTSweep(accent: mode == .reflection ? TT.amber : TT.rose)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if engine.roomTooBright && mode == .infrared {
                VStack {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 9))
                        Text("房間還不夠暗，紅外模式會失準")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(TT.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(.top, 12)
                    Spacer()
                }
            }

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.cameraFailed ? TT.rose : (engine.isScanning ? TT.rose : TT.mint))
                        .frame(width: 5, height: 5)
                    Text(engine.statusText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if engine.isScanning {
                        Text(String(format: "%.0f%%", engine.progress * 100))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(TT.rose)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(12)
            }
        }
        .frame(height: 320)
    }

    private var cornerMarks: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let color = TT.rose.opacity(0.55)
            ZStack {
                cornerMark(x: 26, y: 26, sx: 1, sy: 1, color: color)
                cornerMark(x: w - 26, y: 26, sx: -1, sy: 1, color: color)
                cornerMark(x: 26, y: h - 26, sx: 1, sy: -1, color: color)
                cornerMark(x: w - 26, y: h - 26, sx: -1, sy: -1, color: color)
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerMark(x: CGFloat, y: CGFloat,
                            sx: CGFloat, sy: CGFloat,
                            color: Color) -> some View {
        let len: CGFloat = 22
        return ZStack {
            Rectangle().fill(color)
                .frame(width: len, height: 1.6)
                .position(x: x + sx * len / 2, y: y)
            Rectangle().fill(color)
                .frame(width: 1.6, height: len)
                .position(x: x, y: y + sy * len / 2)
        }
    }

    // MARK: 控制

    private var controlBlock: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(AntiSpySensitivity.allCases) { s in
                    Button {
                        guard !engine.isScanning else { return }
                        sensitivity = s
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(s.rawValue)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(sensitivity == s ? TT.ink : Color.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                Capsule().fill(sensitivity == s ? TT.rose.opacity(0.9)
                                                                : Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isScanning)
                }
            }

            HStack(spacing: 6) {
                Text("靈敏度")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                Text(sensitivity.note)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.22))
                Spacer(minLength: 0)
            }

            if engine.isScanning {
                TTMeterBar(ratio: engine.signal, accent: TT.rose, height: 5)
                HStack {
                    Text("畫面訊號")
                        .font(.system(size: 9.5))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.28))
                    Spacer()
                    Text("\(engine.liveCount) 個候選")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }

            if !engine.torchAvailable && mode == .reflection {
                Text("這台裝置沒有可用的閃光燈，反光掃描無法使用。請改用紅外掃描。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TT.amber.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TTButton(title: buttonTitle,
                     icon: engine.isScanning ? "hourglass" : "viewfinder",
                     accent: TT.rose,
                     enabled: !engine.cameraFailed
                        && !engine.isScanning
                        && !(mode == .reflection && !engine.torchAvailable)) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if engine.phase == .finished { engine.reset() }
                engine.startScan()
            }

            if engine.phase == .finished {
                Text(engine.statusText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var buttonTitle: String {
        switch engine.phase {
        case .idle:     return "開始掃描"
        case .finished: return "重新掃描"
        default:        return "掃描中…"
        }
    }

    // MARK: 證據

    private var evidenceBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionTitle(text: "掃描記錄", accent: TT.rose)

            if engine.evidence.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: engine.phase == .finished ? "checkmark.seal" : "viewfinder")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(engine.phase == .finished ? TT.mint.opacity(0.8)
                                                                   : Color.white.opacity(0.2))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.phase == .finished ? "本次沒有記錄到可疑光源" : "還沒有掃描記錄")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(engine.phase == .finished
                             ? "這不代表房間沒問題，請照下面清單用眼睛再確認一次。"
                             : "掃描時把可疑的角落慢慢掃過一次，程式會自動存下有疑點的那一格畫面。")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 11) {
                        ForEach(engine.evidence) { item in
                            Button {
                                previewItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack {
                                        Image(uiImage: item.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 132, height: 96)
                                            .clipped()
                                        boxOverlay(item, size: CGSize(width: 132, height: 96))
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    HStack(spacing: 5) {
                                        Circle().fill(item.level.color).frame(width: 5, height: 5)
                                        Text(item.level.rawValue)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(item.level.color)
                                        Text(relative(item.date))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.white.opacity(0.28))
                                    }
                                }
                                .frame(width: 132, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text("點開可以看原圖與標記位置。這些只是「光學現象」，是不是真的鏡頭，要靠近用眼睛確認看到實體才成立。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func boxOverlay(_ item: EvidenceItem, size: CGSize) -> some View {
        ZStack {
            ForEach(item.boxes) { b in
                let side = max(CGFloat(b.r) * min(size.width, size.height), 14)
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(item.level.color, lineWidth: 1.6)
                    .frame(width: side, height: side)
                    .position(x: CGFloat(b.cx) * size.width,
                              y: CGFloat(b.cy) * size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "\(max(1, s)) 秒前" }
        return "\(s / 60) 分鐘前"
    }

    // MARK: 清單

    private var checklistBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TTSectionTitle(text: "逐項檢查", accent: TT.mint)
                Spacer(minLength: 0)
                Text("\(checks.count)/\(AntiSpyCheckItem.all.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TT.mint.opacity(0.65))
            }

            Text("這份清單才是主力。掃描只是幫你縮小範圍，眼睛跟手才是最後的判斷。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 0) {
                ForEach(Array(AntiSpyCheckItem.all.enumerated()), id: \.element.id) { idx, item in
                    checkRow(item)
                    if idx < AntiSpyCheckItem.all.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                            .padding(.leading, 40)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )

            if checks.count == AntiSpyCheckItem.all.count {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(TT.mint)
                    Text("全部看過了。離開前把可疑的那幾處拍下來存證。")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 2)
            }
        }
    }

    private func checkRow(_ item: AntiSpyCheckItem) -> some View {
        Button {
            if checks.contains(item.id) { checks.remove(item.id) }
            else { checks.insert(item.id) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(checks.contains(item.id) ? TT.mint : Color.white.opacity(0.2),
                                      lineWidth: 1.4)
                        .frame(width: 19, height: 19)
                    if checks.contains(item.id) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TT.mint)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(checks.contains(item.id) ? .white.opacity(0.4)
                                                                      : .white.opacity(0.86))
                        if item.level >= 3 {
                            Text("高風險")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(TT.rose)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(TT.rose.opacity(0.12)))
                        }
                    }
                    Text(item.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("手機沒有紅外發射器，所以「打紅外光看反射」這招做不了——那是專業偵測器的活。這裡做的是相反方向：抓設備自己發出的紅外光。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.24))
                .fixedSize(horizontal: false, vertical: true)
            Text("所有畫面都在本機即時分析，不儲存、不上傳。掃描記錄只留在這次畫面裡，離開就沒了。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.24))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

// MARK: - 證據大圖

struct EvidenceDetailView: View {
    let item: EvidenceItem
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("掃描記錄")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Circle().fill(item.level.color).frame(width: 5, height: 5)
                            Text(item.level.rawValue)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(item.level.color)
                            Text("· \(item.mode.rawValue)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)

                GeometryReader { geo in
                    let fitted = fitRect(imageSize: item.image.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: item.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        ForEach(item.boxes) { b in
                            let side = max(CGFloat(b.r) * min(fitted.width, fitted.height) * 2.2, 20)
                            let px = fitted.minX + CGFloat(b.cx) * fitted.width
                            let py = fitted.minY + CGFloat(b.cy) * fitted.height
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(item.level.color, lineWidth: 2)
                                    .frame(width: side, height: side)
                                    .shadow(color: item.level.color.opacity(0.7), radius: 6)
                                Text("可疑光源")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(TT.ink)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(item.level.color))
                                    .offset(y: -side / 2 - 12)
                            }
                            .position(x: px, y: py)
                        }
                    }
                }
                .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("這是程式當下截到的原始畫面，框起來的地方就是它偵測到的持續亮點。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("請照這個位置靠近用眼睛看：是待機指示燈、玻璃反光，還是真的有鏡頭。程式不會替你判定，也不該替你判定。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2,
                      width: w, height: h)
    }
}
