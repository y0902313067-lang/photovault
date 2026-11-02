import SwiftUI
import UIKit

// MARK: - 貨幣

struct CurrencyInfo: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }

    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "TWD", name: "新台幣", flag: "🇹🇼"),
        CurrencyInfo(code: "USD", name: "美元", flag: "🇺🇸"),
        CurrencyInfo(code: "JPY", name: "日圓", flag: "🇯🇵"),
        CurrencyInfo(code: "EUR", name: "歐元", flag: "🇪🇺"),
        CurrencyInfo(code: "CNY", name: "人民幣", flag: "🇨🇳"),
        CurrencyInfo(code: "HKD", name: "港幣", flag: "🇭🇰"),
        CurrencyInfo(code: "GBP", name: "英鎊", flag: "🇬🇧"),
        CurrencyInfo(code: "KRW", name: "韓元", flag: "🇰🇷"),
        CurrencyInfo(code: "SGD", name: "新加坡幣", flag: "🇸🇬"),
        CurrencyInfo(code: "AUD", name: "澳幣", flag: "🇦🇺"),
        CurrencyInfo(code: "CAD", name: "加幣", flag: "🇨🇦"),
        CurrencyInfo(code: "CHF", name: "瑞士法郎", flag: "🇨🇭"),
        CurrencyInfo(code: "NZD", name: "紐西蘭幣", flag: "🇳🇿"),
        CurrencyInfo(code: "THB", name: "泰銖", flag: "🇹🇭"),
        CurrencyInfo(code: "MYR", name: "馬來西亞令吉", flag: "🇲🇾"),
        CurrencyInfo(code: "PHP", name: "菲律賓披索", flag: "🇵🇭"),
        CurrencyInfo(code: "VND", name: "越南盾", flag: "🇻🇳"),
        CurrencyInfo(code: "IDR", name: "印尼盾", flag: "🇮🇩"),
        CurrencyInfo(code: "INR", name: "印度盧比", flag: "🇮🇳"),
        CurrencyInfo(code: "AED", name: "阿聯酋迪拉姆", flag: "🇦🇪"),
        CurrencyInfo(code: "SAR", name: "沙烏地里亞爾", flag: "🇸🇦"),
        CurrencyInfo(code: "ZAR", name: "南非蘭特", flag: "🇿🇦"),
        CurrencyInfo(code: "BRL", name: "巴西雷亞爾", flag: "🇧🇷"),
        CurrencyInfo(code: "MXN", name: "墨西哥披索", flag: "🇲🇽"),
        CurrencyInfo(code: "TRY", name: "土耳其里拉", flag: "🇹🇷"),
        CurrencyInfo(code: "SEK", name: "瑞典克朗", flag: "🇸🇪"),
        CurrencyInfo(code: "NOK", name: "挪威克朗", flag: "🇳🇴"),
        CurrencyInfo(code: "DKK", name: "丹麥克朗", flag: "🇩🇰"),
        CurrencyInfo(code: "PLN", name: "波蘭茲羅提", flag: "🇵🇱"),
        CurrencyInfo(code: "RUB", name: "俄羅斯盧布", flag: "🇷🇺")
    ]

    static func find(_ code: String) -> CurrencyInfo {
        all.first { $0.code == code } ?? all[0]
    }
}

// MARK: - 匯率資料

struct RateRecord: Identifiable {
    let id = UUID()
    let amount: Double
    let from: String
    let to: String
    let result: Double
    let date: Date
}

final class RateModel: ObservableObject {
    @Published var rates: [String: Double] = [:]
    @Published var lastUpdate: Date?
    @Published var loading = false
    @Published var usingCache = false
    @Published var errorText: String?
    @Published var sourceNote = ""

    private let cacheRatesKey = "pv.rate.rates"
    private let cacheTimeKey = "pv.rate.time"

    func load() {
        readCache()
        fetch()
    }

    func fetch() {
        loading = true
        errorText = nil

        guard let url = URL(string: "https://open.er-api.com/v6/latest/TWD") else {
            loading = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data, let parsed = RateModel.parsePrimary(data) {
                DispatchQueue.main.async {
                    self.apply(parsed.rates, date: parsed.date, note: "每日更新")
                }
            } else {
                self.fetchBackup()
            }
        }.resume()
    }

