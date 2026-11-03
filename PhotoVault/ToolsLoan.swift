import SwiftUI
import UIKit

// MARK: - 攤還計算

enum LoanMethod: String, CaseIterable, Identifiable {
    case equalPayment
    case equalPrincipal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equalPayment:   return "本息平均"
        case .equalPrincipal: return "本金平均"
        }
    }

    var note: String {
        switch self {
        case .equalPayment:   return "每月繳一樣多，好抓預算"
        case .equalPrincipal: return "每月本金一樣，前期繳得多、之後遞減"
        }
    }
}

struct LoanRow: Identifiable {
    let id = UUID()
    let period: Int
    let payment: Double
    let principal: Double
    let interest: Double
    let balance: Double
}

struct LoanPlan {
    var firstPayment: Double = 0
    var lastPayment: Double = 0
    var totalInterest: Double = 0
    var totalPayment: Double = 0
    var rows: [LoanRow] = []

    var interestRatio: Double {
        totalPayment > 0 ? totalInterest / totalPayment : 0
    }
}

enum LoanMath {

    static func compute(principal: Double,
                        annualRate: Double,
                        months: Int,
                        graceMonths: Int,
                        method: LoanMethod) -> LoanPlan {
        var plan = LoanPlan()
        guard principal > 0, months > 0 else { return plan }

        let rate = max(annualRate, 0) / 100 / 12
        let grace = min(max(graceMonths, 0), months - 1)
        let payMonths = months - grace
        var balance = principal
        var rows: [LoanRow] = []

        // 寬限期：只繳利息，本金不動
        if grace > 0 {
            for period in 1...grace {
                let interest = balance * rate
                rows.append(LoanRow(period: period, payment: interest,
                                    principal: 0, interest: interest, balance: balance))
                plan.totalInterest += interest
                plan.totalPayment += interest
            }
        }

        switch method {
        case .equalPayment:
            let payment: Double
            if rate > 0 {
                payment = balance * rate / (1 - pow(1 + rate, -Double(payMonths)))
            } else {
                payment = balance / Double(payMonths)
            }

            for index in 0..<payMonths {
                let period = grace + index + 1
                let interest = balance * rate
                var principalPart = payment - interest
                if principalPart < 0 { principalPart = 0 }
                if index == payMonths - 1 || principalPart > balance {
                    principalPart = balance
                }
                let actualPayment = principalPart + interest
                balance -= principalPart
                if balance < 0 { balance = 0 }

                rows.append(LoanRow(period: period, payment: actualPayment,
                                    principal: principalPart, interest: interest, balance: balance))
                plan.totalInterest += interest
                plan.totalPayment += actualPayment
            }

        case .equalPrincipal:
            let principalPart = principal / Double(months)
            for index in 0..<payMonths {
                let period = grace + index + 1
                let interest = balance * rate
                var pay = principalPart
                if pay > balance { pay = balance }
                balance -= pay
                if balance < 0 { balance = 0 }
                let actualPayment = pay + interest

                rows.append(LoanRow(period: period, payment: actualPayment,
                                    principal: pay, interest: interest, balance: balance))
                plan.totalInterest += interest
                plan.totalPayment += actualPayment
            }
        }

        plan.rows = rows
        plan.firstPayment = rows.first?.payment ?? 0
        plan.lastPayment = rows.last?.payment ?? 0
        return plan
    }

    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    static func money2(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }
}

// MARK: - 頁面

struct LoanView: View {
    @EnvironmentObject var store: AppStore
    @State private var principalText = "8,000,000"
    @State private var rateText = "2.15"
    @State private var monthsText = "360"
    @State private var graceText = "0"
    @State private var method: LoanMethod = .equalPayment
    @State private var showAll = false

    private let accent = TT.indigo

    private var principal: Double { LoanView.parse(principalText) }
    private var rate: Double { LoanView.parse(rateText) }
    private var months: Int { max(Int(LoanView.parse(monthsText)), 0) }
    private var grace: Int { max(Int(LoanView.parse(graceText)), 0) }

    private var plan: LoanPlan {
        LoanMath.compute(principal: principal, annualRate: rate,
                         months: months, graceMonths: grace, method: method)
    }

    private var visibleRows: [LoanRow] {
        showAll ? plan.rows : Array(plan.rows.prefix(12))
    }

    var body: some View {
        TTScreen(title: "貸款試算",
                 subtitle: "LOAN CALCULATOR",
                 badge: months > 0 ? "\(months) 期" : nil,
                 badgeOn: true,
                 accent: accent) {

            presetBlock
            inputBlock
            methodBlock
            if months > 0 && principal > 0 {
                resultBlock
                scheduleBlock
            } else {
                TTEmptyHint(icon: "percent", text: "填入本金、利率與期數就會算出每月要繳多少")
            }
            noteBlock
        }
        .onAppear { store.bumpTask("tophat", add: 1) }
    }

    // MARK: 情境

