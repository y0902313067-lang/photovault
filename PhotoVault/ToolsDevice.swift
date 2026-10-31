import SwiftUI
import UIKit
import Foundation

// MARK: - 裝置資訊模型

enum DeviceProbe {

    /// 機型標識（如 iPhone15,2）
    static var machineCode: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        let id = mirror.children.reduce(into: "") { acc, element in
            guard let v = element.value as? Int8, v != 0 else { return }
            acc.append(Character(UnicodeScalar(UInt8(v))))
        }
        return id.isEmpty ? "Unknown" : id
    }

    /// 機型友好名稱
    static var machineName: String {
        let code = machineCode
        if let name = modelMap[code] { return name }
        if code.hasPrefix("iPhone") { return "iPhone（未識別機型）" }
        if code.hasPrefix("iPad") { return "iPad（未識別機型）" }
        if code.hasPrefix("iPod") { return "iPod touch" }
        if code.contains("Mac") { return "Mac" }
        if code.contains("Simulator") || code.contains("x86") || code.contains("arm64") {
            return "模擬器"
        }
        return code
    }

    static var idfv: String {
        UIDevice.current.identifierForVendor?.uuidString.uppercased() ?? "不可用"
    }

    static var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static var screenDescription: String {
        let b = UIScreen.main.nativeBounds
        let scale = UIScreen.main.nativeScale
        let w = Int(b.width.rounded())
        let h = Int(b.height.rounded())
        let points = "\(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height)) pt"
        return "\(w)×\(h) px · @\(String(format: "%.0f", scale))x · \(points)"
    }

    static var disk: (total: String, used: String, free: String, usedRatio: Double) {
        let home = NSHomeDirectory()
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home),
              let totalNum = attrs[.systemSize] as? NSNumber,
              let freeNum = attrs[.systemFreeSize] as? NSNumber else {
            return ("—", "—", "—", 0)
        }
        let total = totalNum.doubleValue
        let free = freeNum.doubleValue
        let used = max(total - free, 0)
        return (fmtBytes(total), fmtBytes(used), fmtBytes(free), total > 0 ? used / total : 0)
    }

    static var memoryTotal: String {
        fmtBytes(Double(ProcessInfo.processInfo.physicalMemory))
    }

    static var cpuCores: String {
        let n = ProcessInfo.processInfo.processorCount
        let active = ProcessInfo.processInfo.activeProcessorCount
        return "\(n) 核（\(active) 活躍）"
    }

    static var uptime: String {
        let s = Int(ProcessInfo.processInfo.systemUptime)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d) 天 \(h) 小時 \(m) 分" }
        if h > 0 { return "\(h) 小時 \(m) 分" }
        return "\(m) 分"
    }

    static var thermal: (text: String, level: Int) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return ("正常", 0)
        case .fair:     return ("偏溫", 1)
        case .serious:  return ("偏熱", 2)
        case .critical: return ("過熱", 3)
        @unknown default: return ("未知", 0)
        }
    }

    /// 越獄痕跡檢查
    static var jailbreakTraces: [String] {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/cycript",
            "/var/jb"
        ]
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    static var timezone: String {
        let tz = TimeZone.current
        return "\(tz.identifier) · UTC\(tz.secondsFromGMT() >= 0 ? "+" : "-")\(abs(tz.secondsFromGMT()) / 3600)"
    }

    static var locale: String {
        Locale.current.identifier
    }

    static func fmtBytes(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = bytes
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        return String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    static let modelMap: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (第 2 代)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (第 3 代)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPad13,18": "iPad (第 10 代)",
        "iPad14,1": "iPad mini (第 6 代)",
        "iPad14,3": "iPad Pro 11 吋 (第 4 代)",
        "iPad14,5": "iPad Pro 12.9 吋 (第 6 代)",
        "iPad16,3": "iPad Pro 11 吋 (M4)",
        "iPad16,5": "iPad Pro 13 吋 (M4)"
    ]
}

// MARK: - 裝置資訊頁