    private func fetchBackup() {
        guard let url = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/twd.json") else {
            finishWithError()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data, let parsed = RateModel.parseBackup(data) {
                DispatchQueue.main.async {
                    self.apply(parsed.rates, date: parsed.date, note: "備援來源")
                }
            } else {
                self.finishWithError()
            }
        }.resume()
    }

    private func finishWithError() {
        DispatchQueue.main.async {
            self.loading = false
            if self.rates.isEmpty {
                self.errorText = "連不上匯率服務，檢查一下網路"
                self.usingCache = false
            } else {
                self.usingCache = true
                self.errorText = nil
            }
        }
    }

    private func apply(_ newRates: [String: Double], date: Date, note: String) {
        var cleaned = newRates
        cleaned["TWD"] = 1.0
        rates = cleaned
        lastUpdate = date
        loading = false
        usingCache = false
        errorText = nil
        sourceNote = note
        writeCache(date: date)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: 快取

    private func readCache() {
        let defaults = UserDefaults.standard
        guard let stored = defaults.dictionary(forKey: cacheRatesKey) as? [String: Double],
              !stored.isEmpty else { return }
        var cleaned = stored
        cleaned["TWD"] = 1.0
        rates = cleaned
        let stamp = defaults.double(forKey: cacheTimeKey)
        if stamp > 0 {
            lastUpdate = Date(timeIntervalSince1970: stamp)
        }
        usingCache = true
    }

    private func writeCache(date: Date) {
        let defaults = UserDefaults.standard
        defaults.set(rates, forKey: cacheRatesKey)
        defaults.set(date.timeIntervalSince1970, forKey: cacheTimeKey)
    }

    // MARK: 解析

    private static func parsePrimary(_ data: Data) -> (rates: [String: Double], date: Date)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let raw = object["rates"] as? [String: Any] else { return nil }

        var result: [String: Double] = [:]
        for (key, value) in raw {
            if let number = value as? NSNumber { result[key.uppercased()] = number.doubleValue }
            else if let double = value as? Double { result[key.uppercased()] = double }
        }
        guard result.count > 5 else { return nil }

        var date = Date()
        if let stamp = object["time_last_update_unix"] as? NSNumber {
            date = Date(timeIntervalSince1970: stamp.doubleValue)
        }
        return (result, date)
    }

    private static func parseBackup(_ data: Data) -> (rates: [String: Double], date: Date)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let raw = object["twd"] as? [String: Any] else { return nil }

        var result: [String: Double] = [:]
        for (key, value) in raw {
            if let number = value as? NSNumber { result[key.uppercased()] = number.doubleValue }
            else if let double = value as? Double { result[key.uppercased()] = double }
        }
        guard result.count > 5 else { return nil }

        var date = Date()
        if let text = object["date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let parsed = formatter.date(from: text) { date = parsed }
        }
        return (result, date)
    }
}

// MARK: - 頁面

struct RateView: View {
    @StateObject private var model = RateModel()

    @State private var amountText = "1000"
    @State private var fromCode = "TWD"
    @State private var toCode = "USD"
    @State private var records: [RateRecord] = []
    @State private var choosingFrom = true
    @State private var showPicker = false

    private let accent = TT.teal

    private var amount: Double {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }

    private var converted: Double? {
        guard let fromRate = model.rates[fromCode], let toRate = model.rates[toCode],
              fromRate > 0 else { return nil }
        return amount / fromRate * toRate
    }

    private var unitRate: Double? {
        guard let fromRate = model.rates[fromCode], let toRate = model.rates[toCode],
              fromRate > 0 else { return nil }
        return toRate / fromRate
    }

    var body: some View {
        TTScreen(title: "即時匯率",
                 subtitle: "LIVE EXCHANGE RATE",
                 badge: model.loading ? "更新中" : (model.usingCache ? "快取" : "已更新"),
                 badgeOn: !model.loading,
                 accent: accent) {

            converterBlock
            quickBlock
            if !records.isEmpty {
                recordBlock
            }
            statusBlock
        }
        .onAppear {
            if model.rates.isEmpty { model.load() }
        }
        .sheet(isPresented: $showPicker) {
            currencyPicker
        }
    }

    // MARK: 換算

