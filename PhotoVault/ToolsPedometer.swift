import SwiftUI
import UIKit
import CoreMotion

// MARK: - 單日資料

struct StepDay: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
}

// MARK: - 計步資料來源

final class PedometerModel: ObservableObject {
    @Published var steps = 0
    @Published var distance: Double = 0
    @Published var floors = 0
    @Published var pace: Double?
    @Published var cadence: Double?
    @Published var days: [StepDay] = []
    @Published var updated: Date?
    @Published var loading = false
    @Published var errorText: String?
    @Published var authorized = false
    @Published var available = true

    private let queryPedometer = CMPedometer()
    private let livePedometer = CMPedometer()
    private var live = false
    private var lastLiveSteps = 0
    private var lastLiveDate: Date?

    private var calendar: Calendar { Calendar.current }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    var goal: Int { 8000 }

    var progress: Double {
        Double(steps) / Double(goal)
    }

    var active: Bool { steps > 0 }

    init() {
        available = CMPedometer.isStepCountingAvailable()
        refresh()
    }

    func refresh() {
        available = CMPedometer.isStepCountingAvailable()
        guard available else {
            errorText = "這台裝置沒有計步感測器，模擬器也讀不到"
            return
        }

        let status = CMPedometer.authorizationStatus()
        authorized = (status == .authorized)
        if status == .denied {
            errorText = "動作與健身權限沒開，資料讀不到"
        } else {
            errorText = nil
        }

        loading = true
        let now = Date()
        let start = startOfToday

        queryPedometer.queryPedometerData(from: start, to: now) { data, error in
            DispatchQueue.main.async {
                self.loading = false
                if let data = data {
                    self.steps = data.numberOfSteps.intValue
                    self.distance = data.distance?.doubleValue ?? 0
                    self.floors = data.floorsAscended?.intValue ?? 0
                    self.pace = data.averageActivePace?.doubleValue
                    self.updated = Date()
                    self.authorized = true
                    self.errorText = nil
                } else if error != nil {
                    self.errorText = "今天還讀不到資料，走幾步再回來看看"
                }
            }
        }

        loadWeek()
        startLive()
    }

    private func loadWeek() {
        var collected: [StepDay] = []
        let group = DispatchGroup()

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: startOfToday),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { continue }

            let end = min(dayEnd, Date())
            group.enter()
            queryPedometer.queryPedometerData(from: dayStart, to: end) { data, _ in
                let stepsCount = data?.numberOfSteps.intValue ?? 0
                collected.append(StepDay(date: dayStart, steps: stepsCount))
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.days = collected.sorted { $0.date < $1.date }
        }
    }

    private func startLive() {
        guard !live, CMPedometer.isStepCountingAvailable() else { return }
        live = true
        lastLiveSteps = 0
        lastLiveDate = Date()

        livePedometer.startUpdates(from: startOfToday) { data, _ in
            guard let data = data else { return }
            DispatchQueue.main.async {
                self.steps = max(self.steps, data.numberOfSteps.intValue)
                self.distance = data.distance?.doubleValue ?? self.distance
                self.floors = data.floorsAscended?.intValue ?? self.floors
                if let activePace = data.averageActivePace?.doubleValue, activePace > 0 {
                    self.pace = activePace
                }

                // 用相鄰兩次更新的差值算「現在每分鐘幾步」
                let now = Date()
                if let lastDate = self.lastLiveDate {
                    let seconds = now.timeIntervalSince(lastDate)
                    let delta = data.numberOfSteps.intValue - self.lastLiveSteps
                    if seconds >= 2, delta >= 0 {
                        if delta > 0 {
                            self.cadence = Double(delta) / seconds * 60
                        } else {
                            self.cadence = 0
                        }
                        self.lastLiveMetrics(now: now, steps: data.numberOfSteps.intValue)
                    }
                } else {
                    self.lastLiveMetrics(now: now, steps: data.numberOfSteps.intValue)
                }
                self.updated = now
            }
        }
    }

    private func lastLiveMetrics(now: Date, steps: Int) {
        lastLiveDate = now
        lastLiveSteps = steps
    }

    deinit {
        if live { livePedometer.stopUpdates() }
    }
}

// MARK: - 頁面

struct PedometerView: View {
    @StateObject private var model = PedometerModel()

    private let accent = TT.amber

    var body: some View {
        TTScreen(title: "計步與活動",
                 subtitle: "STEP COUNTER",
                 badge: model.loading ? "讀取中" : "今日",
                 badgeOn: true,
                 accent: accent) {

            if !model.available {
                TTEmptyHint(icon: "figure.walk",
                            text: "這台裝置沒有計步感測器")
            } else if !model.authorized, let error = model.errorText {
                permissionBlock(error)
            } else {
                ringBlock
                statsBlock
                weekBlock
                noteBlock
            }
        }
    }

    // MARK: 權限

