import SwiftUI
import UIKit

// MARK: - 大數進制運算（不依賴 Int，任意長度）

enum BaseMath {

    static func digitValue(_ ch: Character) -> Int? {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return nil }
        let value = scalar.value
        if value >= 48 && value <= 57 { return Int(value - 48) }
        if value >= 65 && value <= 90 { return Int(value - 55) }
        if value >= 97 && value <= 122 { return Int(value - 87) }
        return nil
    }

    static func charFor(_ value: Int) -> Character {
        if value < 10 { return Character(String(value)) }
        if let scalar = UnicodeScalar(55 + value) { return Character(scalar) }
        return "0"
    }

    /// 字串 → 十進位大數（低位在前）。非法字元或超出進位範圍回傳 nil
    static func parse(_ text: String, base: Int) -> [Int]? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, base >= 2, base <= 36 else { return nil }

        var digits = [0]
        for ch in cleaned {
            guard let value = digitValue(ch), value < base else { return nil }
            var carry = value
            for i in 0..<digits.count {
                let total = digits[i] * base + carry
                digits[i] = total % 10
                carry = total / 10
            }
            while carry > 0 {
                digits.append(carry % 10)
                carry /= 10
            }
        }
        while digits.count > 1 && digits.last == 0 { digits.removeLast() }
        return digits
    }

    /// 十進位大數 → 指定進位字串
    static func render(_ digits: [Int], base: Int) -> String {
        guard base >= 2, base <= 36 else { return "—" }
        if digits.count == 1 && digits[0] == 0 { return "0" }

        var current = digits
        var output: [Character] = []

        while !(current.count == 1 && current[0] == 0) {
            var remainder = 0
            var quotient: [Int] = []
            for value in current.reversed() {
                let cur = remainder * 10 + value
                let q = cur / base
                remainder = cur % base
                if !quotient.isEmpty || q != 0 { quotient.append(q) }
            }
            output.append(charFor(remainder))
            current = quotient.isEmpty ? [0] : Array(quotient.reversed())
        }

        return String(output.reversed())
    }

    static func convert(_ text: String, from: Int, to: Int) -> String? {
        guard let digits = parse(text, base: from) else { return nil }
        return render(digits, base: to)
    }

    static func group(_ text: String, size: Int = 4) -> String {
        guard text.count > size else { return text }
        var out: [String] = []
        var buffer = ""
        for ch in text {
            buffer.append(ch)
            if buffer.count == size {
                out.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { out.append(buffer) }
        return out.joined(separator: " ")
    }

    /// 二進位有效位元長度
    static func bitLength(_ binary: String) -> Int {
        let trimmed = binary.drop { $0 == "0" }
        return trimmed.isEmpty ? 1 : trimmed.count
    }
}

// MARK: - 資料大小

enum ByteUnit: String, CaseIterable, Identifiable {
    case bit, byte, kb, mb, gb, tb
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bit:  return "bit"
        case .byte: return "B"
        case .kb:   return "KB"
        case .mb:   return "MB"
        case .gb:   return "GB"
        case .tb:   return "TB"
        }
    }

    var bytesFactor: Double {
        switch self {
        case .bit:  return 1.0 / 8.0
        case .byte: return 1
        case .kb:   return 1024
        case .mb:   return 1024 * 1024
        case .gb:   return 1024 * 1024 * 1024
        case .tb:   return 1024 * 1024 * 1024 * 1024
        }
    }
}

// MARK: - 頁面

struct BaseConvertView: View {
    @State private var raw = ""
    @State private var inputBase = 10
    @State private var uppercase = true

    @State private var sizeValue = ""
    @State private var sizeUnit: ByteUnit = .mb
    @State private var binaryUnits = false

    @State private var opA = ""
    @State private var opB = ""
    @State private var operatorKind = 0
    @State private var shift = "1"

    @State private var copiedKey: String?

    private let bases = [2, 8, 10, 16]
    private let operators = ["AND", "OR", "XOR", "NOT", "左移", "右移"]

