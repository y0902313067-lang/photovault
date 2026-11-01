import SwiftUI
import AVFoundation
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

// MARK: - 語言

struct TranslateLanguage: Identifiable, Hashable {
    let id: String          // BCP-47，auto 代表自動偵測
    let name: String        // 繁體名稱
    let short: String       // 兩三字縮寫

    static let auto = TranslateLanguage(id: "auto", name: "自動偵測", short: "自動")

    static let all: [TranslateLanguage] = [
        auto,
        TranslateLanguage(id: "zh-Hant", name: "繁體中文", short: "繁"),
        TranslateLanguage(id: "zh-Hans", name: "簡體中文", short: "簡"),
        TranslateLanguage(id: "en", name: "英文", short: "EN"),
        TranslateLanguage(id: "ja", name: "日文", short: "日"),
        TranslateLanguage(id: "ko", name: "韓文", short: "韓"),
        TranslateLanguage(id: "fr", name: "法文", short: "FR"),
        TranslateLanguage(id: "de", name: "德文", short: "DE"),
        TranslateLanguage(id: "es", name: "西班牙文", short: "ES"),
        TranslateLanguage(id: "it", name: "義大利文", short: "IT"),
        TranslateLanguage(id: "pt-BR", name: "葡萄牙文", short: "PT"),
        TranslateLanguage(id: "ru", name: "俄文", short: "RU"),
        TranslateLanguage(id: "ar", name: "阿拉伯文", short: "AR"),
        TranslateLanguage(id: "hi", name: "印地文", short: "HI"),
        TranslateLanguage(id: "th", name: "泰文", short: "TH"),
        TranslateLanguage(id: "vi", name: "越南文", short: "VI"),
        TranslateLanguage(id: "id", name: "印尼文", short: "ID"),
        TranslateLanguage(id: "tr", name: "土耳其文", short: "TR"),
        TranslateLanguage(id: "nl", name: "荷蘭文", short: "NL"),
        TranslateLanguage(id: "pl", name: "波蘭文", short: "PL"),
        TranslateLanguage(id: "uk", name: "烏克蘭文", short: "UK")
    ]

    static func named(_ id: String) -> TranslateLanguage {
        all.first { $0.id == id } ?? auto
    }
}

// MARK: - 主頁

