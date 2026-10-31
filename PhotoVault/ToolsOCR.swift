import SwiftUI
import PhotosUI
import Vision
import UIKit

// MARK: - 方向轉換

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

// MARK: - 模型

struct OCRItem: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
}

final class OCRModel: ObservableObject {
    @Published var items: [OCRItem] = []
    @Published var preview: UIImage?
    @Published var busy = false
    @Published var status = "選一張圖，或用相機拍一張"
    @Published var accurate = true
    @Published var autoLanguage = true
    @Published var elapsed: Double = 0
    @Published var regionMode = false
    @Published var codes: [String] = []
    @Published var links: [String] = []

    static func extractLinks(_ text: String) -> [String] {
        let pattern = "(?i)\\b(?:https?://|www\\.)[^\\s，。、；）】」》,;\"']+"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out: [String] = []
        for m in matches {
            var s = ns.substring(with: m.range)
            while let last = s.last, ".,;:)]}，。、".contains(last) {
                s.removeLast()
            }
            if s.count > 4, !out.contains(s) { out.append(s) }
        }
        return out
    }

    var summary: String {
        let text = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let separators = CharacterSet(charactersIn: "。！？!?.\n")
        let sentences = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 }
        var picked: [String] = []
        var total = 0
        for s in sentences {
            if total + s.count > 170 { break }
            picked.append(s)
            total += s.count
            if picked.count >= 5 { break }
        }
        if picked.isEmpty { return String(text.prefix(120)) }
        return picked.joined(separator: "。") + "。"
    }

    var joined: String { items.map(\.text).joined(separator: "\n") }
    var charCount: Int { joined.count }

    var avgConfidence: Double {
        guard !items.isEmpty else { return 0 }
        return Double(items.map(\.confidence).reduce(0, +)) / Double(items.count)
    }

    func run(_ image: UIImage) {
        preview = image
        items = []
        busy = true
        status = "辨識中…"

        let level: VNRequestTextRecognitionLevel = accurate ? .accurate : .fast
        let auto = autoLanguage
        let regions = regionMode
        let start = Date()

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [OCRItem] = []
            var foundCodes: [String] = []
            var errText: String?
            var angle: Double = 0

            if let cg = image.cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = level
                request.usesLanguageCorrection = true
                if #available(iOS 16.0, *) {
                    request.automaticallyDetectsLanguage = auto
                }
                if !auto {
                    request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US", "ja-JP"]
                }
                if regions {
                    request.regionOfInterest = CGRect(x: 0, y: 0, width: 1.0, height: 1.0)
                }

                let handler = VNImageRequestHandler(cgImage: cg,
                                                    orientation: CGImagePropertyOrientation(image.imageOrientation),
                                                    options: [:])
                do {
                    try handler.perform([request])
                    if let observations = request.results {
                        for obs in observations {
                            guard let top = obs.topCandidates(1).first else { continue }
                            results.append(OCRItem(text: top.string, confidence: top.confidence))
                        }
                        if let first = observations.first {
                            angle = atan2(Double(first.boundingBox.height),
                                          Double(first.boundingBox.width)) * 180.0 / Double.pi
                        }
                    }
                } catch {
                    errText = "辨識失敗"
                }

                let barcodeHandler = VNImageRequestHandler(cgImage: cg,
                                                           orientation: CGImagePropertyOrientation(image.imageOrientation),
                                                           options: [:])
                let barcodeRequest = VNDetectBarcodesRequest()
                if (try? barcodeHandler.perform([barcodeRequest])) != nil {
                    foundCodes = (barcodeRequest.results ?? []).compactMap { $0.payloadStringValue }
                }
            } else {
                errText = "無法讀取這張圖片"
            }

            let cost = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                self.items = results
                self.codes = foundCodes
                self.links = OCRModel.extractLinks(results.map(\.text).joined(separator: "\n"))
                self.elapsed = cost
                self.busy = false
                if let e = errText {
                    self.status = e
                } else if results.isEmpty {
                    self.status = "沒有找到文字，換更清楚的圖試試"
                } else {
                    self.status = "辨識完成"
                }
                _ = angle
                UINotificationFeedbackGenerator().notificationOccurred(results.isEmpty ? .warning : .success)
            }
        }
    }

    func clear() {
        items = []
        preview = nil
        status = "選一張圖，或用相機拍一張"
        codes = []
        links = []
        elapsed = 0
    }
}

// MARK: - 相機

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onImage(img)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - 畫面

