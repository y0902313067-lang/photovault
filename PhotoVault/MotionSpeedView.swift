import SwiftUI
import CoreLocation
import MapKit
import UIKit

// MARK: - 單位

enum SpeedUnit: String, CaseIterable, Identifiable, Codable {
    case kmh, mph, ms, knot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kmh:  return "公里"
        case .mph:  return "英里"
        case .ms:   return "公尺"
        case .knot: return "節"
        }
    }

    var speedShort: String {
        switch self {
        case .kmh:  return "km/h"
        case .mph:  return "mph"
        case .ms:   return "m/s"
        case .knot: return "kn"
        }
    }

    /// 每秒公尺 → 這個單位
    func value(fromMPS mps: Double) -> Double {
        switch self {
        case .kmh:  return mps * 3.6
        case .mph:  return mps * 2.2369362920544
        case .ms:   return mps
        case .knot: return mps * 1.9438444924406
        }
    }

    /// 公尺 → 這個單位的距離
    func distance(fromMeters m: Double) -> Double {
        switch self {
        case .kmh:  return m / 1000
        case .ms:   return m
        case .mph:  return m / 1609.344
        case .knot: return m / 1852
        }
    }

    var distanceShort: String {
        switch self {
        case .kmh:  return "km"
        case .ms:   return "m"
        case .mph:  return "mi"
        case .knot: return "nmi"
        }
    }
}

// MARK: - 一次紀錄

struct SpeedRun: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var duration: Double        // 秒
    var distance: Double        // 公尺
    var maxSpeed: Double        // m/s
    var avgSpeed: Double        // m/s
    var ascent: Double          // 公尺
    var descent: Double         // 公尺
    var unitRaw: String

    var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }
}

// MARK: - 模型

