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
            } else {
                errText = "無法讀取這張圖片"
            }

            let cost = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                self.items = results
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