struct OCRView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = OCRModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var copied = false

    var body: some View {
        TTScreen(title: "文字辨識",
                 subtitle: "ON-DEVICE OCR",
                 badge: model.busy ? "SCANNING" : (model.items.isEmpty ? "IDLE" : "\(model.items.count) LINES"),
                 badgeOn: !model.items.isEmpty,
                 accent: TT.blue) {
            sourceBlock

            if let preview = model.preview {
                TTPanel(accent: TT.blue, padding: 8) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(TT.blue.opacity(0.18), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity)
                }
            }

            optionsBlock

            if model.busy {
                TTPanel(accent: TT.blue) {
                    HStack(spacing: 11) {
                        ProgressView().tint(TT.blue)
                        Text("辨識中，稍等…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                    }
                }
            } else if !model.items.isEmpty {
                statsBlock
                resultBlock
                if !model.links.isEmpty { linksBlock }
                if !model.codes.isEmpty { codesBlock }
                if !model.summary.isEmpty { summaryBlock }
                actionBlock
            } else {
                TTPanel(accent: TT.blue) {
                    TTEmptyHint(icon: "text.viewfinder",
                                text: "支援繁體中文、簡體中文、英文與日文\n全部在手機本機完成，圖片不會上傳")
                }
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        model.run(img)
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { img in
                model.run(img)
            }
            .ignoresSafeArea()
        }
    }

    private var sourceBlock: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 13, weight: .semibold))
                    Text("從相簿選")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(TT.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [TT.blue, TT.indigo],
                                             startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)

            Button {
                showCamera = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("拍攝")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 106)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TT.blue.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var optionsBlock: some View {
        TTPanel(accent: TT.indigo, padding: 14) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("精準模式")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                        Text("慢一點但小字更準；關掉則速度快")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                    Toggle("", isOn: $model.accurate)
                        .labelsHidden()
                        .tint(TT.blue)
                }
                Divider().overlay(Color.white.opacity(0.07))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自動偵測語言")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                        Text("中英日混排時建議開啟")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                    Toggle("", isOn: $model.autoLanguage)
                        .labelsHidden()
                        .tint(TT.blue)
                }
            }
        }
    }

    private var statsBlock: some View {
        HStack(spacing: 10) {
            TTStat(title: "行數", value: "\(model.items.count)", unit: "行", accent: TT.blue)
            TTStat(title: "字數", value: "\(model.charCount)", unit: "字", accent: TT.indigo)
            TTStat(title: "平均信心",
                   value: String(format: "%.0f", model.avgConfidence * 100),
                   unit: "%",
                   accent: model.avgConfidence > 0.6 ? TT.mint : TT.amber)
            TTStat(title: "耗時", value: String(format: "%.1f", model.elapsed), unit: "s", accent: TT.violet)
        }
    }

    private var resultBlock: some View {
        TTPanel(accent: TT.mint, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("辨識結果")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text(model.status)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.28))
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.items) { item in
                        HStack(alignment: .top, spacing: 9) {
                            Text(item.text)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.9))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(Int(item.confidence * 100))")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(confidenceColor(item.confidence).opacity(0.85))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(confidenceColor(item.confidence).opacity(0.12))
                                )
                        }
                        if item.id != model.items.last?.id {
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
    }

    private var linksBlock: some View {
        TTPanel(accent: TT.teal, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TT.teal.opacity(0.8))
                    Text("偵測到 \(model.links.count) 個網址")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
                ForEach(model.links, id: \.self) { link in
                    HStack(spacing: 8) {
                        Button {
                            openString(link)
                        } label: {
                            Text(link)
                                .font(.system(size: 12))
                                .foregroundStyle(TT.teal)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            copyString(link)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var codesBlock: some View {
        TTPanel(accent: TT.indigo, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TT.indigo.opacity(0.85))
                    Text("圖片中的二維碼")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
                ForEach(model.codes, id: \.self) { code in
                    HStack(alignment: .top, spacing: 8) {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            copyString(code)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let first = model.codes.first,
                   first.lowercased().hasPrefix("http") || first.lowercased().hasPrefix("www.") {
                    Button {
                        openString(first)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "safari")
                                .font(.system(size: 11))
                            Text("在瀏覽器打開")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(TT.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryBlock: some View {
        TTPanel(accent: TT.amber, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TT.amber.opacity(0.9))
                    Text("重點摘要 · 本機生成")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button {
                        copyString(model.summary)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                Text(model.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyString(_ s: String) {
        UIPasteboard.general.string = s
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func openString(_ raw: String) {
        var s = raw
        if s.lowercased().hasPrefix("www.") { s = "https://" + s }
        guard let url = URL(string: s), let scheme = url.scheme,
              ["http", "https", "tel", "mailto", "sms"].contains(scheme.lowercased()) else { return }
        UIApplication.shared.open(url)
    }

    private func openTranslate() {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~ ")
        let body = String(model.joined.prefix(1200))
        guard let enc = body.addingPercentEncoding(withAllowedCharacters: cs),
              let url = URL(string: "https://translate.google.com/?sl=auto&tl=zh-TW&text=\(enc)") else { return }
        UIApplication.shared.open(url)
    }

    private func confidenceColor(_ c: Float) -> Color {
        if c > 0.7 { return TT.mint }
        if c > 0.45 { return TT.amber }
        return TT.rose
    }

    private var actionBlock: some View {
        VStack(spacing: 9) {
            TTButton(title: copied ? "已複製全部" : "複製全部文字",
                     icon: copied ? "checkmark" : "doc.on.doc",
                     accent: copied ? TT.mint : TT.blue) {
                UIPasteboard.general.string = model.joined
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { copied = false }
                }
            }
            Button(action: openTranslate) {
                HStack(spacing: 7) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 13, weight: .semibold))
                    Text("翻譯這段文字")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(TT.teal.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(model.items.isEmpty)
            .opacity(model.items.isEmpty ? 0.4 : 1)
            HStack(spacing: 10) {
                Button {
                    model.clear()
                } label: {
                    Text("清空重來")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                ShareLink(item: model.joined) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("分享文字")
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
    }
}