    private var converterBlock: some View {
        TTPanel(accent: accent) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("金額")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.32))
                        TextField("1000", text: $amountText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .keyboardType(.decimalPad)
                            .frame(height: 34)
                    }

                    Button {
                        let previous = fromCode
                        fromCode = toCode
                        toCode = previous
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(TT.ink)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(accent))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    currencyButton(code: fromCode, label: "從") {
                        choosingFrom = true
                        showPicker = true
                    }
                    currencyButton(code: toCode, label: "到") {
                        choosingFrom = false
                        showPicker = true
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("換算結果")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.32))

                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(resultText)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(toCode)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.85))
                        Spacer(minLength: 0)
                    }

                    if let unitRate = unitRate {
                        Text("1 \(fromCode) = \(formatRate(unitRate)) \(toCode)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.34))
                    }

                    if converted != nil {
                        Button {
                            saveRecord()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text("記一筆")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(accent)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(accent.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func currencyButton(code: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 6) {
                    Text(CurrencyInfo.find(code).flag)
                        .font(.system(size: 15))
                    Text(code)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.94))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer(minLength: 0)
                }
                Text(CurrencyInfo.find(code).name)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(accent.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var resultText: String {
        guard let converted = converted else { return "—" }
        return formatAmount(converted)
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if abs(value) >= 1000 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else if abs(value) < 1 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 4
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func formatRate(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.2f", value) }
        if value >= 1 { return String(format: "%.4f", value) }
        return String(format: "%.6f", value)
    }

    // MARK: 常用對

    private var quickBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            TTSectionTitle(text: "常用", accent: TT.mint)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9),
                                GridItem(.flexible(), spacing: 9)], spacing: 9) {
                quickCard("TWD", "USD")
                quickCard("TWD", "JPY")
                quickCard("TWD", "CNY")
                quickCard("USD", "TWD")
            }
        }
    }

    private func pairRate(_ from: String, _ to: String) -> Double? {
        guard let base = model.rates[from], base > 0, let target = model.rates[to] else { return nil }
        return target / base
    }

    private func quickCard(_ from: String, _ to: String) -> some View {
        let rate = pairRate(from, to)

        return Button {
            fromCode = from
            toCode = to
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(from) → \(to)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Text(rate == nil ? "—" : formatRate(rate!))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder((fromCode == from && toCode == to ? accent.opacity(0.5) : Color.white.opacity(0.06)),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 記錄

    private var recordBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TTSectionTitle(text: "最近換算", accent: TT.violet)
                Spacer(minLength: 0)
                Button {
                    records.removeAll()
                } label: {
                    Text("清空")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }

            TTPanel(accent: TT.violet) {
                VStack(spacing: 0) {
                    ForEach(Array(records.indices), id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 1)
                        }
                        recordRow(records[index])
                    }
                }
            }
        }
    }

    private func recordRow(_ record: RateRecord) -> some View {
        HStack(spacing: 8) {
            Text("\(formatAmount(record.amount)) \(record.from)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.2))
            Text("\(formatAmount(record.result)) \(record.to)")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Text(timeText(record.date))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.24))
        }
        .padding(.vertical, 9)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func saveRecord() {
        guard let converted = converted else { return }
        records.insert(RateRecord(amount: amount, from: fromCode, to: toCode,
                                  result: converted, date: Date()), at: 0)
        if records.count > 10 { records.removeLast() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: 狀態

    private var statusBlock: some View {
        TTPanel(accent: model.usingCache ? TT.amber : TT.mint) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.usingCache ? TT.amber : TT.mint)
                        .frame(width: 6, height: 6)
                    Text(model.usingCache ? "離線 · 顯示上次匯率" : "匯率已更新")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 0)
                    if model.loading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: accent))
                            .scaleEffect(0.7)
                    } else {
                        Button {
                            model.fetch()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let lastUpdate = model.lastUpdate {
                    Text("更新時間：\(longTime(lastUpdate))（台北時間）\(model.sourceNote.isEmpty ? "" : " · \(model.sourceNote)")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.34))
                }

                if let error = model.errorText {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(TT.amber.opacity(0.85))
                }

                Text("匯率是中價，不是銀行牌告價；實際換匯會有手續費與價差。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.24))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func longTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter.string(from: date)
    }

    // MARK: 選貨幣

    private var currencyPicker: some View {
        NavigationView {
            ZStack {
                Backdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(CurrencyInfo.all) { currency in
                            Button {
                                if choosingFrom { fromCode = currency.code } else { toCode = currency.code }
                                showPicker = false
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                HStack(spacing: 11) {
                                    Text(currency.flag)
                                        .font(.system(size: 18))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(currency.code)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.92))
                                        Text(currency.name)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    Spacer(minLength: 0)
                                    if (choosingFrom ? fromCode : toCode) == currency.code {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(accent)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 1)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(choosingFrom ? "從哪個幣別" : "換成什麼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { showPicker = false }
                        .foregroundStyle(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
