import SwiftUI
import UIKit
import PhotosUI
import Vision
import CoreImage

// MARK: - 規格

struct IDSpec: Identifiable, Hashable {
    let id: String
    let name: String
    let mm: String
    let px: CGSize

    static let presets: [IDSpec] = [
        IDSpec(id: "one", name: "一寸照", mm: "25 × 35 mm", px: CGSize(width: 295, height: 413)),
        IDSpec(id: "two", name: "兩寸照", mm: "35 × 49 mm", px: CGSize(width: 413, height: 579)),
        IDSpec(id: "head", name: "大頭照", mm: "35 × 45 mm", px: CGSize(width: 413, height: 531)),
        IDSpec(id: "passport", name: "護照", mm: "33 × 48 mm", px: CGSize(width: 390, height: 567)),
        IDSpec(id: "mainland", name: "台胞證", mm: "33 × 48 mm", px: CGSize(width: 390, height: 567)),
        IDSpec(id: "us", name: "美簽 2×2", mm: "51 × 51 mm", px: CGSize(width: 600, height: 600))
    ]
}

struct IDBackdrop: Identifiable {
    let id: String
    let name: String
    let color: UIColor

    static let all: [IDBackdrop] = [
        IDBackdrop(id: "white", name: "白底", color: UIColor.white),
        IDBackdrop(id: "blue", name: "藍底", color: UIColor(red: 0.26, green: 0.56, blue: 0.86, alpha: 1)),
        IDBackdrop(id: "red", name: "紅底", color: UIColor(red: 0.85, green: 0.13, blue: 0.16, alpha: 1)),
        IDBackdrop(id: "gray", name: "淺灰", color: UIColor(white: 0.9, alpha: 1))
    ]
}

// MARK: - 合成

enum IDRenderer {

    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func faceRect(of image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        try? handler.perform([request])
        return request.results?.first?.boundingBox
    }

    @available(iOS 17.0, *)
    static func cutout(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first else { return nil }
        guard let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances,
                                                           from: handler,
                                                           croppedToInstancesExtent: false) else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext()
        guard let out = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: out)
    }

    /// 把人像排進證件照規格：臉部高度約佔畫面 58%，頭頂留 13%
    static func compose(photo: UIImage,
                        face: CGRect?,
                        spec: IDSpec,
                        backdrop: UIColor,
                        subject: UIImage?) -> UIImage {
        let target = spec.px
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            backdrop.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))

            let drawImage = subject ?? photo
            let w = photo.size.width
            let h = photo.size.height
            var scale: CGFloat
            var origin = CGPoint.zero

            if let bb = face, w > 0, h > 0 {
                let faceTop = (1 - bb.maxY) * h
                let faceCenterX = bb.midX * w
                let faceH = max(bb.height * h, 1)
                scale = (target.height * 0.58) / faceH
                origin = CGPoint(x: target.width / 2 - faceCenterX * scale,
                                 y: target.height * 0.13 - faceTop * scale)
            } else {
                scale = max(target.width / max(w, 1), target.height / max(h, 1))
                origin = CGPoint(x: (target.width - w * scale) / 2,
                                 y: (target.height - h * scale) / 2)
            }

            let rect = CGRect(x: origin.x, y: origin.y,
                              width: drawImage.size.width * scale,
                              height: drawImage.size.height * scale)
            drawImage.draw(in: rect)
        }
    }
}

// MARK: - 頁面

struct IDPhotoView: View {
    @State private var picked: PhotosPickerItem?
    @State private var showPicker = false
    @State private var source: UIImage?
    @State private var subject: UIImage?
    @State private var result: UIImage?
    @State private var spec: IDSpec = IDSpec.presets[0]
    @State private var backdrop: IDBackdrop = IDBackdrop.all[0]
    @State private var removeBG = true
    @State private var working = false
    @State private var message: String?
    @State private var saved = false
    @State private var shareURL: URL?

