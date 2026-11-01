import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI

// MARK: - 內容類型

enum QRStudioKind: String, CaseIterable, Identifiable {
    case url, text, contact, wifi
    var id: String { rawValue }

    var title: String {
        switch self {
        case .url:     return "網址"
        case .text:    return "文字"
        case .contact: return "聯絡資訊"
        case .wifi:    return "Wi-Fi"
        }
    }

    var icon: String {
        switch self {
        case .url:     return "link"
        case .text:    return "text.alignleft"
        case .contact: return "person.crop.circle"
        case .wifi:    return "wifi"
        }
    }
}

// MARK: - 模組樣式

enum QRStudioStyle: String, CaseIterable, Identifiable {
    case square, rounded, dots, bar
    var id: String { rawValue }

    var title: String {
        switch self {
        case .square:  return "方形"
        case .rounded: return "圓角"
        case .dots:    return "圓點"
        case .bar:     return "橫條"
        }
    }
}

// MARK: - 產生器

enum QRStudioRenderer {

    /// 把 QR 內容變成模組矩陣（true = 深色格）
    static func matrix(_ text: String, correction: String) -> [[Bool]]? {
        guard !text.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction

        guard let output = filter.outputImage else { return nil }

        let w = Int(output.extent.width)
        let h = Int(output.extent.height)
        guard w > 7, h > 7 else { return nil }

        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }

        var pixels = [UInt8](repeating: 255, count: w * h)
        guard let bitmap = CGContext(data: &pixels,
                                     width: w,
                                     height: h,
                                     bitsPerComponent: 8,
                                     bytesPerRow: w,
                                     space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        bitmap.interpolationQuality = .none
        bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var grid = (0..<h).map { row in
            (0..<w).map { col in pixels[row * w + col] < 128 }
        }

        // 方向校正：標準 QR 的定位圖案在左上、右上、左下三個角
        let okOrigin = hasFinder(grid, 0, 0) && hasFinder(grid, 0, w - 7) && hasFinder(grid, h - 7, 0)
        if !okOrigin {
            let flipped = Array(grid.reversed())
            if hasFinder(flipped, 0, 0) && hasFinder(flipped, 0, w - 7) && hasFinder(flipped, h - 7, 0) {
                grid = flipped
            }
        }
        return grid
    }

    /// 7×7 定位圖案檢查：外框全深、中間一圈淺、中心 3×3 深
    static func hasFinder(_ grid: [[Bool]], _ r0: Int, _ c0: Int) -> Bool {
        let h = grid.count
        guard h > 0 else { return false }
        let w = grid[0].count
        guard r0 >= 0, c0 >= 0, r0 + 7 <= h, c0 + 7 <= w else { return false }

        for i in 0..<7 {
            if !grid[r0][c0 + i] || !grid[r0 + 6][c0 + i] { return false }
            if !grid[r0 + i][c0] || !grid[r0 + i][c0 + 6] { return false }
        }
        for i in 1...5 {
            if grid[r0 + 1][c0 + i] || grid[r0 + 5][c0 + i] { return false }
            if grid[r0 + i][c0 + 1] || grid[r0 + i][c0 + 5] { return false }
        }
        for r in 2...4 {
            for c in 2...4 {
                if !grid[r0 + r][c0 + c] { return false }
            }
        }
        return true
    }

