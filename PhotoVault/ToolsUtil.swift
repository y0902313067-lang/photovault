import SwiftUI
import UIKit

// MARK: - 時間工具

struct TimeToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    @State private var stampInput = ""
    @State private var manualDate = Date()
    @State private var copied = ""

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var zones: [(String, String, String)] {
        [
            ("台北", "Asia/Taipei", "TWD"),
            ("東京", "Asia/Tokyo", "JST"),
            ("首爾", "Asia/Seoul", "KST"),
            ("新加坡", "Asia/Singapore", "SGT"),
            ("雪梨", "Australia/Sydney", "AEDT"),
            ("杜拜", "Asia/Dubai", "GST"),
            ("倫敦", "Europe/London", "GMT"),
            ("巴黎", "Europe/Paris", "CET"),
            ("紐約", "America/New_York", "EST"),
            ("洛杉磯", "America/Los_Angeles", "PST")
        ]
    }

    var body: some View {
        TTScreen(title: "時間工具",
                 subtitle: "TIME CONVERTER",
                 badge: "LIVE",
                 badgeOn: true,
                 accent: TT.teal) {
            clockBlock
            stampBlock
            convertBlock
            worldBlock
        }
        .onReceive(timer) { t in
            now = t
        }
    }

    private var clockBlock: some View {
        TTPanel(accent: TT.teal) {
            VStack(spacing: 11) {
                Text(timeString(now, format: "HH:mm:ss"))
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: TT.teal.opacity(0.4), radius: 20)
                    .contentTransition(.numericText())
                Text(dateString(now))
                    .font(.system(size: 12.5, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.42))
                HStack(spacing: 6) {
                    Circle().fill(TT.mint).frame(width: 5, height: 5)
                    Text(TimeZone.current.identifier + " · " + offsetText())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func offsetText() -> String {
        let seconds = TimeZone.current.secondsFromGMT(for: now)
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        return String(format: "UTC%+d:%02d", hours, minutes)
    }

    private var stampBlock: some View {
        TTPanel(accent: TT.blue, padding: 14) {
            VStack(spacing: 11) {
                HStack {
                    Text("Unix 時間戳")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text(TimeZone.current.identifier)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.24))
                }
                HStack(spacing: 10) {
                    stampCell(title: "秒", value: "\(Int(now.timeIntervalSince1970))", accent: TT.blue)
                    stampCell(title: "毫秒", value: "\(Int(now.timeIntervalSince1970 * 1000))", accent: TT.indigo)
                }
                HStack {
                    stampCell(title: "ISO 8601", value: isoString(now), accent: TT.teal)
                }
                Text("點一下複製")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func stampCell(title: String, value: String, accent: Color) -> some View {
        Button {
            UIPasteboard.general.string = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { copied = value }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation { copied = "" }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(copied == value ? "已複製" : title)
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(copied == value ? accent : .white.opacity(0.32))
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(accent.opacity(copied == value ? 0.5 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var convertBlock: some View {
        TTPanel(accent: TT.violet) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("時間戳 → 日期")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    if !stampInput.isEmpty {
                        Button {
                            stampInput = ""
                        } label: {
                            Text("清空")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("", text: $stampInput)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TT.violet.opacity(0.28), lineWidth: 1)
                    )
                    .overlay(alignment: .leading) {
                        if stampInput.isEmpty {
                            Text("貼上 10 位（秒）或 13 位（毫秒）數字")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.22))
                                .padding(.leading, 13)
                        }
                    }

                if let parsed = parseStamp() {
                    VStack(spacing: 8) {
                        resultRow("本地時間", formatLocal(parsed), TT.mint)
                        resultRow("UTC", formatUTC(parsed), TT.teal)
                        resultRow("ISO 8601", isoString(parsed), TT.blue)
                        resultRow("相對現在", relative(parsed), TT.amber)
                    }
                } else if !stampInput.isEmpty {
                    Text("數字格式不對，貼 10 或 13 位數字")
                        .font(.system(size: 11))
                        .foregroundStyle(TT.amber.opacity(0.8))
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 9) {
                    Text("日期 → 時間戳")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.4))
                    DatePicker("", selection: $manualDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(TT.violet)
                    HStack(spacing: 8) {
                        Text("\(Int(manualDate.timeIntervalSince1970))")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = "\(Int(manualDate.timeIntervalSince1970))"
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text("複製")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(TT.violet)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func resultRow(_ key: String, _ value: String, _ accent: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(accent.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var worldBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "世界時鐘", accent: TT.teal)
            ForEach(zones, id: \.1) { zone in
                HStack(spacing: 10) {
                    Text(zone.0)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 56, alignment: .leading)
                    Text(zone.2)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.24))
                        .frame(width: 40, alignment: .leading)
                    Spacer()
                    if let tz = TimeZone(identifier: zone.1) {
                        Text(timeString(now, format: "HH:mm", zone: tz))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.85))
                        Text(dayDiffText(now, zone: tz))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(dayDiffColor(now, zone: tz))
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
            }
        }
    }

    private func dayDiffText(_ date: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let d = cal.component(.day, from: date)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone.current
        let l = local.component(.day, from: date)
        let diff = d - l
        if diff == 0 { return "同日" }
        return diff > 0 ? "+\(diff)日" : "\(diff)日"
    }

    private func dayDiffColor(_ date: Date, zone: TimeZone) -> Color {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let d = cal.component(.day, from: date)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone.current
        let l = local.component(.day, from: date)
        return d == l ? Color.white.opacity(0.22) : TT.amber.opacity(0.8)
    }

    private func parseStamp() -> Date? {
        let s = stampInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = Double(s), n > 0 else { return nil }
        if s.count >= 13 {
            return Date(timeIntervalSince1970: n / 1000.0)
        }
        if s.count <= 10 {
            return Date(timeIntervalSince1970: n)
        }
        return Date(timeIntervalSince1970: n / 1000.0)
    }

    private func timeString(_ date: Date, format: String, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = zone
        f.locale = Locale(identifier: "zh_TW")
        return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        f.locale = Locale(identifier: "zh_TW")
        return f.string(from: date)
    }

    private func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone.current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func formatLocal(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    private func formatUTC(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private func relative(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        let absDiff = abs(diff)
        let prefix = diff < 0 ? "前" : "後"
        if absDiff < 60 { return "\(Int(absDiff)) 秒\(prefix)" }
        if absDiff < 3600 { return "\(Int(absDiff / 60)) 分鐘\(prefix)" }
        if absDiff < 86400 { return "\(Int(absDiff / 3600)) 小時\(prefix)" }
        return "\(Int(absDiff / 86400)) 天\(prefix)"
    }
}

// MARK: - 單位換算

struct MeasureUnit {
    let name: String
    let symbol: String
    let factor: Double
}

struct MeasureCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let units: [MeasureUnit]
    var temperature: Bool = false
}

enum MeasureData {
    static let all: [MeasureCategory] = [
        MeasureCategory(name: "長度", icon: "ruler", units: [
            MeasureUnit(name: "毫米", symbol: "mm", factor: 0.001),
            MeasureUnit(name: "公分", symbol: "cm", factor: 0.01),
            MeasureUnit(name: "公尺", symbol: "m", factor: 1),
            MeasureUnit(name: "公里", symbol: "km", factor: 1000),
            MeasureUnit(name: "英寸", symbol: "in", factor: 0.0254),
            MeasureUnit(name: "英尺", symbol: "ft", factor: 0.3048),
            MeasureUnit(name: "碼", symbol: "yd", factor: 0.9144),
            MeasureUnit(name: "英里", symbol: "mi", factor: 1609.344),
            MeasureUnit(name: "海里", symbol: "nmi", factor: 1852)
        ]),
        MeasureCategory(name: "重量", icon: "scalemass", units: [
            MeasureUnit(name: "毫克", symbol: "mg", factor: 0.000001),
            MeasureUnit(name: "公克", symbol: "g", factor: 0.001),
            MeasureUnit(name: "公斤", symbol: "kg", factor: 1),
            MeasureUnit(name: "公噸", symbol: "t", factor: 1000),
            MeasureUnit(name: "台斤", symbol: "斤", factor: 0.6),
            MeasureUnit(name: "台兩", symbol: "兩", factor: 0.0375),
            MeasureUnit(name: "盎司", symbol: "oz", factor: 0.028349523125),
            MeasureUnit(name: "磅", symbol: "lb", factor: 0.45359237)
        ]),
        MeasureCategory(name: "溫度", icon: "thermometer.medium", units: [
            MeasureUnit(name: "攝氏", symbol: "°C", factor: 1),
            MeasureUnit(name: "華氏", symbol: "°F", factor: 1),
            MeasureUnit(name: "克氏", symbol: "K", factor: 1)
        ], temperature: true),
        MeasureCategory(name: "面積", icon: "square.dashed", units: [
            MeasureUnit(name: "平方公分", symbol: "cm²", factor: 0.0001),
            MeasureUnit(name: "平方公尺", symbol: "m²", factor: 1),
            MeasureUnit(name: "平方公里", symbol: "km²", factor: 1000000),
            MeasureUnit(name: "公頃", symbol: "ha", factor: 10000),
            MeasureUnit(name: "坪", symbol: "坪", factor: 3.305785),
            MeasureUnit(name: "平方英尺", symbol: "ft²", factor: 0.09290304),
            MeasureUnit(name: "英畝", symbol: "ac", factor: 4046.8564224)
        ]),
        MeasureCategory(name: "體積", icon: "cube", units: [
            MeasureUnit(name: "毫升", symbol: "mL", factor: 0.001),
            MeasureUnit(name: "公升", symbol: "L", factor: 1),
            MeasureUnit(name: "立方公尺", symbol: "m³", factor: 1000),
            MeasureUnit(name: "美制加侖", symbol: "gal", factor: 3.785411784),
            MeasureUnit(name: "美制品脫", symbol: "pt", factor: 0.473176473),
            MeasureUnit(name: "液量盎司", symbol: "fl oz", factor: 0.0295735296)
        ]),
        MeasureCategory(name: "速度", icon: "speedometer", units: [
            MeasureUnit(name: "公尺/秒", symbol: "m/s", factor: 1),
            MeasureUnit(name: "公里/時", symbol: "km/h", factor: 0.277777778),
            MeasureUnit(name: "英里/時", symbol: "mph", factor: 0.44704),
            MeasureUnit(name: "節", symbol: "kn", factor: 0.514444444),
            MeasureUnit(name: "英尺/秒", symbol: "ft/s", factor: 0.3048)
        ]),
        MeasureCategory(name: "資料", icon: "internaldrive", units: [
            MeasureUnit(name: "位元", symbol: "bit", factor: 0.125),
            MeasureUnit(name: "位元組", symbol: "B", factor: 1),
            MeasureUnit(name: "KB", symbol: "KB", factor: 1024),
            MeasureUnit(name: "MB", symbol: "MB", factor: 1048576),
            MeasureUnit(name: "GB", symbol: "GB", factor: 1073741824),
            MeasureUnit(name: "TB", symbol: "TB", factor: 1099511627776)
        ]),
        MeasureCategory(name: "時間", icon: "clock", units: [
            MeasureUnit(name: "毫秒", symbol: "ms", factor: 0.001),
            MeasureUnit(name: "秒", symbol: "s", factor: 1),
            MeasureUnit(name: "分鐘", symbol: "min", factor: 60),
            MeasureUnit(name: "小時", symbol: "h", factor: 3600),
            MeasureUnit(name: "天", symbol: "d", factor: 86400),
            MeasureUnit(name: "週", symbol: "wk", factor: 604800)
        ]),
        MeasureCategory(name: "壓力", icon: "gauge.medium", units: [
            MeasureUnit(name: "帕", symbol: "Pa", factor: 0.01),
            MeasureUnit(name: "百帕", symbol: "hPa", factor: 1),
            MeasureUnit(name: "千帕", symbol: "kPa", factor: 10),
            MeasureUnit(name: "巴", symbol: "bar", factor: 1000),
            MeasureUnit(name: "大氣壓", symbol: "atm", factor: 1013.25),
            MeasureUnit(name: "毫米汞柱", symbol: "mmHg", factor: 1.33322),
            MeasureUnit(name: "psi", symbol: "psi", factor: 68.9476)
        ])
    ]
}

struct UnitConvertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var categoryIndex = 0
    @State private var input = "1"
    @State private var fromIndex = 0
    @State private var copied = ""

    private var category: MeasureCategory {
        MeasureData.all[min(categoryIndex, MeasureData.all.count - 1)]
    }

    var body: some View {
        TTScreen(title: "單位換算",
                 subtitle: "UNIT CONVERTER",
                 badge: category.name.uppercased(),
                 badgeOn: true,
                 accent: TT.amber) {
            categoryChips
            inputBlock
            resultList
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(MeasureData.all.enumerated()), id: \.offset) { idx, cat in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            categoryIndex = idx
                            fromIndex = 0
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(cat.name)
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(idx == categoryIndex ? TT.ink : .white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(idx == categoryIndex
                                      ? AnyShapeStyle(LinearGradient(colors: [TT.amber, TT.mint],
                                                                     startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(Color.white.opacity(0.05)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var inputBlock: some View {
        TTPanel(accent: TT.amber) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("", text: $input)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(alignment: .leading) {
                        if input.isEmpty {
                            Text("輸入數值")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.18))
                                .padding(.leading, 14)
                        }
                    }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(category.units.enumerated()), id: \.offset) { idx, unit in
                            Button {
                                fromIndex = idx
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(unit.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(idx == fromIndex ? TT.ink : .white.opacity(0.5))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(
                                        Capsule()
                                            .fill(idx == fromIndex
                                                  ? AnyShapeStyle(TT.amber)
                                                  : AnyShapeStyle(Color.white.opacity(0.05)))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var resultList: some View {
        VStack(spacing: 8) {
            ForEach(Array(category.units.enumerated()), id: \.offset) { idx, unit in
                resultRow(idx: idx, unit: unit)
            }
        }
    }

    private func resultRow(idx: Int, unit: MeasureUnit) -> some View {
        let value = convert(to: idx)
        let isSource = idx == fromIndex
        return Button {
            UIPasteboard.general.string = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { copied = unit.symbol }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation { copied = "" }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(isSource ? 0.92 : 0.72))
                    Text(unit.symbol)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                Spacer()
                Text(copied == unit.symbol ? "已複製" : value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSource ? TT.amber : .white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(isSource ? 0.075 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(TT.amber.opacity(isSource ? 0.32 : 0.0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func convert(to idx: Int) -> String {
        let raw = input.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(raw) else { return "—" }
        let units = category.units
        guard units.indices.contains(fromIndex), units.indices.contains(idx) else { return "—" }

        if category.temperature {
            let celsius: Double
            switch fromIndex {
            case 0: celsius = v
            case 1: celsius = (v - 32.0) * 5.0 / 9.0
            default: celsius = v - 273.15
            }
            let out: Double
            switch idx {
            case 0: out = celsius
            case 1: out = celsius * 9.0 / 5.0 + 32.0
            default: out = celsius + 273.15
            }
            return formatNumber(out)
        }

        let base = v * units[fromIndex].factor
        let out = base / units[idx].factor
        return formatNumber(out)
    }

    private func formatNumber(_ d: Double) -> String {
        if d == 0 { return "0" }
        let absD = abs(d)
        if absD >= 1e12 || absD < 1e-6 {
            return String(format: "%.4e", d)
        }
        if absD >= 1000 {
            return String(format: "%.2f", d)
        }
        if absD >= 1 {
            return String(format: "%.4g", d)
        }
        return String(format: "%.6f", d)
    }
}