struct TranslateView: View {
    var body: some View {
        TTScreen(title: "文字翻譯",
                 subtitle: "ON-DEVICE TRANSLATOR",
                 accent: TT.mint) {
            #if canImport(Translation)
            if #available(iOS 18.0, *) {
                TranslatorCore()
            } else {
                unsupportedCard
            }
            #else
            unsupportedCard
            #endif
        }
    }

    private var unsupportedCard: some View {
        TTPanel(accent: TT.amber) {
            VStack(spacing: 12) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(TT.amber)
                Text("此裝置暫不支援")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("文字翻譯使用系統內建的離線翻譯引擎，需要 iOS 18 或以上。其餘工具不受影響。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 翻譯核心

#if canImport(Translation)
@available(iOS 18.0, *)
struct TranslatorCore: View {
    @State private var input = ""
    @State private var output = ""
    @State private var source: TranslateLanguage = .auto
    @State private var target: TranslateLanguage = .named("zh-Hant")
    @State private var detected: TranslateLanguage?
    @State private var configuration: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var errorText: String?
    @State private var copied = false
    @State private var speaking = false
    @State private var picker: PickerSide?

    @FocusState private var inputFocused: Bool

    @State private var synth = AVSpeechSynthesizer()
    private let maxChars = 2000

    private enum PickerSide: String, Identifiable {
        case source, target
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 14) {
            languageBar
            inputCard
            actionRow
            if let errorText {
                errorCard(errorText)
            }
            outputCard
            privacyNote
        }
        .translationTask(configuration) { session in
            await runTranslation(session)
        }
        .sheet(item: $picker) { side in
            LanguagePickerView(
                title: side == .source ? "翻譯來源" : "翻譯成",
                allowsAuto: side == .source,
                selected: side == .source ? source : target
            ) { picked in
                if side == .source {
                    source = picked
                } else {
                    target = picked
                }
                if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startTranslate()
                }
            }
        }
    }

    // MARK: 語言列

    private var languageBar: some View {
        HStack(spacing: 10) {
            languageButton(title: source.name,
                           caption: source == .auto
                           ? (detected.map { "偵測為 \($0.name)" } ?? "自動判斷語言")
                           : "來源",
                           accent: TT.teal) {
                picker = .source
            }

            Button {
                let old = source
                source = target
                target = old == .auto ? .named("en") : old
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startTranslate()
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TT.mint)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        Circle().strokeBorder(TT.mint.opacity(0.28), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            languageButton(title: target.name,
                           caption: "譯文語言",
                           accent: TT.mint) {
                picker = .target
            }
        }
    }

    private func languageButton(title: String,
                                caption: String,
                                accent: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(accent.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.35),
                                                Color.white.opacity(0.04)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 輸入

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("原文")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.3))
                Spacer(minLength: 0)
                Text("\(input.count) / \(maxChars)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.22))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("輸入或貼上要翻譯的文字…")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.22))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $input)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($inputFocused)
                    .frame(minHeight: 108, maxHeight: 190)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .onChange(of: input) { newValue in
                        if newValue.count > maxChars {
                            input = String(newValue.prefix(maxChars))
                        }
                        errorText = nil
                    }
            }

            HStack(spacing: 10) {
                Button {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        input = String(text.prefix(maxChars))
                    }
                } label: {
                    Label("貼上", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    input = ""
                    output = ""
                    detected = nil
                    errorText = nil
                } label: {
                    Label("清除", systemImage: "xmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: 翻譯按鈕

    private var actionRow: some View {
        Button {
            startTranslate()
        } label: {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(TT.ink)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isTranslating ? "翻譯中…" : "翻譯")
                    .font(.system(size: 14.5, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(TT.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [TT.mint, TT.teal, TT.blue],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: TT.mint.opacity(0.28), radius: 18, y: 8)
            .opacity(canTranslate ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canTranslate)
    }

    private var canTranslate: Bool {
        !isTranslating && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: 錯誤

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TT.amber)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(TT.amber.opacity(0.08))
        )
    }

    // MARK: 譯文

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("譯文")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.3))
                if let detected, source == .auto {
                    Text(detected.short)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(TT.teal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(TT.teal.opacity(0.14)))
                }
                Rectangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.08),
                                                  .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                Text(target.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(TT.mint.opacity(0.65))
            }

            if output.isEmpty {
                TTEmptyHint(icon: "text.bubble",
                            text: isTranslating ? "正在翻譯…" : "譯文會顯示在這裡")
                    .padding(.vertical, 4)
            } else {
                Text(output)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 18) {
                    toolButton(copied ? "已複製" : "複製",
                               icon: copied ? "checkmark.circle.fill" : "doc.on.doc") {
                        UIPasteboard.general.string = output
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    }

                    toolButton(speaking ? "朗讀中" : "朗讀",
                               icon: speaking ? "speaker.wave.3.fill" : "speaker.wave.2") {
                        speak(output)
                    }

                    toolButton("分享", icon: "square.and.arrow.up") {
                        UIPasteboard.general.string = output
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(colors: [TT.mint.opacity(0.07),
                                            Color.white.opacity(0.03)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [TT.mint.opacity(0.3),
                                            Color.white.opacity(0.05)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
    }

    private func toolButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(TT.mint.opacity(0.9))
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 9))
            Text("翻譯由系統離線引擎處理，文字不上傳")
                .font(.system(size: 9.5))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.2))
        .padding(.top, 2)
    }

    // MARK: 動作

    private func startTranslate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        inputFocused = false

        var sourceLanguage: Locale.Language?
        if source == .auto {
            if let guessed = Self.detectLanguage(text) {
                sourceLanguage = guessed.language
                detected = guessed.matched
            } else {
                sourceLanguage = Locale.Language(identifier: "en")
                detected = nil
            }
        } else {
            sourceLanguage = Locale.Language(identifier: source.id)
            detected = nil
        }
        let targetLanguage = Locale.Language(identifier: target.id)

        isTranslating = true
        output = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) {
            if isTranslating {
                isTranslating = false
                errorText = "翻譯逾時沒有回應，請再點一次。第一次使用某個語言時，系統會先下載語言包。"
            }
        }
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: sourceLanguage,
                                                             target: targetLanguage)
        } else {
            configuration?.invalidate()
            configuration = TranslationSession.Configuration(source: sourceLanguage,
                                                             target: targetLanguage)
        }
    }

    @MainActor
    private func runTranslation(_ session: TranslationSession) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            isTranslating = false
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let response = try await session.translate(text)
            output = response.targetText
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorText = friendly(error)
        }
    }

    static func detectLanguage(_ text: String) -> (language: Locale.Language, matched: TranslateLanguage?)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let raw = dominant.rawValue
        let matched = TranslateLanguage.all.first { item in
            item != .auto && item.id.lowercased() == raw.lowercased()
        } ?? TranslateLanguage.all.first { item in
            item != .auto && item.id.lowercased().hasPrefix(String(raw.lowercased().prefix(2)))
        }
        return (Locale.Language(identifier: raw), matched)
    }

    private func friendly(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("unsupported") || text.contains("not supported") {
            return "這組語言系統不支援，換一個語言試試。"
        }
        if text.contains("cancel") {
            return "語言包沒有下載，無法翻譯。到「設定 → 一般 → 語言與地區」可查看已安裝的語言。"
        }
        return "翻譯沒有完成，請再試一次。如果一直失敗，換一組語言或重開 App。"
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
            speaking = false
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: target.id)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
        speaking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2.0, Double(text.count) * 0.12)) {
            speaking = false
        }
    }
}

// MARK: - 語言選擇器

struct LanguagePickerView: View {
    let title: String
    let allowsAuto: Bool
    let selected: TranslateLanguage
    let onPick: (TranslateLanguage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var list: [TranslateLanguage] {
        let base = TranslateLanguage.all.filter { item in
            item != .auto || allowsAuto
        }
        guard !query.isEmpty else { return base }
        return base.filter { $0.name.contains(query) || $0.id.lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                TechGrid()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(list) { item in
                            Button {
                                onPick(item)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(item.short)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(item == selected ? TT.ink : TT.mint)
                                        .frame(width: 38, height: 26)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(item == selected ? TT.mint : TT.mint.opacity(0.12))
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.9))
                                        Text(item.id)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.25))
                                    }
                                    Spacer(minLength: 0)
                                    if item == selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(TT.mint)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 1)
                                .padding(.leading, 66)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜尋語言")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(TT.mint)
                }
            }
        }
    }
}
#endif