final class MotionSpeedModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var running = false
    @Published var paused = false
    @Published var elapsed: Double = 0
    @Published var distance: Double = 0
    @Published var current: Double = 0          // m/s
    @Published var maxSpeed: Double = 0         // m/s
    @Published var altitude: Double = 0
    @Published var ascent: Double = 0
    @Published var descent: Double = 0
    @Published var accuracy: Double = -1
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var denied = false
    @Published var gpsReady = false
    @Published var stationary = false
    @Published var history: [SpeedRun] = []
    @Published var unit: SpeedUnit = .kmh {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: "pv_speed_unit") }
    }

    /// 行車預警引擎（由畫面注入，跟本頁共用同一份定位）
    weak var alertEngine: DriveAlertEngine?

    private let lm = CLLocationManager()
    private var timer: Timer?
    private var segStart: Date?
    private var accumulated: Double = 0
    private var lastPoint: CLLocation?
    private var lastAlt: Double?
    private var hasFix = false
    private var samples: [CLLocation] = []
    private var stillTicks = 0
    private var lastFixAt: Date?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = .fitness
        if let raw = UserDefaults.standard.string(forKey: "pv_speed_unit"),
           let u = SpeedUnit(rawValue: raw) {
            unit = u
        }
        history = Self.loadHistory()
    }

    // MARK: 權限 / 生命週期

    func startUpdates() {
        switch lm.authorizationStatus {
        case .notDetermined:
            lm.requestWhenInUseAuthorization()
        case .denied, .restricted:
            denied = true
        default:
            denied = false
            lm.startUpdatingLocation()
        }
    }

    func stopUpdates() {
        lm.stopUpdatingLocation()
        stopTimer()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.startUpdatingLocation()
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    // MARK: 計時

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, !self.paused else { return }
            self.elapsed = self.rawElapsed
            self.checkStaleFix()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 車停下來之後系統幾乎不再回報位置，靠這個兜底把速度歸零
    private func checkStaleFix() {
        guard running, !paused, let t = lastFixAt else { return }
        guard Date().timeIntervalSince(t) > 2.2 else { return }
        if current != 0 { current = 0 }
        if !stationary { stationary = true }
    }

    private var rawElapsed: Double {
        accumulated + (segStart.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: 控制

    func start() {
        guard !running else { return }
        reset(false)
        running = true
        paused = false
        segStart = Date()
        startTimer()
        startUpdates()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func pause() {
        guard running, !paused else { return }
        paused = true
        accumulated = rawElapsed
        segStart = nil
        elapsed = accumulated
        current = 0
        stationary = false
        samples = []
        stillTicks = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func resume() {
        guard running, paused else { return }
        paused = false
        segStart = Date()
        startTimer()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func stop() {
        guard running else { return }
        accumulated = rawElapsed
        segStart = nil
        elapsed = accumulated
        running = false
        paused = false
        current = 0
        stationary = false
        stopTimer()
        if elapsed >= 3, distance >= 10 {
            let run = SpeedRun(date: Date(),
                               duration: elapsed,
                               distance: distance,
                               maxSpeed: maxSpeed,
                               avgSpeed: distance / max(elapsed, 0.001),
                               ascent: ascent,
                               descent: descent,
                               unitRaw: unit.rawValue)
            history.insert(run, at: 0)
            history = Array(history.prefix(30))
            Self.saveHistory(history)
        }
    }

    func reset(_ manual: Bool = true) {
        accumulated = 0
        segStart = nil
        elapsed = 0
        distance = 0
        current = 0
        maxSpeed = 0
        ascent = 0
        descent = 0
        route = []
        lastPoint = nil
        lastAlt = nil
        samples = []
        stillTicks = 0
        stationary = false
        if manual {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func clearHistory() {
        history = []
        Self.saveHistory(history)
    }

    // MARK: 定位回呼

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // 太舊的點（快取位置）不能拿來算瞬時速度
        guard loc.horizontalAccuracy > 0, loc.timestamp.timeIntervalSinceNow > -6 else { return }

        hasFix = true
        gpsReady = true
        lastFixAt = Date()
        accuracy = loc.horizontalAccuracy
        if loc.verticalAccuracy > 0 { altitude = loc.altitude }

        // 保留最近 3.5 秒的樣本，用「實際位移」推算真實速度
        samples.append(loc)
        samples.removeAll { loc.timestamp.timeIntervalSince($0.timestamp) > 3.5 }

        var span: Double = 0
        var moved: Double = 0
        var moveSpeed: Double = -1
        if let first = samples.first, samples.count >= 2 {
            span = loc.timestamp.timeIntervalSince(first.timestamp)
            if span > 0.8 {
                moved = loc.distance(from: first)
                moveSpeed = moved / span
            }
        }

        // 瞬時速度：GPS 給負值代表靜止；speedAccuracy 太差代表這個值不可信
        var raw = max(loc.speed, 0)
        if loc.speedAccuracy > 2.5, moveSpeed >= 0 { raw = moveSpeed }

        // 停車後 GPS 瞬時速度會殘留好幾秒，所以用位移當主判據：
        // 短窗幾乎沒動（<0.5m/1.2s）或長窗明顯沒動（<2.2m/2.8s）都算停下來
        let stillFast = span >= 1.2 && moved < 0.5 && raw < 2.5
        let stillSteady = span >= 2.8 && moved < 2.2
        let stillNow = stillFast || stillSteady
        stillTicks = stillNow ? stillTicks + 1 : 0

        if paused {
            current = 0
            stationary = false
            if lastPoint == nil { lastPoint = loc }
            return
        }

        if stillTicks >= 1 {
            // 已靜止：速度直接歸零，也不刷新最高時速
            stationary = true
            current = 0
        } else {
            stationary = false
            let blended = moveSpeed >= 0 ? (raw * 0.6 + moveSpeed * 0.4) : raw
            current = current * 0.3 + blended * 0.7
            if current < 0.4 { current = 0 }
            // 抗噪：單次跳點不計入峰值（用位移速度壓一下離譜數值）
            let candidate = moveSpeed >= 0 ? min(raw, moveSpeed * 1.6 + 1.5) : raw
            if candidate > maxSpeed, candidate < 130 { maxSpeed = candidate }
        }

        // 行車預警：把同一份定位餵給速限／測速照相／區間測速引擎
        alertEngine?.update(location: loc, speedMPS: max(current, 0))

        guard running, !paused, loc.horizontalAccuracy < 55 else {
            if lastPoint == nil { lastPoint = loc }
            return
        }

        if let prev = lastPoint {
            let step = loc.distance(from: prev)
            let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
            // 過濾 GPS 漂移：位移太小、跳太遠、時間沒前進都不算
            if step >= 1.2, step <= max(120, raw * max(dt, 1) * 3), dt > 0, dt < 60, !stationary {
                distance += step
                route.append(loc.coordinate)
            }
        } else {
            route.append(loc.coordinate)
        }
        lastPoint = loc

        // 海拔累計（靜止時不累加，免得抖動虛增上升下降）
        if !stationary, loc.verticalAccuracy > 0, loc.verticalAccuracy < 30 {
            if let prevAlt = lastAlt {
                let diff = loc.altitude - prevAlt
                if abs(diff) >= 1.2 {
                    if diff > 0 { ascent += diff } else { descent -= diff }
                    lastAlt = loc.altitude
                }
            } else {
                lastAlt = loc.altitude
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !hasFix { gpsReady = false }
    }

    // MARK: 顯示輔助

    var currentText: String { String(format: "%.1f", unit.value(fromMPS: current)) }
    var maxText: String { String(format: "%.1f", unit.value(fromMPS: maxSpeed)) }
    var avgSpeed: Double { elapsed > 0.5 ? distance / elapsed : 0 }
    var avgText: String { String(format: "%.1f", unit.value(fromMPS: avgSpeed)) }
    var distanceText: String {
        let d = unit.distance(fromMeters: distance)
        return d >= 100 ? String(format: "%.1f", d) : String(format: "%.2f", d)
    }

    var elapsedText: String {
        let total = Int(elapsed.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// 配速：每公里幾分鐘（距離太短不顯示）
    var paceText: String {
        guard distance > 20, elapsed > 1 else { return "—" }
        let secPerKm = elapsed / (distance / 1000)
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d'%02d\"", m, s)
    }

    var altitudeText: String { String(format: "%.0f", altitude) }
    var ascentText: String { String(format: "%.0f", ascent) }
    var descentText: String { String(format: "%.0f", descent) }

    // MARK: 歷史

    private static func loadHistory() -> [SpeedRun] {
        guard let data = UserDefaults.standard.data(forKey: "pv_speed_history"),
              let list = try? JSONDecoder().decode([SpeedRun].self, from: data) else { return [] }
        return list
    }

    private static func saveHistory(_ list: [SpeedRun]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "pv_speed_history")
        }
    }
}

// MARK: - 軌跡地圖

struct RouteMapView: UIViewRepresentable {
    var coords: [CLLocationCoordinate2D]
    var accent: UIColor

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = .dark
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let shown = context.coordinator.drawn
        guard coords.count != shown else { return }
        context.coordinator.drawn = coords.count

        let old = map.overlays
        if !old.isEmpty { map.removeOverlays(old) }

        guard coords.count >= 2 else {
            if let one = coords.first {
                map.setRegion(MKCoordinateRegion(center: one,
                                                 latitudinalMeters: 420,
                                                 longitudinalMeters: 420), animated: true)
            }
            return
        }

        let poly = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(poly)

        if coords.count % 12 == 2 || shown == 0 {
            map.setVisibleMapRect(poly.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 34, left: 34, bottom: 34, right: 34),
                                  animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(accent: accent) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var drawn = -1
        let accent: UIColor

        init(accent: UIColor) { self.accent = accent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = accent
            r.lineWidth = 4
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
    }
}

// MARK: - 畫面

struct MotionSpeedView: View {
    @StateObject private var model = MotionSpeedModel()
    @StateObject private var drive = DriveAlertEngine()

    var body: some View {
        TTScreen(title: "源隼測速",
                 subtitle: "YUAN SUN SPEED",
                 badge: model.running ? (model.paused ? "已暫停" : "記錄中") : "待機",
                 badgeOn: model.running && !model.paused,
                 accent: TT.amber) {
            if model.denied {
                permissionPanel
            } else {
                gaugeBlock
                limitBlock
                cameraAlertBlock
                intervalBlock
                unitBlock
                statsBlock
                mapBlock
                controlBlock
                historyBlock
            }
        }
        .onAppear {
            DriveData.shared.prepare {}
            DriveVoice.shared.activateSession()
            model.alertEngine = drive
            model.startUpdates()
        }
        .onDisappear {
            model.alertEngine = nil
            model.stopUpdates()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 主錶

    private var gaugeBlock: some View {
        TTPanel(accent: TT.amber) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.currentText)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(colors: [.white, TT.amber.opacity(0.92)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(model.unit.speedShort)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TT.amber.opacity(0.8))
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Circle()
                        .fill(model.gpsReady ? TT.mint : TT.rose)
                        .frame(width: 5, height: 5)
                    Text(model.gpsReady
                         ? String(format: "GPS 已定位 · 誤差 %.0f m", max(model.accuracy, 0))
                         : "正在取得 GPS 訊號…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.42))
                    if model.running, !model.paused, model.stationary {
                        Text("已靜止")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(TT.ink)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TT.mint.opacity(0.85)))
                            .transition(.opacity)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: 速限（新增）

    private var nowKmh: Double { max(model.current, 0) * 3.6 }

    private var limitBlock: some View {
        TTPanel(accent: drive.overSpeed ? TT.rose : TT.teal) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    limitSign
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(drive.limitFromInterval ? "區間測速速限" : "路段速限")
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1.4)
                                .foregroundStyle(.white.opacity(0.36))
                            Spacer(minLength: 8)
                            voiceChip
                        }
                        if drive.limit != nil {
                            Text(drive.overSpeed ? "超速中" : String(format: "現在 %.0f km/h", nowKmh))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(drive.overSpeed ? TT.rose : TT.mint)
                        } else {
                            Text(drive.dataReady ? "非限速路段" : "載入圖資…")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var voiceChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { drive.voiceOn.toggle() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: drive.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(drive.voiceOn ? "語音播報" : "已靜音")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(drive.voiceOn ? TT.ink : .white.opacity(0.6))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(drive.voiceOn ? TT.amber.opacity(0.9) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private var limitSign: some View {
        ZStack {
            Circle().fill(Color(red: 0.96, green: 0.96, blue: 0.96))
            Circle().strokeBorder(Color(red: 0.85, green: 0.15, blue: 0.19), lineWidth: 6)
            if let l = drive.limit {
                Text("\(l)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
            } else {
                Text("--")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.32))
            }
        }
        .frame(width: 66, height: 66)
        .shadow(color: (drive.overSpeed ? TT.rose : TT.teal).opacity(0.35), radius: 10)
    }

    // MARK: 測速照相預警（新增，觸發時才出現）

    private var cameraAlertBlock: some View {
        Group {
            if let c = drive.cameraAlert {
                TTPanel(accent: c.near ? TT.rose : TT.amber, padding: 13) {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.near ? TT.rose : TT.amber)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle().fill((c.near ? TT.rose : TT.amber).opacity(0.14))
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.near ? "測速照相就在前方" : "前方測速照相")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Text(c.addr.isEmpty ? String(format: "%.0f 公尺", c.distance)
                                                : String(format: "%.0f 公尺 · %@", c.distance, c.addr))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 1) {
                            Text("\(c.limit)")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(c.near ? TT.rose : TT.amber)
                            Text("km/h")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    // MARK: 區間測速預警（新增，接近／進行中才出現）

    private var intervalBlock: some View {
        Group {
            if let run = drive.intervalLive {
                TTPanel(accent: run.over ? TT.rose : TT.violet, padding: 13) {
                    VStack(spacing: 9) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(run.over ? TT.rose : TT.violet)
                            Text("區間測速進行中")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Spacer(minLength: 0)
                            Text(run.name)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            intervalCell("限速", "\(run.limit)", "km/h",
                                         run.over ? TT.rose : TT.violet)
                            intervalCell("目前平均", String(format: "%.0f", run.avg), "km/h",
                                         run.over ? TT.rose : TT.mint)
                            intervalCell("已行駛", String(format: "%.2f", run.travelled / 1000), "km",
                                         TT.teal)
                            intervalCell("剩餘", String(format: "%.2f", run.remaining / 1000), "km",
                                         TT.blue)
                        }
                        if run.over {
                            Text("平均速度超過限速，通過終點會被開單")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(TT.rose.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if let ap = drive.intervalApproach {
                TTPanel(accent: TT.violet, padding: 13) {
                    HStack(spacing: 12) {
                        Image(systemName: "timer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TT.violet)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(TT.violet.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("前方進入區間測速")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Text(String(format: "%.0f 公尺 · %@", ap.distance, ap.name))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("限 \(ap.limit)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TT.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(TT.violet.opacity(0.9)))
                    }
                }
            }
        }
    }

    private func intervalCell(_ title: String, _ value: String, _ unit: String,
                              _ accent: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 7.5))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: 單位

    private var unitBlock: some View {
        VStack(spacing: 9) {
            TTSectionTitle(text: "速度單位", accent: TT.amber)
            HStack(spacing: 8) {
                ForEach(SpeedUnit.allCases) { u in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { model.unit = u }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 3) {
                            Text(u.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(model.unit == u ? TT.ink : .white.opacity(0.6))
                            Text(u.speedShort)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(model.unit == u ? TT.ink.opacity(0.65) : .white.opacity(0.28))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(model.unit == u ? TT.amber.opacity(0.92) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(model.unit == u ? Color.clear : TT.amber.opacity(0.16),
                                              lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 數據

    private var statsBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "本次紀錄", accent: TT.amber)
            HStack(spacing: 10) {
                TTStat(title: "用時", value: model.elapsedText, accent: TT.teal)
                TTStat(title: "移動距離", value: model.distanceText,
                       unit: model.unit.distanceShort, accent: TT.mint)
            }
            HStack(spacing: 10) {
                TTStat(title: "最高時速", value: model.maxText,
                       unit: model.unit.speedShort, accent: TT.rose)
                TTStat(title: "平均速度", value: model.avgText,
                       unit: model.unit.speedShort, accent: TT.blue)
            }
            HStack(spacing: 10) {
                TTStat(title: "配速 / 公里", value: model.paceText, accent: TT.violet)
                TTStat(title: "目前海拔", value: model.altitudeText, unit: "m", accent: TT.indigo)
            }
            HStack(spacing: 10) {
                TTStat(title: "累計上升", value: model.ascentText, unit: "m", accent: TT.lime)
                TTStat(title: "累計下降", value: model.descentText, unit: "m", accent: TT.amber)
            }
        }
    }

    // MARK: 地圖

    private var mapBlock: some View {
        VStack(spacing: 9) {
            TTSectionTitle(text: "移動軌跡", accent: TT.mint)
            RouteMapView(coords: model.route, accent: UIColor(red: 0.62, green: 0.98, blue: 0.52, alpha: 1))
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(TT.mint.opacity(0.18), lineWidth: 1)
                )
                .overlay(alignment: .bottomLeading) {
                    if model.route.count < 2 {
                        Text("開始移動後會畫出路線")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                            .padding(10)
                    }
                }
        }
    }

    // MARK: 控制

    private var controlBlock: some View {
        HStack(spacing: 10) {
            if !model.running {
                TTButton(title: "開始測速", icon: "play.fill", accent: TT.amber) {
                    model.start()
                }
            } else if model.paused {
                TTButton(title: "繼續", icon: "play.fill", accent: TT.mint) {
                    model.resume()
                }
                TTButton(title: "結束", icon: "stop.fill", accent: TT.rose) {
                    model.stop()
                }
            } else {
                TTButton(title: "暫停", icon: "pause.fill", accent: TT.teal) {
                    model.pause()
                }
                TTButton(title: "結束", icon: "stop.fill", accent: TT.rose) {
                    model.stop()
                }
            }
        }
    }

    // MARK: 歷史

    private var historyBlock: some View {
        VStack(spacing: 10) {
            HStack {
                TTSectionTitle(text: "歷史紀錄", accent: TT.violet)
                Spacer(minLength: 8)
                if !model.history.isEmpty {
                    Button {
                        withAnimation { model.clearHistory() }
                    } label: {
                        Text("清空")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.history.isEmpty {
                TTPanel(accent: TT.violet) {
                    TTEmptyHint(icon: "speedometer", text: "還沒有紀錄\n測速結束後會自動存到本機")
                }
            } else {
                ForEach(model.history) { run in
                    historyRow(run)
                }
            }
        }
    }

    private func historyRow(_ run: SpeedRun) -> some View {
        let u = run.unit
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateText(run.date))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(Self.mmss(run.duration)) · \(String(format: "%.2f", u.distance(fromMeters: run.distance))) \(u.distanceShort)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(String(format: "%.1f", u.value(fromMPS: run.maxSpeed))) \(u.speedShort)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(TT.amber.opacity(0.9))
                Text("平均 \(String(format: "%.1f", u.value(fromMPS: run.avgSpeed)))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(TT.violet.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: 權限

    private var permissionPanel: some View {
        TTPanel(accent: TT.rose) {
            VStack(spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(TT.rose.opacity(0.7))
                Text("需要定位權限")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("測速靠 GPS 計算速度與距離，到「設定 → 源隼科技 → 位置」選「使用 App 期間」即可")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("前往設定", destination: url)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TT.mint)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 格式化

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }

    static func mmss(_ t: Double) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