    private var presetBlock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                presetChip("房貸 30 年", principal: "8,000,000", rate: "2.15", months: "360", grace: "0")
                presetChip("車貸 5 年", principal: "800,000", rate: "3.50", months: "60", grace: "0")
                presetChip("信貸 7 年", principal: "500,000", rate: "6.20", months: "84", grace: "0")
                presetChip("分期 12 期", principal: "36,000", rate: "0", months: "12", grace: "0")
                presetChip("寬限期 2 年", principal: "8,000,000", rate: "2.15", months: "360", grace: "24")
            }
            .padding(.vertical, 2)
        }
    }

    private func presetChip(_ title: String, principal: String, rate: String,
                            months: String, grace: String) -> some View {
        Button {
            principalText = principal
            rateText = rate
            monthsText = months
            graceText = grace
            showAll = false
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule().fill(Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule().strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 輸入

    private var inputBlock: some View {
        TTPanel(accent: accent) {
            VStack(spacing: 12) {
                TTSectionTitle(text: "條件", accent: accent)

                field(title: "本金", placeholder: "8000000", text: $principalText, unit: "元", decimal: false)
                field(title: "年利率", placeholder: "2.15", text: $rateText, unit: "%", decimal: true)
                field(title: "期數", placeholder: "360", text: $monthsText, unit: "期（月）", decimal: false)
                field(title: "寬限期", placeholder: "0", text: $graceText, unit: "期（只繳息）", decimal: false)
            }
        }
    }

    private func field(title: String, placeholder: String,
                       text: Binding<String>, unit: String, decimal: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 56, alignment: .leading)

            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

            Text(unit)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 62, alignment: .leading)
        }
    }

    // MARK: 還款方式

    private var methodBlock: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                ForEach(LoanMethod.allCases) { item in
                    Button {
                        method = item
                        showAll = false
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(method == item ? TT.ink : .white.opacity(0.5))
                            Text(item.note)
                                .font(.system(size: 9))
                                .foregroundStyle(method == item ? TT.ink.opacity(0.6) : .white.opacity(0.25))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(method == item ? AnyShapeStyle(accent) : AnyShapeStyle(Color.white.opacity(0.05)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 結果

    private var resultBlock: some View {
        VStack(spacing: 12) {
            TTPanel(accent: accent) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(grace > 0 ? "寬限期後每月繳" : "每月繳")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.32))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("$")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.7))
                        Text(LoanMath.money(plan.firstPayment))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("元")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer(minLength: 0)
                    }

                    if method == .equalPrincipal, plan.firstPayment != plan.lastPayment {
                        Text("末期降至 $\(LoanMath.money(plan.lastPayment)) 元")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.38))
                    } else if grace > 0 {
                        Text("前 \(grace) 期只繳利息，每期約 $\(LoanMath.money(plan.rows.first?.payment ?? 0)) 元")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
            }

            HStack(spacing: 10) {
                TTStat(title: "總利息", value: LoanMath.money(plan.totalInterest), unit: "元", accent: TT.rose)
                TTStat(title: "總還款", value: LoanMath.money(plan.totalPayment), unit: "元", accent: TT.teal)
            }

            HStack(spacing: 10) {
                TTStat(title: "利息佔比", value: String(format: "%.1f", plan.interestRatio * 100), unit: "%", accent: TT.amber)
                TTStat(title: "每萬元月付", value: String(format: "%.0f", plan.firstPayment / max(principal / 10000, 1)), unit: "元", accent: TT.mint)
            }

            TTPanel(accent: TT.rose) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("利息佔比")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer(minLength: 0)
                        Text("\(LoanMath.money(plan.totalInterest)) / \(LoanMath.money(plan.totalPayment))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    TTMeterBar(ratio: plan.interestRatio, accent: TT.rose, height: 8)
                }
            }
        }
    }

    // MARK: 攤還表

    private var scheduleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TTSectionTitle(text: "攤還表", accent: TT.mint)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(showAll ? "只看前 12 期" : "展開全部 \(plan.rows.count) 期")
                        .font(.system(size: 10.5))
                        .foregroundStyle(TT.mint.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            TTPanel(accent: TT.mint, padding: 12) {
                VStack(spacing: 0) {
                    HStack {
                        Text("期").frame(width: 34, alignment: .leading)
                        Text("本金").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("利息").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("餘額").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 8)

                    ForEach(visibleRows) { row in
                        HStack {
                            Text("\(row.period)")
                                .frame(width: 34, alignment: .leading)
                                .foregroundStyle(.white.opacity(0.35))
                            Text(LoanMath.money(row.principal))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(LoanMath.money(row.interest))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(TT.rose.opacity(0.85))
                            Text(LoanMath.money(row.balance))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: 說明

    private var noteBlock: some View {
        TTPanel(accent: TT.amber) {
            VStack(alignment: .leading, spacing: 7) {
                TTSectionTitle(text: "算的是什麼", accent: TT.amber)
                Text("用標準年金公式逐期攤還，本金平均則每期固定還本。實際銀行會另收開辦費、帳管費、信用查詢費，並以日計息到小數點，數字會有幾十到幾百元的差距。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func parse(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }
}
