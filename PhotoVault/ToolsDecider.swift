import SwiftUI
import UIKit

// MARK: - 儲存的抽選規則

struct DecisionSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var options: [String]
    var savedAt = Date()
}

// MARK: - 頁面

struct DecisionEngineView: View {
    @State private var mode = 0

    @State private var optionsText = ""
    @State private var result = ""
    @State private var rolling = false

    @State private var drawCount = 1
    @State private var picked: [String] = []
    @State private var shuffledList: [String] = []

    @State private var diceSides = 6
    @State private var diceCount = 1
    @State private var diceValues: [Int] = []

    @State private var numberMin = "1"
    @State private var numberMax = "100"
    @State private var numberCount = 1
    @State private var uniqueNumbers = true
    @State private var numberValues: [Int] = []

    @State private var saveName = ""
    @State private var sets: [DecisionSet] = []
    @State private var savedFlash = false

    private let modes = ["抽一個", "抽籤", "洗牌", "骰子", "數字"]
    private let storeKey = "md.decision.sets"
    private let diceOptions = [4, 6, 8, 10, 12, 20, 100]

    private var options: [String] {
        optionsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        TTScreen(title: "隨機決策",
                 subtitle: "DECISION ENGINE",
                 badge: "\(options.count) 選項",
                 badgeOn: options.count > 0,
                 accent: TT.violet) {

            modeBlock
            optionsBlock

            switch mode {
            case 0: oneBlock
            case 1: drawBlock
            case 2: shuffleBlock
            case 3: diceBlock
            default: numberBlock
            }

            saveBlock
        }
        .onAppear(perform: loadSets)
    }

    // MARK: 模式