struct DeviceInfoView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var batteryLevel: Int = -1
    @State private var batteryState: String = "—"
    @State private var copied = ""
    @State private var appear = false

    private var disk: (total: String, used: String, free: String, usedRatio: Double) {
        DeviceProbe.disk
    }

    var body: some View {
        TTScreen(title: "裝置資訊",
                 subtitle: "DEVICE INSPECTOR",
                 badge: "REAL-TIME",
                 badgeOn: true,
                 accent: TT.blue) {
            hero
            identityBlock
            hardwareBlock
            systemBlock
            securityBlock
            footer
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refreshBattery()
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
        }
        .onDisappear {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        .overlay(alignment: .top) {
            if !copied.isEmpty {
                Text("已複製\(copied)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TT.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(TT.mint))
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: 頂部

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(TT.blue.opacity(0.22), lineWidth: 1)
                    .frame(width: 104, height: 104)
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                    .foregroundStyle(TT.mint.opacity(0.4))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(appear ? 360 : 0))
                    .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: appear)
                Image(systemName: "cpu")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [TT.mint, TT.blue],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: TT.blue.opacity(0.5), radius: 12)
            }

            VStack(spacing: 4) {
                Text(UIDevice.current.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(DeviceProbe.machineName)
                    .font(.system(size: 12))
                    .foregroundStyle(TT.mint.opacity(0.85))
                Text(DeviceProbe.machineCode)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: 識別碼

    private var identityBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "裝置識別", accent: TT.mint)

            TTPanel(accent: TT.mint) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("供應商識別碼 IDFV")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = DeviceProbe.idfv
                            flash(" IDFV")
                        } label: {
                            Text("複製")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(TT.mint)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(TT.mint.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(DeviceProbe.idfv)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().background(Color.white.opacity(0.07))

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(TT.amber.opacity(0.8))
                            .padding(.top, 1)
                        Text("iOS 不開放第三方 App 讀取硬體 UDID，上面這組是系統分配給本 App 的唯一識別碼，同一台裝置上固定不變，可用來做裝置綁定。")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 硬體

    private var hardwareBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "硬體", accent: TT.blue)

            HStack(spacing: 10) {
                TTStat(title: "記憶體", value: DeviceProbe.memoryTotal, accent: TT.blue)
                TTStat(title: "處理器", value: "\(ProcessInfo.processInfo.processorCount)", unit: "核", accent: TT.blue)
            }

            TTPanel(accent: TT.blue) {
                VStack(spacing: 0) {
                    TTKeyRow(key: "儲存空間", value: "\(disk.free) 可用 / \(disk.total)")
                    TTMeterBar(ratio: disk.usedRatio, accent: TT.blue)
                        .padding(.bottom, 8)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "已使用", value: disk.used)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "螢幕", value: DeviceProbe.screenDescription)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "機型標識", value: DeviceProbe.machineCode, mono: true)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "電池", value: batteryText)
                    if batteryLevel >= 0 {
                        TTMeterBar(ratio: Double(batteryLevel) / 100.0,
                                   accent: batteryLevel <= 20 ? TT.rose : TT.mint)
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                    }
                }
            }
        }
    }

    // MARK: 系統

    private var systemBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "系統", accent: TT.violet)

            TTPanel(accent: TT.violet) {
                VStack(spacing: 0) {
                    TTKeyRow(key: "系統版本", value: DeviceProbe.osVersion)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "開機時長", value: DeviceProbe.uptime)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "熱狀態", value: DeviceProbe.thermal.text)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "時區", value: DeviceProbe.timezone)
                    Divider().background(Color.white.opacity(0.07))
                    TTKeyRow(key: "語系", value: DeviceProbe.locale, mono: true)
                }
            }
        }
    }

    // MARK: 安全

    private var securityBlock: some View {
        let traces = DeviceProbe.jailbreakTraces
        return VStack(spacing: 10) {
            TTSectionTitle(text: "安全狀態", accent: traces.isEmpty ? TT.mint : TT.rose)

            TTPanel(accent: traces.isEmpty ? TT.mint : TT.rose) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill((traces.isEmpty ? TT.mint : TT.rose).opacity(0.14))
                                .frame(width: 34, height: 34)
                            Image(systemName: traces.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(traces.isEmpty ? TT.mint : TT.rose)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(traces.isEmpty ? "未發現越獄痕跡" : "發現可疑檔案")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            Text(traces.isEmpty
                                 ? "系統分區與常見越獄路徑均正常"
                                 : "共 \(traces.count) 處，裝置可能已被改機")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                    }

                    if !traces.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(traces, id: \.self) { t in
                                Text(t)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(TT.rose.opacity(0.85))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(TT.rose.opacity(0.07)))
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 3) {
            Text("MINT DRAGON · DEVICE INSPECTOR")
                .font(.system(size: 8.5, weight: .medium))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.16))
            Text("所有資訊在本機讀取，不會上傳")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.18))
        }
        .padding(.top, 6)
    }

    // MARK: 輔助

    private var batteryText: String {
        guard batteryLevel >= 0 else { return "讀取中…" }
        return "\(batteryLevel)% · \(batteryState)"
    }

    private func refreshBattery() {
        let d = UIDevice.current
        let lvl = d.batteryLevel
        batteryLevel = lvl < 0 ? -1 : Int((lvl * 100).rounded())
        switch d.batteryState {
        case .charging: batteryState = "充電中"
        case .full:     batteryState = "已充滿"
        case .unplugged: batteryState = "使用中"
        default:        batteryState = "未知"
        }
    }

    private func flash(_ what: String) {
        withAnimation { copied = what }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { copied = "" }
        }
    }
}
