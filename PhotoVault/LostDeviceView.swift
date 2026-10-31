import SwiftUI
import CoreLocation
import UIKit

// MARK: - 遺失找回：背景每小時定位一次

final class LostModeManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LostModeManager()

    @Published var alwaysAuthorized = false
    @Published var whenInUseOnly = false
    @Published var denied = false
    @Published var running = false
    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "pv_lost_enabled")
    @Published var lastSentAt: Date?
    @Published var fixOK = false
    @Published var sending = false

    /// 每小時一次
    static let interval: TimeInterval = 3600

    private let lm = CLLocationManager()
    private let geocoder = CLGeocoder()
    private weak var store: AppStore?
    private var lastSent = Date.distantPast
    private var manualRequest = false
    private var configured = false

    private override init() {
        super.init()
        let saved = UserDefaults.standard.object(forKey: "pv_lost_last") as? Double
        if let saved { lastSentAt = Date(timeIntervalSince1970: saved) }
        refreshStatus()
    }

    static var currentKey: String { PVDevice.key }

    func configure(store: AppStore) {
        self.store = store
        guard !configured else { return }
        configured = true

        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
        lm.distanceFilter = 20
        lm.pausesLocationUpdatesAutomatically = false
        lm.activityType = .otherNavigation
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = false

        refreshStatus()
        if enabled && alwaysAuthorized { start() }
    }

    func refreshStatus() {
        let s = lm.authorizationStatus
        alwaysAuthorized = (s == .authorizedAlways)
        whenInUseOnly = (s == .authorizedWhenInUse)
        denied = (s == .denied || s == .restricted)
    }

    /// 要求「永遠允許」
    func requestAlways() {
        switch lm.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            lm.requestAlwaysAuthorization()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    /// 只有「永遠允許」才能開啟；其他狀態一律不給用
    var canEnable: Bool { alwaysAuthorized }

    func setEnabled(_ on: Bool) {
        guard canEnable else { return }
        enabled = on
        UserDefaults.standard.set(on, forKey: "pv_lost_enabled")
        if on {
            start()
            sendNow()
        } else {
            stop()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func start() {
        guard alwaysAuthorized else { return }
        running = true
        lm.startUpdatingLocation()
        lm.startMonitoringSignificantLocationChanges()
    }

    func stop() {
        running = false
        lm.stopUpdatingLocation()
        lm.stopMonitoringSignificantLocationChanges()
    }

    /// 手動補一次（頁面打開、剛開啟開關時）
    func sendNow() {
        guard alwaysAuthorized else { return }
        manualRequest = true
        sending = true
        lm.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshStatus()
        if enabled && alwaysAuthorized {
            start()
        }
        if !alwaysAuthorized {
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        fixOK = true
        sending = false

        let now = Date()
        let manual = manualRequest
        manualRequest = false
        let due = manual || lastSent == .distantPast || now.timeIntervalSince(lastSent) >= Self.interval
        // 手動或剛開啟立刻送；之後嚴格一小時一次
        guard due else { return }

        lastSent = now
        lastSentAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "pv_lost_last")

        geocoder.reverseGeocodeLocation(loc) { [weak self] places, _ in
            guard let self else { return }
            let p = places?.first
            let joined = [p?.administrativeArea, p?.locality, p?.subLocality,
                          p?.thoroughfare, p?.subThoroughfare, p?.name]
                .compactMap { $0 }
                .joined(separator: " ")
            Task { @MainActor in
                self.store?.reportLocation(lat: loc.coordinate.latitude,
                                           lon: loc.coordinate.longitude,
                                           alt: loc.altitude,
                                           acc: loc.horizontalAccuracy,
                                           speed: loc.speed,
                                           course: loc.course,
                                           address: joined,
                                           place: p?.name ?? "",
                                           force: true)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        sending = false
    }
}

// MARK: - 一台裝置的最後狀態

struct LostDevice: Identifiable {
    let id: String
    let name: String
    let time: Date
    let battery: Int?
    let address: String
    let lat: Double
    let lon: Double
    let accuracy: Double

    var isThisDevice: Bool { id == LostModeManager.currentKey }
}

// MARK: - 畫面

struct LostDeviceView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var lost = LostModeManager.shared
    @State private var devices: [LostDevice] = []
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var tick = Date()
    @State private var poller: Timer?

    var body: some View {
        TTScreen(title: "遺失找回",
                 subtitle: "FIND MY DEVICE",
                 badge: lost.alwaysAuthorized ? (lost.enabled ? "守護中" : "待開啟") : "未授權",
                 badgeOn: lost.alwaysAuthorized && lost.enabled,
                 accent: TT.lime) {
            permissionBlock
            switchBlock
            if lost.alwaysAuthorized && lost.enabled {
                heartbeatBlock
            }
            devicesBlock
            tipBlock
        }
        .onAppear {
            lost.configure(store: store)
            lost.refreshStatus()
            Task { await reload() }
            poller?.invalidate()
            poller = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                Task { @MainActor in
                    tick = Date()
                    if loadedOnce { await reload() }
                }
            }
        }
        .onDisappear {
            poller?.invalidate()
            poller = nil
        }
    }

    // MARK: 權限

    private var permissionBlock: some View {
        Group {
            if lost.alwaysAuthorized {
                EmptyView()
            } else if lost.denied {
                TTPanel(accent: TT.rose) {
                    VStack(spacing: 10) {
                        Image(systemName: "location.slash")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(TT.rose.opacity(0.75))
                        Text("定位被關閉了")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("這個功能必須「永遠允許」定位才能用，請到設定裡打開")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                        Button {
                            lost.requestAlways()
                        } label: {
                            Text("前往設定")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TT.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(TT.rose.opacity(0.9))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                TTPanel(accent: TT.amber) {
                    VStack(spacing: 11) {
                        HStack(spacing: 9) {
                            Image(systemName: "exclamationmark.shield")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(TT.amber)
                            Text("需要「永遠允許」定位")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            Spacer(minLength: 0)
                        }
                        Text("手機丟了以後要還能被找到，App 就必須在你沒打開它的時候也能定位。這個功能只在「永遠允許」下可用；選「使用 App 期間」或「不允許」時，功能無法開啟。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            lost.requestAlways()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(lost.whenInUseOnly ? "改成「永遠允許」" : "允許永遠定位")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(TT.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [TT.lime, TT.mint],
                                                         startPoint: .leading, endPoint: .trailing))
                            )
                        }
                        .buttonStyle(.plain)
                        Text("iOS 的權限選單可能只給「使用 App 期間」，選了之後再進來一次，系統會再問你是否改成「永遠允許」。")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.28))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 開關

    private var switchBlock: some View {
        TTPanel(accent: TT.lime) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [TT.lime.opacity(0.9), TT.mint.opacity(0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TT.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("每小時回報一次位置")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(lost.alwaysAuthorized ? 0.92 : 0.35))
                    Text(lost.alwaysAuthorized
                         ? "背景每小時定位一次，關掉螢幕也會繼續"
                         : "需要「永遠允許」定位才能開啟")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(
                    get: { lost.enabled && lost.alwaysAuthorized },
                    set: { lost.setEnabled($0) }
                ))
                .labelsHidden()
                .tint(TT.lime)
                .disabled(!lost.alwaysAuthorized)
            }
        }
    }

    // MARK: 心跳狀態

    private var heartbeatBlock: some View {
        TTPanel(accent: TT.teal, padding: 14) {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(lostEnabledColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: lostEnabledColor.opacity(0.8), radius: 5)
                    Text(lost.running ? "背景定位運行中" : "準備中")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 4)
                    Text(nextText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                HStack(spacing: 10) {
                    TTStat(title: "上次回報", value: lastSentText, accent: TT.teal)
                    TTStat(title: "本機電量", value: batteryText, accent: TT.amber)
                }
                HStack(spacing: 6) {
                    Text("這台裝置")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(PVDevice.key)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(TT.mint.opacity(0.7))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var lostEnabledColor: Color {
        if lost.running && lost.fixOK { return TT.mint }
        if lost.running { return TT.amber }
        return .white.opacity(0.3)
    }

    private var lastSentText: String {
        guard let t = lost.lastSentAt else { return "—" }
        let mins = Int(Date().timeIntervalSince(t) / 60)
        if mins < 1 { return "剛剛" }
        if mins < 60 { return "\(mins) 分鐘前" }
        let h = mins / 60
        if h < 24 { return "\(h) 小時前" }
        return "\(h / 24) 天前"
    }

    private var nextText: String {
        guard lost.enabled, let t = lost.lastSentAt else { return "每 60 分鐘" }
        let next = t.addingTimeInterval(LostModeManager.interval)
        let mins = max(0, Int(next.timeIntervalSince(Date()) / 60))
        return "下次約 \(mins) 分後"
    }

    private var batteryText: String {
        let d = UIDevice.current
        if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
        let l = d.batteryLevel
        return l < 0 ? "—" : "\(Int((l * 100).rounded()))%"
    }

    // MARK: 裝置清單

    private var devicesBlock: some View {
        VStack(spacing: 10) {
            HStack {
                TTSectionTitle(text: "我的裝置", accent: TT.mint)
                Spacer(minLength: 8)
                Button {
                    Task { await reload() }
                } label: {
                    HStack(spacing: 5) {
                        if loading {
                            ProgressView().tint(TT.mint).scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(loading ? "讀取中" : "重新整理")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            if devices.isEmpty {
                TTPanel(accent: TT.mint) {
                    TTEmptyHint(icon: "iphone.slash",
                                text: loading ? "正在讀取位置…"
                                : "還沒有任何裝置回報過位置\n開啟上面的開關後，這台手機就會出現")
                }
            } else {
                ForEach(devices) { dev in
                    deviceRow(dev)
                }
            }
        }
    }

    private func deviceRow(_ dev: LostDevice) -> some View {
        TTPanel(accent: dev.isThisDevice ? TT.teal : TT.mint, padding: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: dev.isThisDevice ? "iphone" : "iphone.gen3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(dev.isThisDevice ? TT.teal : TT.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(dev.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                            if dev.isThisDevice {
                                Text("這台")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(TT.ink)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(TT.teal.opacity(0.9)))
                            }
                        }
                        Text("最後上線 · \(Self.ago(dev.time))")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer(minLength: 4)
                    if let b = dev.battery {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(b))
                                .font(.system(size: 10))
                            Text("\(b)%")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(b <= 20 ? TT.rose : TT.mint.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                    }
                }

                if !dev.address.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(dev.address)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 9) {
                    Text(String(format: "%.5f, %.5f", dev.lat, dev.lon))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                    Spacer(minLength: 0)
                    if let url = URL(string: String(format: "https://maps.google.com/?q=%.6f,%.6f", dev.lat, dev.lon)) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "map")
                                    .font(.system(size: 9.5))
                                Text("地圖")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(TT.mint.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(TT.mint.opacity(0.12)))
                        }
                    }
                }
            }
        }
    }

    private func batteryIcon(_ b: Int) -> String {
        if b <= 10 { return "battery.0" }
        if b <= 25 { return "battery.25" }
        if b <= 50 { return "battery.50" }
        if b <= 75 { return "battery.75" }
        return "battery.100"
    }

    // MARK: 說明

    private var tipBlock: some View {
        TTPanel(accent: TT.violet, padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(TT.violet.opacity(0.8))
                    Text("手機丟了怎麼找")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                tipLine("1", "舊手機開著這個功能，關掉螢幕也會每小時回報一次位置")
                tipLine("2", "拿另一台手機，登入同一個帳號")
                tipLine("3", "進來這一頁，上面就會列出每台裝置的最後位置、時間和電量")
            }
        }
    }

    private func tipLine(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(n)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TT.violet.opacity(0.9))
                .frame(width: 14, height: 14)
                .background(Circle().fill(TT.violet.opacity(0.15)))
            Text(t)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 資料

    private func reload() async {
        await MainActor.run { loading = true }
        let list = await store.fetchLocations()
        var seen = Set<String>()
        var out: [LostDevice] = []
        for item in list {
            let key = item.deviceKey
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(LostDevice(id: key,
                                  name: item.deviceName.isEmpty ? "未知裝置" : item.deviceName,
                                  time: item.date,
                                  battery: item.battery,
                                  address: item.address,
                                  lat: item.lat,
                                  lon: item.lon,
                                  accuracy: item.accuracy))
        }
        // 這台手機排最前面
        out.sort { a, b in
            if a.isThisDevice != b.isThisDevice { return a.isThisDevice }
            return a.time > b.time
        }
        await MainActor.run {
            devices = out
            loading = false
            loadedOnce = true
        }
    }

    static func ago(_ d: Date) -> String {
        let s = max(0, Date().timeIntervalSince(d))
        if s < 60 { return "\(Int(s)) 秒前" }
        if s < 3600 { return "\(Int(s / 60)) 分鐘前" }
        if s < 86400 { return "\(Int(s / 3600)) 小時前" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }
}