    private var modeBlock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(modes.enumerated()), id: \.offset) { index, title in
                    Button {
                        mode = index
                        result = ""
                        picked = []
                        shuffledList = []
                        diceValues = []
                        numberValues = []
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(mode == index ? TT.ink : Color.white.opacity(0.55))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(
                                Capsule().fill(mode == index
                                               ? AnyShapeStyle(LinearGradient(colors: [TT.violet, TT.indigo],
                                                                              startPoint: .leading,
                                                                              endPoint: .trailing))
                                               : AnyShapeStyle(Color.white.opacity(0.05)))
                            )
                            .overlay(Capsule().strokeBorder(Color.white.opacity(mode == index ? 0 : 0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: 選項

    private var optionsBlock: some View {
        TTPanel(accent: TT.violet) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("選項（一行一個）")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text("\(options.count) 個")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.26))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $optionsText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 108)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(TT.violet.opacity(0.22), lineWidth: 1)
                        )
                    if optionsText.isEmpty {
                        Text("拉麵\n壽司\n火鍋\n隨便")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(.horizontal, 14)
                            .padding(.top, 13)
                            .allowsHitTesting(false)
                    }
                }

                if mode == 4 {
                    Text("這個模式不吃上面的選項，直接填範圍就好")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.24))
                }
            }
        }
    }

    // MARK: 抽一個

    private var oneBlock: some View {
        VStack(spacing: 12) {
            TTPanel(accent: TT.violet) {
                VStack(spacing: 10) {
                    Text(result.isEmpty ? "按下面開始" : result)
                        .font(.system(size: result.count > 10 ? 24 : 30, weight: .bold, design: .rounded))
                        .foregroundStyle(result.isEmpty ? Color.white.opacity(0.25) : TT.mint)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 86)
                        .animation(.easeOut(duration: 0.12), value: result)
                }
            }

            TTButton(title: rolling ? "抽選中…" : "抽出一個",
                     icon: "dice.fill",
                     accent: TT.violet,
                     enabled: !rolling && options.count >= 1) {
                drawOne()
            }
        }
    }

    // MARK: 抽籤

    private var drawBlock: some View {
        VStack(spacing: 12) {
            TTPanel(accent: TT.indigo) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("抽幾個")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("\(min(max(drawCount, 1), max(options.count, 1)))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(TT.indigo)
                    }
                    Slider(value: Binding(
                        get: { Double(min(max(drawCount, 1), max(options.count, 1))) },
                        set: { drawCount = Int($0.rounded()) }
                    ), in: 1...Double(max(options.count, 2)), step: 1)
                    .tint(TT.indigo)

                    Text("不重複抽出，順序隨機")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.24))
                }
            }

            if !picked.isEmpty {
                TTPanel(accent: TT.mint) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("抽中")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.35))
                        ForEach(Array(picked.enumerated()), id: \.offset) { index, name in
                            HStack(spacing: 9) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(TT.ink)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(TT.mint.opacity(0.85)))
                                Text(name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }

            TTButton(title: "抽出",
                     icon: "hand.draw.fill",
                     accent: TT.indigo,
                     enabled: options.count >= 1) {
                let count = min(max(drawCount, 1), options.count)
                picked = Array(options.shuffled().prefix(count))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: 洗牌

    private var shuffleBlock: some View {
        VStack(spacing: 12) {
            if !shuffledList.isEmpty {
                TTPanel(accent: TT.teal) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("洗牌結果")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.35))
                        ForEach(Array(shuffledList.enumerated()), id: \.offset) { index, name in
                            HStack(spacing: 9) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(TT.teal)
                                    .frame(width: 22, alignment: .leading)
                                Text(name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.88))
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            } else {
                TTPanel(accent: TT.teal) {
                    TTEmptyHint(icon: "shuffle", text: "把上面的選項打散\n決定順序、排隊、抽獎順位都好用")
                }
            }

            TTButton(title: "重新洗牌", icon: "shuffle", accent: TT.teal, enabled: options.count >= 2) {
                shuffledList = options.shuffled()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: 骰子

    private var diceBlock: some View {
        VStack(spacing: 12) {
            TTPanel(accent: TT.amber) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("面數")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(diceOptions, id: \.self) { sides in
                                Button {
                                    diceSides = sides
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Text("D\(sides)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(diceSides == sides ? TT.ink : Color.white.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(
                                            Capsule().fill(diceSides == sides
                                                           ? AnyShapeStyle(TT.amber)
                                                           : AnyShapeStyle(Color.white.opacity(0.05)))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }

                    HStack {
                        Text("顆數")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Stepper("\(diceCount)", value: $diceCount, in: 1...8)
                            .labelsHidden()
                        Text("\(diceCount)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(TT.amber)
                            .frame(width: 22)
                    }
                }
            }

            if !diceValues.isEmpty {
                TTPanel(accent: TT.mint) {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(Array(diceValues.enumerated()), id: \.offset) { _, value in
                                Text("\(value)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .frame(minWidth: 40)
                                    .frame(height: 46)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(TT.mint.opacity(0.14))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(TT.mint.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        if diceValues.count > 1 {
                            Text("總和 \(diceValues.reduce(0, +))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TT.mint)
                        }
                    }
                }
            }

            TTButton(title: "擲骰子", icon: "die.face.5", accent: TT.amber, enabled: true) {
                diceValues = (0..<diceCount).map { _ in Int.random(in: 1...diceSides) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: 數字

    private var numberBlock: some View {
        VStack(spacing: 12) {
            TTPanel(accent: TT.blue) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        numberField("最小", text: $numberMin)
                        numberField("最大", text: $numberMax)
                    }

                    HStack {
                        Text("取幾個")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Stepper("\(numberCount)", value: $numberCount, in: 1...20)
                            .labelsHidden()
                        Text("\(numberCount)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(TT.blue)
                            .frame(width: 24)
                    }

                    HStack {
                        Text("不重複")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Toggle("", isOn: $uniqueNumbers)
                            .labelsHidden()
                            .tint(TT.blue)
                    }
                }
            }

            if !numberValues.isEmpty {
                TTPanel(accent: TT.mint) {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ForEach(Array(numberValues.enumerated()), id: \.offset) { _, value in
                                Text("\(value)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .frame(minWidth: 48)
                                    .frame(height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(TT.blue.opacity(0.14))
                                    )
                            }
                        }
                        if numberValues.count > 1 {
                            Text("合計 \(numberValues.reduce(0, +))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TT.mint)
                        }
                    }
                }
            }

            TTButton(title: "產生數字", icon: "number", accent: TT.blue, enabled: range != nil) {
                generateNumbers()
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            TextField("0", text: text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .keyboardType(.numbersAndPunctuation)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    private var range: ClosedRange<Int>? {
        guard let low = Int(numberMin.trimmingCharacters(in: .whitespaces)),
              let high = Int(numberMax.trimmingCharacters(in: .whitespaces)),
              low <= high else { return nil }
        return low...high
    }

    private func generateNumbers() {
        guard let range = range else { return }
        var values: [Int] = []
        if uniqueNumbers {
            let span = range.upperBound - range.lowerBound + 1
            let count = min(max(numberCount, 1), span)
            var pool = Array(range)
            pool.shuffle()
            values = Array(pool.prefix(count))
        } else {
            values = (0..<max(numberCount, 1)).map { _ in Int.random(in: range) }
        }
        numberValues = values
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: 儲存規則

    private var saveBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "儲存抽選規則", accent: TT.mint)

            TTPanel(accent: TT.mint) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("例如：午餐吃什麼", text: $saveName)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )

                        Button {
                            saveCurrent()
                        } label: {
                            Text(savedFlash ? "已存" : "儲存")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TT.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(options.count >= 2 ? TT.mint : Color.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(options.count < 2)
                    }

                    if sets.isEmpty {
                        Text("還沒有儲存的規則")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.24))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.05))
                                        .frame(height: 1)
                                }
                                HStack(spacing: 10) {
                                    Button {
                                        saveName = set.name
                                        optionsText = set.options.joined(separator: "\n")
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(set.name)
                                                .font(.system(size: 12.5, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.88))
                                            Text("\(set.options.count) 個選項")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(.white.opacity(0.25))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        deleteSet(set)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(TT.rose.opacity(0.7))
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 資料

    private func saveCurrent() {
        guard options.count >= 2 else { return }
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "未命名規則" : name

        if let index = sets.firstIndex(where: { $0.name == finalName }) {
            sets[index].options = options
            sets[index].savedAt = Date()
        } else {
            sets.insert(DecisionSet(name: finalName, options: options), at: 0)
        }
        if sets.count > 20 { sets = Array(sets.prefix(20)) }
        persist()
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { savedFlash = false }
        }
    }

    private func deleteSet(_ set: DecisionSet) {
        sets.removeAll { $0.id == set.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func loadSets() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let list = try? JSONDecoder().decode([DecisionSet].self, from: data) else { return }
        sets = list
    }

    private func drawOne() {
        let list = options
        guard !list.isEmpty, !rolling else { return }
        rolling = true
        result = ""

        Task {
            for _ in 0..<14 {
                await MainActor.run { result = list.randomElement() ?? "" }
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            await MainActor.run {
                result = list.randomElement() ?? ""
                rolling = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}
