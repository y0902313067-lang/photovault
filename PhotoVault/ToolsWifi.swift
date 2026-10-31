import SwiftUI
import UIKit
import Foundation
import Network
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import CoreLocation
import UserNotifications

// MARK: - 快照

struct WifiSnapshot {
    var ssid: String? = nil
    var bssid: String? = nil
    var secure: Bool? = nil
    var ip: String? = nil
    var checkedAt: Date? = nil
}

/// 連線品質：對外連通、是否需要先登入（Captive Portal）、往返延遲
enum PortalState {
    case unknown      // 還沒測
    case ok           // 連通正常
    case portal       // 需要先登入的公共網路（飯店／機場／咖啡廳）
    case offline      // 連不出去
}

// MARK: - 模型

final class WifiModel: ObservableObject {
    @Published var snap = WifiSnapshot()
    @Published var scanning = false
    @Published var notifOn = UserDefaults.standard.bool(forKey: "md.wifi.notify")
    @Published var toast: String? = nil
    @Published var locationAllowed = false
    @Published var onWifi = false
    @Published var latencyMs: Int? = nil
    @Published var portal: PortalState = .unknown
    @Published var probeRunning = false

    private var notifiedSSID: String? = nil
    private var locManager: CLLocationManager?
    private let pathMonitor = NWPathMonitor()

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.onWifi = (path.status == .satisfied && path.usesInterfaceType(.wifi))
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "md.wifi.path"))
    }

    deinit { pathMonitor.cancel() }

    var borderColor: Color {
        guard let secure = snap.secure else { return TT.amber }
        return secure ? TT.mint : TT.rose
    }

    var stateText: String {
        if snap.ssid == nil {
            return onWifi ? "已連線，但讀不到名稱（需定位權限）" : "未連上 Wi-Fi"
        }
        guard let secure = snap.secure else { return "加密狀態未知，可手動標記" }
        return secure ? "已加密（需密碼）" : "開放網路（免密碼）"
    }

    var networkTypeText: String { onWifi ? "Wi-Fi" : "行動網路" }

    var latencyText: String {
        guard let ms = latencyMs else { return "—" }
        return "\(ms) ms"
    }

    var portalText: String {
        switch portal {
        case .unknown: return "—"
        case .ok:      return "連線正常"
        case .portal:  return "需要先登入（公共網路）"
        case .offline: return "連不出去"
        }
    }

    /// 沒連 Wi-Fi 或讀不到名稱時，一鍵跳到系統設定
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 系統沒給加密狀態時，讓使用者自己標一次，之後這台機器就記住了
    func mark(_ secure: Bool) {
        guard let ssid = snap.ssid else { return }
        var dict = UserDefaults.standard.dictionary(forKey: "md.wifi.manual") as? [String: Bool] ?? [:]
        dict[ssid] = secure
        UserDefaults.standard.set(dict, forKey: "md.wifi.manual")
        snap.secure = secure
        evaluateNotification()
    }

    private func applyManualMark() {
        guard let ssid = snap.ssid else { return }
        if let dict = UserDefaults.standard.dictionary(forKey: "md.wifi.manual") as? [String: Bool],
           let saved = dict[ssid] {
            snap.secure = saved
        }
    }

    func refreshLocationState() {
        let status = CLLocationManager().authorizationStatus
        locationAllowed = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }

    func requestLocation() {
        let m = CLLocationManager()
        locManager = m
        m.requestWhenInUseAuthorization()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.refreshLocationState()
            self.refresh()
        }
    }

    func refresh() {
        scanning = true
        refreshLocationState()
        fetchSnapshot { snap in
            self.snap = snap
            self.applyManualMark()
            self.scanning = false
            self.evaluateNotification()
        }
        probeConnectivity()
    }

    /// 探一下這個網路通不通、要不要先登入、往返多久
    func probeConnectivity() {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        probeRunning = true
        let t0 = Date()

        URLSession.shared.dataTask(with: req) { data, _, err in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async {
                self.probeRunning = false
                self.latencyMs = ms
                if err != nil {
                    self.portal = .offline
                } else if body.contains("Success") {
                    self.portal = .ok
                } else {
                    self.portal = .portal
                }
            }
        }.resume()
    }

    private func fetchSnapshot(_ done: @escaping (WifiSnapshot) -> Void) {
        var s = WifiSnapshot()
        s.ip = WifiModel.localWiFiAddress()

        guard #available(iOS 14.0, *) else {
            s.checkedAt = Date()
            DispatchQueue.main.async { done(s) }
            return
        }

        NEHotspotNetwork.fetchCurrent { net in
            if let net = net {
                s.ssid = net.ssid
                s.bssid = net.bssid
                s.secure = net.isSecure
            }
            if s.ssid == nil, let interfaces = CNCopySupportedInterfaces() as? [String] {
                for itf in interfaces {
                    if let info = CNCopyCurrentNetworkInfo(itf as CFString) as? [String: Any] {
                        s.ssid = info[kCNNetworkInfoKeySSID as String] as? String
                        s.bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
                        break
                    }
                }
            }
            s.checkedAt = Date()
            DispatchQueue.main.async { done(s) }
        }
    }

    func setNotif(_ on: Bool) {
        notifOn = on
        UserDefaults.standard.set(on, forKey: "md.wifi.notify")
        if on {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            notifiedSSID = nil
            evaluateNotification()
        }
    }

    private func evaluateNotification() {
        guard notifOn, let ssid = snap.ssid, snap.secure == false else { return }
        guard notifiedSSID != ssid else { return }
        notifiedSSID = ssid

        let content = UNMutableNotificationContent()
        content.title = "偵測到免密碼 Wi-Fi"
        content.body = "「\(ssid)」是開放網路，任何人不用密碼就能連上，傳資料要小心。"
        content.sound = .default

        let req = UNNotificationRequest(identifier: "md.wifi.open.\(UUID().uuidString)",
                                        content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)

        toast = "已發出提醒：\(ssid)"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            self.toast = nil
        }
    }

    static func localWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }
}