    var body: some View {
        TTScreen(title: "證件照製作",
                 subtitle: "ID PHOTO",
                 badge: result == nil ? nil : spec.name,
                 badgeOn: true,
                 accent: TT.amber) {

            specRow

            ActionCard(accent: TT.amber,
                       icon: "photo.on.rectangle.angled",
                       title: source == nil ? "從相簿選一張人像" : "換一張照片",
                       note: "選正面、光線均勻、背景乾淨的照片效果最好") {
                showPicker = true
            }

            if let img = result {
                preview(img)
            } else {
                TTEmptyHint(icon: "person.crop.rectangle",
                            text: "選一張照片，就會自動排出符合規格的成品")
            }

            backdropRow

            TTPanel(accent: TT.teal) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $removeBG) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自動去背換底色")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                            Text("把人物從背景剪出來，換成你要的底色（需 iOS 17 以上）")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: TT.teal))
                    .onChange(of: removeBG) { _ in rebuild() }
                }
            }

            if working {
                HStack(spacing: 8) {
                    ProgressView().tint(TT.amber).scaleEffect(0.8)
                    Text("正在處理人像…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if let message = message {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TT.rose.opacity(0.9))
            }

            if let img = result {
                TTButton(title: saved ? "已存到相簿 ✓" : "儲存到相簿",
                         icon: "square.and.arrow.down",
                         accent: TT.amber) {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                    saved = true
                }

                if let url = shareURL {
                    ShareLink(item: url) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("分享這張證件照")
                                .font(.system(size: 14.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            TTPanel(accent: TT.violet) {
                VStack(alignment: .leading, spacing: 8) {
                    TTSectionTitle(text: "小提醒", accent: TT.violet)
                    Text("各國證件規格細節（頭部比例、耳朵露出、不能戴眼鏡）各不相同，這頁負責尺寸與底色；送出前記得對一下你要辦的那個單位的規定。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $picked, matching: .images)
        .onChange(of: picked) { item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        source = IDRenderer.upright(img)
                        subject = nil
                        saved = false
                        rebuild()
                    }
                }
                await MainActor.run { picked = nil }
            }
        }
        .onChange(of: spec) { _ in rebuild() }
        .onAppear { rebuild() }
    }

    // MARK: 規格

    private var specRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            TTSectionTitle(text: "尺寸規格", accent: TT.amber)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(IDSpec.presets) { item in
                        Button {
                            spec = item
                        } label: {
                            VStack(spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(spec.id == item.id ? TT.ink : Color.white.opacity(0.8))
                                Text(item.mm)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(spec.id == item.id ? TT.ink.opacity(0.6) : Color.white.opacity(0.3))
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(spec.id == item.id
                                               ? TT.amber.opacity(0.9)
                                               : Color.white.opacity(0.05))
                            )
                            .overlay(
                                Capsule().strokeBorder(spec.id == item.id
                                                       ? Color.clear
                                                       : Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: 預覽

    private func preview(_ img: UIImage) -> some View {
        VStack(spacing: 10) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)

            Text("\(spec.name) · \(spec.mm) · \(Int(spec.px.width)) × \(Int(spec.px.height)) px")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: 底色

    private var backdropRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            TTSectionTitle(text: "底色", accent: TT.blue)
            HStack(spacing: 10) {
                ForEach(IDBackdrop.all) { item in
                    Button {
                        backdrop = item
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(uiColor: item.color))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().strokeBorder(backdrop.id == item.id
                                                          ? TT.mint
                                                          : Color.white.opacity(0.15),
                                                          lineWidth: backdrop.id == item.id ? 2 : 1)
                                )
                                .shadow(color: backdrop.id == item.id ? TT.mint.opacity(0.5) : .clear,
                                        radius: 8)
                            Text(item.name)
                                .font(.system(size: 9.5))
                                .foregroundStyle(backdrop.id == item.id
                                                 ? Color.white.opacity(0.9)
                                                 : Color.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 計算

    private func rebuild() {
        guard let src = source else { return }
        saved = false
        working = true

        let currentSpec = spec
        let currentBackdrop = backdrop
        let wantCutout = removeBG

        Task {
            var cut: UIImage?
            if wantCutout {
                if #available(iOS 17.0, *) {
                    cut = IDRenderer.cutout(src)
                }
            }
            let face = IDRenderer.faceRect(of: src)
            let output = IDRenderer.compose(photo: src,
                                            face: face,
                                            spec: currentSpec,
                                            backdrop: currentBackdrop.color,
                                            subject: cut)

            await MainActor.run {
                subject = cut
                result = output
                working = false
                message = (wantCutout && cut == nil)
                    ? "這張沒能自動去背（可能人物佔比太小），先用原背景排出成品"
                    : nil

                if let data = output.pngData() {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("證件照-\(currentSpec.name)-\(Int(Date().timeIntervalSince1970)).png")
                    try? data.write(to: url)
                    shareURL = url
                }
            }
        }
    }
}