    static func image(matrix: [[Bool]],
                      fg: UIColor,
                      bg: UIColor,
                      bg2: UIColor?,
                      gradient: Bool,
                      style: QRStudioStyle,
                      icon: UIImage?) -> UIImage? {
        let n = matrix.count
        guard n > 0 else { return nil }

        let side: CGFloat = 1024
        let margin = side * 0.065
        let module = (side - margin * 2) / CGFloat(n)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            if gradient, let second = bg2,
               let space = CGColorSpace(name: CGColorSpace.sRGB),
               let grad = CGGradient(colorsSpace: space,
                                     colors: [bg.cgColor, second.cgColor] as CFArray,
                                     locations: [0, 1]) {
                cg.drawLinearGradient(grad,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: side, y: side),
                                      options: [])
            } else {
                cg.setFillColor(bg.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }

            cg.setFillColor(fg.cgColor)
            for row in 0..<n {
                for col in 0..<n where matrix[row][col] {
                    let rect = CGRect(x: margin + CGFloat(col) * module,
                                      y: margin + CGFloat(row) * module,
                                      width: module,
                                      height: module)
                    switch style {
                    case .square:
                        cg.fill(rect)
                    case .rounded:
                        let r = rect.insetBy(dx: module * 0.06, dy: module * 0.06)
                        cg.addPath(UIBezierPath(roundedRect: r, cornerRadius: module * 0.3).cgPath)
                        cg.fillPath()
                    case .dots:
                        cg.fillEllipse(in: rect.insetBy(dx: module * 0.09, dy: module * 0.09))
                    case .bar:
                        cg.fill(rect.insetBy(dx: 0, dy: module * 0.23))
                    }
                }
            }

            if let icon = icon {
                let box = side * 0.235
                let frame = CGRect(x: (side - box) / 2, y: (side - box) / 2, width: box, height: box)
                let plate = UIBezierPath(roundedRect: frame, cornerRadius: box * 0.24)
                cg.setFillColor(bg.cgColor)
                cg.addPath(plate.cgPath)
                cg.fillPath()

                let inner = frame.insetBy(dx: box * 0.13, dy: box * 0.13)
                cg.saveGState()
                cg.addPath(UIBezierPath(roundedRect: inner, cornerRadius: box * 0.16).cgPath)
                cg.clip()
                icon.draw(in: aspectFill(icon, in: inner))
                cg.restoreGState()
            }
        }
    }

    private static func aspectFill(_ image: UIImage, in rect: CGRect) -> CGRect {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else { return rect }
        let scale = max(rect.width / iw, rect.height / ih)
        let w = iw * scale
        let h = ih * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Wi-Fi / vCard 欄位轉義
    static func escape(_ value: String) -> String {
        var out = ""
        for ch in value {
            if "\\;,:\"".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}

// MARK: - 頁面

struct QRStudioView: View {
    @State private var kind: QRStudioKind = .url

    @State private var urlText = "https://"
    @State private var plainText = ""
    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var contactEmail = ""
    @State private var contactOrg = ""
    @State private var wifiSSID = ""
    @State private var wifiPass = ""
    @State private var wifiSecure = true
    @State private var wifiHidden = false

    @State private var fgColor: Color = Color(red: 0.04, green: 0.06, blue: 0.09)
    @State private var bgColor: Color = Color.white
    @State private var bgColor2: Color = Color(red: 0.80, green: 0.98, blue: 0.94)
    @State private var gradientOn = false
    @State private var style: QRStudioStyle = .rounded

    @State private var pickerItem: PhotosPickerItem?
    @State private var icon: UIImage?

    @State private var image: UIImage?
    @State private var hint: String?
    @State private var copied = false

    private let fgPresets: [Color] = [
        Color(red: 0.04, green: 0.06, blue: 0.09),
        TT.mint, TT.teal, TT.blue, TT.violet, TT.rose, TT.amber, Color.white
    ]

    private let bgPresets: [Color] = [
        Color.white,
        Color(red: 0.95, green: 0.97, blue: 0.99),
        Color(red: 0.88, green: 0.99, blue: 0.96),
        Color(red: 0.90, green: 0.94, blue: 1.00),
        Color(red: 1.00, green: 0.95, blue: 0.88),
        Color(red: 0.10, green: 0.13, blue: 0.19)
    ]

    private var payload: String {
        switch kind {
        case .url:
            return urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .text:
            return plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .contact:
            let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            let mail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            let org = contactOrg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty || !phone.isEmpty || !mail.isEmpty else { return "" }
            var lines = ["BEGIN:VCARD", "VERSION:3.0"]
            if !name.isEmpty {
                lines.append("FN:\(name)")
                lines.append("N:\(name);;;;")
            }
            if !org.isEmpty { lines.append("ORG:\(org)") }
            if !phone.isEmpty { lines.append("TEL;TYPE=CELL:\(phone)") }
            if !mail.isEmpty { lines.append("EMAIL:\(mail)") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\n")
        case .wifi:
            let ssid = wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty else { return "" }
            var out = "WIFI:"
            out += "T:\(wifiSecure ? "WPA" : "nopass");"
            out += "S:\(QRStudioRenderer.escape(ssid));"
            if wifiSecure {
                out += "P:\(QRStudioRenderer.escape(wifiPass));"
            }
            if wifiHidden { out += "H:true;" }
            out += ";"
            return out
        }
    }

    var body: some View {
        TTScreen(title: "QR 工作室",
                 subtitle: "QRCODE STUDIO",
                 badge: image == nil ? "IDLE" : "READY",
                 badgeOn: image != nil,
                 accent: TT.indigo) {

            kindBlock
            inputBlock

            TTButton(title: "產生 QR Code", icon: "qrcode", accent: TT.indigo, enabled: !payload.isEmpty) {
                generate()
            }

            if let img = image {
                previewBlock(img)
                shareBlock(img)
            } else {
                TTPanel(accent: TT.indigo) {
                    TTEmptyHint(icon: "qrcode.viewfinder",
                                text: hint ?? "選一種內容、填好資料\n按「產生」就會即時畫出來")
                }
            }

            colorBlock
            styleBlock
            iconBlock

            TTPanel(accent: TT.teal, padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("掃不出來怎麼辦")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("前景與背景的對比要夠強（深碼配淺底最穩）。加了中心圖示會自動把糾錯級別提到 H，遮住約 15% 仍可讀；內容太長時格子會變密，建議縮短網址。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 類型

    private var kindBlock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QRStudioKind.allCases) { item in
                    Button {
                        kind = item
                        hint = nil
                        image = nil
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(kind == item ? TT.ink : Color.white.opacity(0.55))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(
                            Capsule().fill(kind == item
                                           ? AnyShapeStyle(LinearGradient(colors: [TT.indigo, TT.violet],
                                                                          startPoint: .leading,
                                                                          endPoint: .trailing))
                                           : AnyShapeStyle(Color.white.opacity(0.05)))
                        )
                        .overlay(Capsule().strokeBorder(Color.white.opacity(kind == item ? 0 : 0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: 內容輸入

    private var inputBlock: some View {
        TTPanel(accent: TT.indigo) {
            VStack(alignment: .leading, spacing: 11) {
                switch kind {
                case .url:
                    fieldLabel("網址")
                    plainField("https://example.com", text: $urlText)
                case .text:
                    fieldLabel("文字內容")
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $plainText)
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
                        if plainText.isEmpty {
                            Text("輸入要放進 QR 的任何文字")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.2))
                                .padding(.horizontal, 14)
                                .padding(.top, 14)
                                .allowsHitTesting(false)
                        }
                    }
                case .contact:
                    fieldLabel("姓名")
                    plainField("王小明", text: $contactName)
                    fieldLabel("電話")
                    plainField("0912 345 678", text: $contactPhone, keyboard: .phonePad)
                    fieldLabel("電子郵件")
                    plainField("hello@example.com", text: $contactEmail, keyboard: .emailAddress)
                    fieldLabel("公司／組織（選填）")
                    plainField("源隼科技", text: $contactOrg)
                case .wifi:
                    fieldLabel("網路名稱 SSID")
                    plainField("MyWiFi", text: $wifiSSID)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("有密碼（WPA／WPA2）")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("開放式網路關掉這個")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer(minLength: 6)
                        Toggle("", isOn: $wifiSecure)
                            .labelsHidden()
                            .tint(TT.indigo)
                    }
                    if wifiSecure {
                        fieldLabel("密碼")
                        plainField("••••••••", text: $wifiPass)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("隱藏網路")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("SSID 不外播時打開")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer(minLength: 6)
                        Toggle("", isOn: $wifiHidden)
                            .labelsHidden()
                            .tint(TT.indigo)
                    }
                }

                Text("\(payload.count) 字元")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.26))
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.35))
    }

    private func plainField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13.5))
            .foregroundStyle(.white)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(TT.indigo.opacity(0.22), lineWidth: 1)
            )
    }

    // MARK: 預覽

    private func previewBlock(_ img: UIImage) -> some View {
        TTPanel(accent: TT.mint, padding: 12) {
            VStack(spacing: 12) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: TT.mint.opacity(0.18), radius: 22)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    TTStat(title: "尺寸", value: "1024", unit: "px", accent: TT.mint)
                    TTStat(title: "糾錯", value: icon == nil ? "M" : "H", accent: TT.indigo)
                    TTStat(title: "內容", value: "\(payload.count)", unit: "字", accent: TT.teal)
                }
            }
        }
    }

    private func shareBlock(_ img: UIImage) -> some View {
        VStack(spacing: 9) {
            ShareLink(item: Image(uiImage: img),
                      preview: SharePreview("QR Code", image: Image(uiImage: img))) {
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
                                             startPoint: .leading,
                                             endPoint: .trailing))
                )
            }

            Button {
                UIPasteboard.general.string = payload
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation { copied = false }
                }
            } label: {
                Text(copied ? "已複製原始內容" : "複製原始內容")
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

    // MARK: 顏色

    private var colorBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "顏色與背景", accent: TT.violet)

            TTPanel(accent: TT.violet) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("前景色（碼的顏色）")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 9) {
                        ForEach(Array(fgPresets.enumerated()), id: \.offset) { _, color in
                            swatch(color, selected: fgColor == color) {
                                fgColor = color
                                refresh()
                            }
                        }
                        ColorPicker("", selection: $fgColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 26, height: 26)
                            .onChange(of: fgColor) { _ in refresh() }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)

                    Text("背景色（底色）")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 9) {
                        ForEach(Array(bgPresets.enumerated()), id: \.offset) { _, color in
                            swatch(color, selected: bgColor == color) {
                                bgColor = color
                                refresh()
                            }
                        }
                        ColorPicker("", selection: $bgColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 26, height: 26)
                            .onChange(of: bgColor) { _ in refresh() }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("漸層背景")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                            Text("由主色漸變到第二色")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer(minLength: 6)
                        Toggle("", isOn: $gradientOn)
                            .labelsHidden()
                            .tint(TT.violet)
                            .onChange(of: gradientOn) { _ in refresh() }
                    }

                    if gradientOn {
                        HStack(spacing: 9) {
                            Text("第二色")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.32))
                            Spacer(minLength: 0)
                            ColorPicker("", selection: $bgColor2, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 26, height: 26)
                                .onChange(of: bgColor2) { _ in refresh() }
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(selected ? TT.mint : Color.white.opacity(0.18),
                                          lineWidth: selected ? 2 : 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 樣式

    private var styleBlock: some View {
        VStack(spacing: 11) {
            TTSectionTitle(text: "模組樣式", accent: TT.indigo)
            HStack(spacing: 8) {
                ForEach(QRStudioStyle.allCases) { item in
                    Button {
                        style = item
                        refresh()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style == item ? TT.ink : Color.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(style == item
                                          ? AnyShapeStyle(LinearGradient(colors: [TT.indigo, TT.violet],
                                                                         startPoint: .top,
                                                                         endPoint: .bottom))
                                          : AnyShapeStyle(Color.white.opacity(0.05)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 中心圖示

    private var iconBlock: some View {
        TTPanel(accent: TT.rose) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("中心圖示")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("放一張圖在碼中間，糾錯自動提到 H")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer(minLength: 6)

                    if icon != nil {
                        Button {
                            icon = nil
                            pickerItem = nil
                            refresh()
                        } label: {
                            Text("移除")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(TT.rose)
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(Capsule().fill(TT.rose.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text(icon == nil ? "選擇圖片" : "更換")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(TT.ink)
                            .padding(.horizontal, 13)
                            .frame(height: 30)
                            .background(Capsule().fill(TT.mint))
                    }
                    .onChange(of: pickerItem) { item in
                        loadIcon(item)
                    }
                }

                if let icon = icon {
                    HStack(spacing: 10) {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("已套用，重新產生即可看到")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func loadIcon(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                await MainActor.run {
                    icon = img
                    refresh()
                }
            }
        }
    }

    // MARK: 動作

    private func refresh() {
        if image != nil { generate() }
    }

    private func generate() {
        let text = payload
        guard !text.isEmpty else {
            image = nil
            hint = "先把內容填好"
            return
        }
        let level = icon == nil ? "M" : "H"
        guard let grid = QRStudioRenderer.matrix(text, correction: level) else {
            image = nil
            hint = "內容太長，這個糾錯級別塞不下\n試著縮短內容"
            return
        }
        image = QRStudioRenderer.image(matrix: grid,
                                       fg: UIColor(fgColor),
                                       bg: UIColor(bgColor),
                                       bg2: gradientOn ? UIColor(bgColor2) : nil,
                                       gradient: gradientOn,
                                       style: style,
                                       icon: icon)
        hint = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