    var body: some View {
        TTScreen(title: "進制轉換",
                 subtitle: "BASE CONVERTER",
                 badge: inputBase == 10 ? "DEC" : "BASE \(inputBase)",
                 badgeOn: true,
                 accent: TT.amber) {

            convertBlock
            sizeBlock
            bitwiseBlock

            TTPanel(accent: TT.teal, padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("說明")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("轉換用大數演算法，位數再長也不會溢位；十六進位可以貼 0x 以外的純數字或 A–F。位元運算以 64 位元無號整數處理。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 進制互轉

    private var convertBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "進制互轉", accent: TT.amber)

            TTPanel(accent: TT.amber) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        ForEach(bases, id: \.self) { base in
                            Button {
                                inputBase = base
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text("\(base)")
                                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(inputBase == base ? TT.ink : Color.white.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(inputBase == base
                                                  ? AnyShapeStyle(LinearGradient(colors: [TT.amber, TT.rose],
                                                                                 startPoint: .leading,
                                                                                 endPoint: .trailing))
                                                  : AnyShapeStyle(Color.white.opacity(0.05)))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField(placeholderForBase, text: $raw)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white)
                        .keyboardType(inputBase == 10 ? .numberPad : .default)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(TT.amber.opacity(0.25), lineWidth: 1)
                        )

                    if !raw.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                        Text("這個輸入有 \(inputBase) 進位不認得的字元，檢查一下")
                            .font(.system(size: 10.5))
                            .foregroundStyle(TT.rose.opacity(0.9))
                    }

                    VStack(spacing: 9) {
                        resultRow("二進位", "BIN", results["2"] ?? "—", key: "2")
                        resultRow("八進位", "OCT", results["8"] ?? "—", key: "8")
                        resultRow("十進位", "DEC", results["10"] ?? "—", key: "10")
                        resultRow("十六進位", "HEX", results["16"] ?? "—", key: "16")
                    }

                    if let binary = results["2"], !binary.isEmpty, binary != "—" {
                        HStack(spacing: 8) {
                            TTPill(text: "位元長度 \(BaseMath.bitLength(binary))")
                            TTPill(text: "位元組 \(max(1, Int(ceil(Double(BaseMath.bitLength(binary)) / 8.0))))",
                                   color: TT.teal)
                            Spacer(minLength: 0)
                            Toggle("", isOn: $uppercase)
                                .labelsHidden()
                                .tint(TT.amber)
                        }
                    }
                }
            }
        }
    }

    private var placeholderForBase: String {
        switch inputBase {
        case 2:  return "例如 10110100"
        case 8:  return "例如 264"
        case 16: return "例如 FF2A"
        default: return "例如 65535"
        }
    }

    private var results: [String: String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let digits = BaseMath.parse(text, base: inputBase) else { return [:] }
        var out: [String: String] = [:]
        for base in bases {
            var value = BaseMath.render(digits, base: base)
            if base == 16 && !uppercase { value = value.lowercased() }
            out["\(base)"] = value
        }
        return out
    }

    private func resultRow(_ title: String, _ en: String, _ value: String, key: String) -> some View {
        Button {
            guard value != "—" else { return }
            UIPasteboard.general.string = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation { copiedKey = key }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation { copiedKey = nil }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(en)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.2))
                }
                .frame(width: 58, alignment: .leading)

                Text(value)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if copiedKey == key {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TT.mint)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 資料大小

    private var sizeBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "資料大小換算", accent: TT.teal)

            TTPanel(accent: TT.teal) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("1024", text: $sizeValue)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.white)
                            .keyboardType(.decimalPad)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        Picker("", selection: $sizeUnit) {
                            ForEach(ByteUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(TT.teal)
                    }

                    HStack {
                        Text("用 1024 進位（KiB / MiB）")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Toggle("", isOn: $binaryUnits)
                            .labelsHidden()
                            .tint(TT.teal)
                    }

                    VStack(spacing: 0) {
                        ForEach(ByteUnit.allCases) { unit in
                            HStack {
                                Text(unit.title)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .frame(width: 44, alignment: .leading)
                                Text(sizeText(for: unit))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var sizeBaseBytes: Double? {
        guard let number = Double(sizeValue.trimmingCharacters(in: .whitespaces)) else { return nil }
        let factor = binaryUnits ? sizeUnit.bytesFactor : decimalFactor(sizeUnit)
        return number * factor
    }

    private func decimalFactor(_ unit: ByteUnit) -> Double {
        switch unit {
        case .bit:  return 1.0 / 8.0
        case .byte: return 1
        case .kb:   return 1000
        case .mb:   return 1000 * 1000
        case .gb:   return 1000 * 1000 * 1000
        case .tb:   return 1000 * 1000 * 1000 * 1000
        }
    }

    private func sizeText(for unit: ByteUnit) -> String {
        guard let bytes = sizeBaseBytes else { return "—" }
        let factor = binaryUnits ? unit.bytesFactor : decimalFactor(unit)
        guard factor > 0 else { return "—" }
        let value = bytes / factor
        if value == 0 { return "0 \(unit.title)" }
        if value >= 1 {
            return String(format: "%.4f \(unit.title)", value)
        }
        return String(format: "%.6f \(unit.title)", value)
    }

    // MARK: 位元運算

    private var bitwiseBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "位元運算", accent: TT.violet)

            TTPanel(accent: TT.violet) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        bitField("數值 A", text: $opA)
                        bitField("數值 B", text: $opB)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Array(operators.enumerated()), id: \.offset) { index, name in
                                Button {
                                    operatorKind = index
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Text(name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(operatorKind == index ? TT.ink : Color.white.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .frame(height: 32)
                                        .background(
                                            Capsule().fill(operatorKind == index
                                                           ? AnyShapeStyle(TT.violet)
                                                           : AnyShapeStyle(Color.white.opacity(0.05)))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }

                    if operatorKind >= 4 {
                        HStack(spacing: 8) {
                            Text("位移量")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                            TextField("1", text: $shift)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                            Spacer(minLength: 0)
                        }
                    }

                    VStack(spacing: 0) {
                        TTKeyRow(key: "十進位", value: bitwiseResult.dec, accent: TT.violet, mono: true)
                        TTKeyRow(key: "十六進位", value: bitwiseResult.hex, accent: TT.violet, mono: true)
                        TTKeyRow(key: "二進位", value: bitwiseResult.bin, accent: TT.violet, mono: true)
                    }
                }
            }
        }
    }

    private func bitField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            TextField("0 或 0xFF", text: text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    private var bitwiseResult: (dec: String, hex: String, bin: String) {
        guard let a = parseInteger(opA) else { return ("—", "—", "—") }
        let b = parseInteger(opB) ?? 0
        let shiftValue = UInt64(shift.trimmingCharacters(in: .whitespaces)) ?? 1

        var result: UInt64 = 0
        switch operatorKind {
        case 0: result = a & b
        case 1: result = a | b
        case 2: result = a ^ b
        case 3: result = ~a
        case 4: result = shiftValue >= 64 ? 0 : (a << shiftValue)
        case 5: result = shiftValue >= 64 ? 0 : (a >> shiftValue)
        default: result = a
        }

        let dec = String(result)
        let hex = String(result, radix: 16, uppercase: true)
        let bin = String(result, radix: 2)
        return (dec, hex, BaseMath.group(bin))
    }

    private func parseInteger(_ text: String) -> UInt64? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("0X") { value = String(value.dropFirst(2)); return UInt64(value, radix: 16) }
        if value.hasPrefix("0B") { value = String(value.dropFirst(2)); return UInt64(value, radix: 2) }
        if let decimal = UInt64(value) { return decimal }
        return UInt64(value, radix: 16)
    }
}