// MARK: - 頁面

struct WifiCheckView: View {
    @StateObject private var model = WifiModel()
    @Environment(\.scenePhase) private var phase
    @State private var timerOn = false

    var body: some View {
        TTScreen(title: "Wi-Fi 安全檢測",
                 subtitle: "WI-FI SECURITY",
                 badge: model.snap.secure == false ? "OPEN" : (model.snap.secure == true ? "SECURE" : nil),
                 badgeOn: model.snap.secure == false,
                 accent: TT.rose) {

            currentCard

            if model.snap.ssid == nil {
                wifiGuide
            }

            connectionCard

            notifyCard

            detailsCard

            TTButton(title: model.scanning ? "檢測中…" : "重新檢測",
                     icon: "arrow.clockwise",
                     accent: TT.rose,
                     enabled: !model.scanning) {
                model.refresh()
            }

            if !model.locationAllowed {
                locationHint
            }

            limitsCard
        }
        .onAppear {
            model.refresh()
            timerOn = true
            loopCheck()
        }
        .onDisappear { timerOn = false }
        .onChange(of: phase) { newPhase in
            if newPhase == .active { model.refresh() }
        }
    }

    /// 前台每 30 秒自動巡一次（背景不能持續掃，iOS 不允許常駐）
    private func loopCheck() {
        Task {
            while timerOn {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                if !timerOn { break }
                model.refresh()
            }
        }
    }

    // MARK: 目前連線

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(model.borderColor.opacity(0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: model.snap.secure == false ? "wifi.exclamationmark" : "wifi")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(model.borderColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.snap.ssid ?? (model.onWifi ? "已連上 Wi-Fi" : "未連上 Wi-Fi"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.borderColor)
                            .frame(width: 6, height: 6)
                        Text(model.stateText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(model.borderColor.opacity(0.95))
                    }
                }
                Spacer(minLength: 0)
            }

