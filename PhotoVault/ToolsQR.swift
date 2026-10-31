import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - 糾錯級別

enum QRCorrection: String, CaseIterable, Identifiable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "L · 7%"
        case .medium: return "M · 15%"
        case .quartile: return "Q · 25%"
        case .high: return "H · 30%"
        }
    }

    var hint: String {
        switch self {
        case .low: return "容量最大，適合乾淨環境"
        case .medium: return "一般用途，平衡"
        case .quartile: return "稍有磨損也能讀"
        case .high: return "最耐髒污，容量最小"
        }
    }
}

// MARK: - 生成器

enum QRMaker {
    static func image(text: String,
                      correction: QRCorrection,
                      scale: CGFloat = 14,
                      dark: UIColor = UIColor(red: 0.02, green: 0.06, blue: 0.07, alpha: 1),
                      light: UIColor = .white) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8)

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = correction.rawValue

        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let colored = CIFilter.falseColor()
        colored.inputImage = scaled
        colored.color0 = CIColor(color: dark)
        colored.color1 = CIColor(color: light)

        guard let final = colored.outputImage else { return scaled.toUIImage() }

        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(final, from: final.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

extension CIImage {
    func toUIImage() -> UIImage? {
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(self, from: self.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 畫面

struct QRGenerateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var correction: QRCorrection = .medium
    @State private var darkTheme = false
    @State private var image: UIImage?
    @State private var generatedAt = Date()
    @State private var copied = false

    private var dark: UIColor {
        darkTheme
            ? UIColor(red: 0.02, green: 0.05, blue: 0.07, alpha: 1)
            : UIColor(red: 0.03, green: 0.07, blue: 0.09, alpha: 1)
    }

    private var light: UIColor {
        darkTheme
            ? UIColor(red: 0.62, green: 0.97, blue: 0.86, alpha: 1)
            : UIColor.white
    }

    var body: some View {
        TTScreen(title: "二維碼生成",
                 subtitle: "QR GENERATOR",
                 badge: image == nil ? "IDLE" : correction.rawValue,
                 badgeOn: image != nil,
                 accent: TT.indigo) {
            inputBlock
            optionBlock

            if let img = image {
                previewBlock(img)
                actionBlock(img)
            } else {
                TTPanel(accent: TT.indigo) {
                    TTEmptyHint(icon: "qrcode",
                                text: "輸入網址或文字，按「生成」\n全部離線計算，不上傳任何內容")
                }
            }

            TTPanel(accent: TT.violet, padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("小提示")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("內容越長，碼就越密。網址建議用短連結；如果掃不出來，把糾錯級別降到 L 讓格子變大。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var inputBlock: some View {
        TTPanel(accent: TT.indigo) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("內容")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text("\(text.count) 字")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.24))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(TT.indigo.opacity(0.22), lineWidth: 1)
                        )
                    if text.isEmpty {
                        Text("例如 https://t.me/zakadeep_bot")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                }

                TTButton(title: "生成二維碼", icon: "qrcode", accent: TT.indigo, enabled: !text.isEmpty) {
                    generate()
                }
            }
        }
    }

    private var optionBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "糾錯級別", accent: TT.indigo)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QRCorrection.allCases) { level in
                        Button {
                            correction = level
                            if image != nil { generate() }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(spacing: 2) {
                                Text(level.rawValue)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Text(level.title.split(separator: "·").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(correction == level ? TT.ink : .white.opacity(0.5))
                            .frame(width: 62, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(correction == level
                                          ? AnyShapeStyle(LinearGradient(colors: [TT.indigo, TT.violet],
                                                                         startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color.white.opacity(0.05)))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(correction.hint)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)

            TTPanel(accent: TT.violet, padding: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("薄荷配色")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                        Text("深底薄荷碼，適合放投影片或用於品牌")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                    Toggle("", isOn: $darkTheme)
                        .labelsHidden()
                        .tint(TT.indigo)
                        .onChange(of: darkTheme) { _ in
                            if image != nil { generate() }
                        }
                }
            }
        }
    }

    private func previewBlock(_ img: UIImage) -> some View {
        TTPanel(accent: TT.mint, padding: 12) {
            VStack(spacing: 12) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: TT.mint.opacity(0.18), radius: 22)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    TTStat(title: "尺寸", value: "\(Int(img.size.width))", unit: "px", accent: TT.mint)
                    TTStat(title: "糾錯", value: correction.rawValue, accent: TT.indigo)
                    TTStat(title: "內容", value: "\(text.count)", unit: "字", accent: TT.teal)
                }
            }
        }
    }

    private func actionBlock(_ img: UIImage) -> some View {
        VStack(spacing: 9) {
            ShareLink(item: Image(uiImage: img),
                      preview: SharePreview("二維碼", image: Image(uiImage: img))) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("分享或儲存圖片")
                        .font(.system(size: 14.5, weight: .semibold))
                }
                .foregroundStyle(TT.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [TT.mint, TT.teal],
                                             startPoint: .leading, endPoint: .trailing))
                )
            }

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = text
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Text(copied ? "已複製內容" : "複製內容")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    text = ""
                    image = nil
                } label: {
                    Text("清空")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func generate() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        image = QRMaker.image(text: trimmed, correction: correction, dark: dark, light: light)
        generatedAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