    private func permissionBlock(_ text: String) -> some View {
        TTPanel(accent: TT.rose) {
            VStack(alignment: .leading, spacing: 12) {
                TTSectionTitle(text: "需要動作權限", accent: TT.rose)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text("到「設定 → 隱私權與安全性 → 動作與健身」把本 App 打開，回來就會有數字。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)

                TTButton(title: "去設定開啟", icon: "gearshape", accent: TT.rose) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                TTButton(title: "重新讀取", icon: "arrow.clockwise", accent: TT.teal) {
                    model.refresh()
                }
            }
        }
    }

    // MARK: 今日進度

    private var ringBlock: some View {
        TTPanel(accent: accent) {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(model.steps)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("步")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.8))
                    Spacer(minLength: 0)
                    TTPill(text: "目標 \(model.goal)", color: TT.mint)
                }

                TTMeterBar(ratio: model.progress, accent: accent, height: 9)

                HStack {
                    Text(progressText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer(minLength: 0)
                    if let updated = model.updated {
                        Text(clockText(updated))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.26))
                    }
                }

                if let error = model.errorText, model.authorized {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(TT.amber.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var progressText: String {
        guard model.steps > 0 else { return "今天還沒開始走" }
        if model.steps >= model.goal { return "今天目標達成，再多走都是多的" }
        let remain = model.goal - model.steps
        return "還差 \(remain) 步"
    }

    private func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "更新 \(formatter.string(from: date))"
    }

    // MARK: 數據

    private var statsBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TTStat(title: "步行距離", value: distanceText, unit: "km", accent: accent)
                TTStat(title: "爬升樓層", value: "\(model.floors)", unit: "層", accent: TT.teal)
            }
            HStack(spacing: 10) {
                TTStat(title: "平均配速", value: paceText, unit: "/km", accent: TT.violet)
                TTStat(title: "目前節奏", value: cadenceText, unit: "步/分", accent: TT.mint)
            }

            if let pace = model.pace, pace > 0 {
                TTPanel(accent: TT.violet) {
                    VStack(alignment: .leading, spacing: 8) {
                        TTSectionTitle(text: "換算", accent: TT.violet)
                        TTKeyRow(key: "每小時", value: String(format: "%.1f 公里", 3600 / pace / 1000), accent: TT.violet)
                        TTKeyRow(key: "每公里", value: String(format: "%.1f 分鐘", pace * 1000 / 60), accent: TT.violet)
                        TTKeyRow(key: "走完 8000 步約", value: estimatedText, accent: TT.violet)
                    }
                }
            }
        }
    }

    private var distanceText: String {
        model.distance > 0 ? String(format: "%.2f", model.distance / 1000) : "0.00"
    }

    private var paceText: String {
        guard let pace = model.pace, pace > 0 else { return "—" }
        return String(format: "%.1f", pace * 1000 / 60)
    }

    private var cadenceText: String {
        guard let cadence = model.cadence, cadence > 0.5 else { return "—" }
        return String(format: "%.0f", cadence)
    }

    private var estimatedText: String {
        guard let pace = model.pace, pace > 0 else { return "—" }
        // 以每步 0.7 公尺估算
        let kilometers = 8000 * 0.7 / 1000
        let seconds = kilometers * 1000 * pace
        let minutes = Int(seconds / 60)
        return "約 \(minutes) 分鐘"
    }

    // MARK: 近七天

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                TTSectionTitle(text: "近七天", accent: TT.mint)
                Spacer(minLength: 0)
                if let total = weekTotal {
                    Text("合計 \(total) 步")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            TTPanel(accent: TT.mint) {
                VStack(spacing: 12) {
                    if model.days.isEmpty {
                        TTEmptyHint(icon: "chart.bar", text: "系統還在算，等一下再回來看")
                    } else {
                        HStack(alignment: .bottom, spacing: 9) {
                            ForEach(model.days) { day in
                                dayColumn(day)
                            }
                        }
                        .frame(height: 132)

                        Text("系統只保留最近七天的計步紀錄")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.24))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    private var weekTotal: Int? {
        guard !model.days.isEmpty else { return nil }
        return model.days.reduce(0) { $0 + $1.steps }
    }

    private func dayColumn(_ day: StepDay) -> some View {
        let maxSteps = max(model.days.map { $0.steps }.max() ?? 1, 1)
        let ratio = Double(day.steps) / Double(maxSteps)
        let isToday = Calendar.current.isDateInToday(day.date)

        return VStack(spacing: 6) {
            Text(day.steps > 0 ? "\(day.steps)" : "—")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isToday ? TT.mint : .white.opacity(0.34))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 86)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: isToday ? [TT.mint, TT.teal]
                                                         : [TT.teal.opacity(0.55), TT.blue.opacity(0.45)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: max(4, 86 * CGFloat(min(max(ratio, 0), 1))))
            }

            Text(dayLabel(day.date))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(isToday ? TT.mint.opacity(0.9) : .white.opacity(0.28))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.string(from: date)
    }

    // MARK: 說明

    private var noteBlock: some View {
        TTPanel(accent: TT.amber) {
            VStack(alignment: .leading, spacing: 8) {
                TTSectionTitle(text: "資料從哪來", accent: TT.amber)
                Text("直接讀系統的計步感測器，不用開 GPS、不上傳、不耗額外電。手機放在口袋或包包裡走動就會累積，放在桌上不動不會增加。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