            if model.snap.secure == false {
                Text("這個網路沒有密碼，連上的人都能看到同一個網段，別在上面登入網銀或輸入重要密碼。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(TT.rose.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.snap.ssid == nil {
                Text(model.onWifi
                     ? "已連上 Wi-Fi，但 iOS 需要「定位」權限才肯把網路名稱給 App。下面點一下開啟就可以。"
                     : "手機目前沒有連 Wi-Fi（可能正在用行動網路）。這一頁只檢測你當下連著的那一個網路，先連上 Wi-Fi 再回來看。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(TT.amber.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.snap.secure == nil && model.snap.ssid != nil {
                HStack(spacing: 9) {
                    Text("這個網路要密碼嗎？")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer(minLength: 4)
                    Button { model.mark(true) } label: {
                        Text("要密碼")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TT.mint)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(TT.mint.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    Button { model.mark(false) } label: {
                        Text("免密碼")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TT.rose)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(TT.rose.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 11))
                    .foregroundStyle(TT.mint.opacity(0.9))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(model.borderColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(model.borderColor.opacity(0.55), lineWidth: 1.4)
        )
        .shadow(color: model.borderColor.opacity(0.18), radius: 18, y: 8)
    }

    // MARK: 未連線引導

    private var wifiGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TT.amber)
                Text(model.onWifi ? "讀不到網路名稱" : "請先連上 Wi-Fi")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            Text(model.onWifi
                 ? "Wi-Fi 已經連上，但系統還沒把名稱給 App。多半是定位權限沒開，去設定裡打開就好。"
                 : "這一頁測的是你目前連著的那個網路。先連上 Wi-Fi 再回來，就會顯示名稱、加密方式跟連線品質。")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.openSystemSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.system(size: 12, weight: .semibold))
                    Text("前往設定")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(TT.amber)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TT.amber.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(TT.amber.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TT.amber.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TT.amber.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: 連線品質

    private var connectionCard: some View {
        TTPanel(accent: TT.mint) {
            VStack(alignment: .leading, spacing: 12) {
                TTSectionTitle(text: "連線品質", accent: TT.mint)

                HStack(spacing: 9) {
                    metric("類型", model.networkTypeText, TT.mint)
                    metric("延遲", model.probeRunning ? "測量中…" : model.latencyText, latencyColor)
                    metric("連通", model.portalText, portalColor)
                }

                portalHint
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var latencyColor: Color {
        guard let ms = model.latencyMs else { return .white.opacity(0.5) }
        if ms < 100 { return TT.mint }
        if ms < 300 { return TT.amber }
        return TT.rose
    }

    private var portalColor: Color {
        switch model.portal {
        case .ok:      return TT.mint
        case .portal:  return TT.amber
        case .offline: return TT.rose
        case .unknown: return .white.opacity(0.5)
        }
    }

    @ViewBuilder
    private var portalHint: some View {
        switch model.portal {
        case .portal:
            hintText("這個網路還沒放行。連上後通常要先開瀏覽器登入或勾同意（飯店、機場、咖啡廳常見），登入前別輸入重要的密碼。", TT.amber)
        case .offline:
            hintText("連不出去。路由器可能沒接到網路，或是訊號太弱，換個位置或重開 Wi-Fi 再測。", TT.rose)
        case .ok:
            if model.snap.secure == false {
                hintText("連線正常，但這是開放網路。到「設定 → Wi-Fi → 這個網路」把「自動加入」關掉，免得手機自動連上同名假熱點。", TT.rose)
            }
        case .unknown:
            EmptyView()
        }
    }

    private func hintText(_ text: String, _ accent: Color) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(accent.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 通知

    private var notifyCard: some View {
        TTPanel(accent: TT.teal) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { model.notifOn },
                                     set: { model.setNotif($0) })) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TT.teal)
                            Text("免密碼 Wi-Fi 通知")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        Text("偵測到目前連的網路不用密碼時，發一則通知提醒你")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: TT.teal))

                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 9))
                    Text("App 開著時每 30 秒自動巡一次；切到背景後系統不允許常駐監測")
                        .font(.system(size: 10))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white.opacity(0.28))
            }
        }
    }

    // MARK: 詳細資料

    private var detailsCard: some View {
        TTPanel(accent: TT.blue) {
            VStack(spacing: 0) {
                TTKeyRow(key: "網路名稱", value: model.snap.ssid ?? "—", accent: TT.blue)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "加密狀態",
                         value: model.snap.secure == nil ? "—" : (model.snap.secure! ? "已加密" : "開放"),
                         accent: TT.blue)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "路由器 BSSID", value: mask(model.snap.bssid), accent: TT.blue, mono: true)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "本機 IP", value: model.snap.ip ?? "—", accent: TT.blue, mono: true)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "網路類型", value: model.networkTypeText, accent: TT.blue)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "連通狀態", value: model.portalText, accent: TT.blue)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "往返延遲", value: model.latencyText, accent: TT.blue, mono: true)
                Divider().background(Color.white.opacity(0.06))
                TTKeyRow(key: "最後檢測", value: timeText, accent: TT.blue)
            }
        }
    }

    private func mask(_ bssid: String?) -> String {
        guard let b = bssid, b.count > 8 else { return bssid ?? "—" }
        return String(b.prefix(8)) + ":••:••:••"
    }

    private var timeText: String {
        guard let t = model.snap.checkedAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: t)
    }

    // MARK: 定位權限

    private var locationHint: some View {
        Button {
            model.requestLocation()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TT.amber)
                Text("開啟定位權限，才能讀到 Wi-Fi 名稱")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TT.amber.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TT.amber.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 限制說明

    private var limitsCard: some View {
        TTPanel(accent: TT.violet) {
            VStack(alignment: .leading, spacing: 10) {
                TTSectionTitle(text: "這個頁面測什麼", accent: TT.violet)
                Text("只測你目前連著的那一個網路：名稱、有沒有加密、連不連得出去、要不要先登入、往返延遲。\n\n兩件 iOS 不給的事先講清楚，免得誤會：\n• 不能列出附近有哪些熱點。系統沒有這個介面，任何 App 都一樣。\n• 不能細分 WPA2 / WPA3 / WEP。系統只回報「有沒有加密」；顯示「未知」時，可以用卡片上的「要密碼／免密碼」手動標記一次，這台手機之後會記住。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
