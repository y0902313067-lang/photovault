import SwiftUI
import UIKit
import Foundation
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

// MARK: - 模型

final class WifiModel: ObservableObject {
    @Published var snap = WifiSnapshot()
    @Published var scanning = false
    @Published var notifOn = UserDefaults.standard.bool(forKey: "md.wifi.notify")
    @Published var toast: String? = nil
    @Published var locationAllowed = false

    private var notifiedSSID: String? = nil
    private var locManager: CLLocationManager?

    var borderColor: Color {
        guard let secure = snap.secure else { return TT.amber }
        return secure ? TT.mint : TT.rose
    }

    var stateText: String {
        guard snap.ssid != nil else { return "讀不到網路名稱" }
        guard let secure = snap.secure else { return "加密狀態未知，可手動標記" }
        return secure ? "已加密（需密碼）" : "開放網路（免密碼）"
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
        TTScreen(title: "蹭網檢測",
                 subtitle: "WIFI CHECKER",
                 badge: model.snap.secure == false ? "OPEN" : (model.snap.secure == true ? "SECURE" : nil),
                 badgeOn: model.snap.secure == false,
                 accent: TT.rose) {

            currentCard

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
                    Text(model.snap.ssid ?? "未連上 Wi-Fi")
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
                Text("讀不到網路名稱：iOS 需要「定位」權限才肯把 Wi-Fi 名稱給 App。下面點一下開啟就可以。")
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
                TTSectionTitle(text: "為什麼沒有周邊熱點列表", accent: TT.violet)
                Text("iOS 不開放掃描周邊 Wi-Fi 的介面，任何 App 都拿不到「附近有哪些熱點」。這一頁能拿到的是你目前連著的這一個：名稱、路由器編號與本機 IP。\n\n加密狀態由系統決定要不要給；遇到顯示「未知」時，卡片上可以用「要密碼／免密碼」手動標記一次，這台手機之後就會記住，通知也會照這個標記判斷。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
