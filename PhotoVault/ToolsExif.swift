import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - EXIF 讀取

struct ExifRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

struct ExifGroup: Identifiable {
    let id = UUID()
    let title: String
    let rows: [ExifRow]
}

struct ExifReport {
    var groups: [ExifGroup] = []
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var bytes: Int = 0
    var format: String = "—"
    var fieldCount: Int = 0

    var hasGPS: Bool { latitude != nil && longitude != nil }

    var resolutionText: String {
        pixelWidth > 0 ? "\(pixelWidth) × \(pixelHeight)" : "—"
    }

    var megapixelText: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "—" }
        let value = Double(pixelWidth * pixelHeight) / 1_000_000
        return String(format: "%.1f MP", value)
    }

    var bytesText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

enum ExifReader {

    private static func number(_ any: Any?) -> Double? {
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? String { return Double(value) }
        return nil
    }

    private static func text(_ any: Any?) -> String? {
        if let value = any as? String, !value.isEmpty { return value }
        return nil
    }

    private static func shutter(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds >= 1 {
            return String(format: "%.1f 秒", seconds)
        }
        return String(format: "1/%.0f 秒", 1 / seconds)
    }

    private static func gpsDegrees(_ any: Any?, reference: String?) -> Double? {
        // ImageIO 多半直接給 Double，少數檔案給 [度, 分, 秒]
        if let value = number(any) {
            var result = value
            if let reference = reference, reference.uppercased().hasPrefix("S") || reference.uppercased().hasPrefix("W") {
                result = -abs(result)
            }
            return result
        }
        if let list = any as? [Double], list.count >= 3 {
            var result = list[0] + list[1] / 60 + list[2] / 3600
            if let reference = reference, reference.uppercased().hasPrefix("S") || reference.uppercased().hasPrefix("W") {
                result = -abs(result)
            }
            return result
        }
        return nil
    }

    static func read(data: Data) -> ExifReport {
        var report = ExifReport()
        report.bytes = data.count

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            return report
        }

        if let rawType = CGImageSourceGetType(source) {
            let type = rawType as String
            if type.contains("heic") || type.contains("heif") { report.format = "HEIC" }
            else if type.contains("jpeg") { report.format = "JPEG" }
            else if type.contains("png") { report.format = "PNG" }
            else if type.contains("tiff") { report.format = "TIFF" }
            else { report.format = type.components(separatedBy: ".").last?.uppercased() ?? "—" }
        }

        if let width = number(properties["PixelWidth"]) { report.pixelWidth = Int(width) }
        if let height = number(properties["PixelHeight"]) { report.pixelHeight = Int(height) }

        let exif = properties["{Exif}"] as? [String: Any] ?? [:]
        let tiff = properties["{TIFF}"] as? [String: Any] ?? [:]
        let gps = properties["{GPS}"] as? [String: Any] ?? [:]

        report.fieldCount = exif.count + tiff.count + gps.count

        // 摘要
        var summary: [ExifRow] = []
        summary.append(ExifRow(key: "格式", value: report.format))
        summary.append(ExifRow(key: "尺寸", value: report.resolutionText))
        summary.append(ExifRow(key: "畫素", value: report.megapixelText))
        summary.append(ExifRow(key: "檔案大小", value: report.bytesText))
        if let color = text(properties["ColorModel"]) { summary.append(ExifRow(key: "色彩空間", value: color)) }
        if let depth = number(properties["Depth"]) { summary.append(ExifRow(key: "位元深度", value: "\(Int(depth)) 位元")) }
        if let orientation = number(properties["Orientation"]) {
            summary.append(ExifRow(key: "方向", value: orientation == 1 ? "正常（1）" : "已旋轉（\(Int(orientation))）"))
        }
        report.groups.append(ExifGroup(title: "檔案", rows: summary))

        // 相機
        var camera: [ExifRow] = []
        if let make = text(tiff["Make"]) ?? text(properties["Make"]) { camera.append(ExifRow(key: "品牌", value: make)) }
        if let model = text(tiff["Model"]) ?? text(properties["Model"]) { camera.append(ExifRow(key: "機型", value: model)) }
        if let lens = text(exif["LensModel"]) { camera.append(ExifRow(key: "鏡頭", value: lens)) }
        if let aperture = number(exif["FNumber"]) {
            camera.append(ExifRow(key: "光圈", value: String(format: "f/%.1f", aperture)))
        }
        if let exposure = number(exif["ExposureTime"]) {
            camera.append(ExifRow(key: "快門", value: shutter(exposure)))
        }
        if let isoList = exif["ISOSpeedRatings"] as? [Any], let first = isoList.first, let iso = number(first) {
            camera.append(ExifRow(key: "ISO", value: "\(Int(iso))"))
        } else if let iso = number(exif["ISOSpeedRatings"]) {
            camera.append(ExifRow(key: "ISO", value: "\(Int(iso))"))
        }
        if let focal = number(exif["FocalLength"]) {
            camera.append(ExifRow(key: "焦距", value: String(format: "%.2f mm", focal)))
        }
        if let focal35 = number(exif["FocalLenIn35mmFilm"]) {
            camera.append(ExifRow(key: "等效焦距", value: "\(Int(focal35)) mm"))
        }
        if let exposureBias = number(exif["ExposureBiasValue"]) {
            camera.append(ExifRow(key: "曝光補償", value: String(format: "%+.1f EV", exposureBias)))
        }
        if let flash = number(exif["Flash"]) {
            let fired = Int(flash) & 1 == 1
            camera.append(ExifRow(key: "閃光燈", value: fired ? "有閃光" : "未閃光"))
        }
        if let software = text(tiff["Software"]) ?? text(properties["Software"]) {
            camera.append(ExifRow(key: "軟體", value: software))
        }
        if !camera.isEmpty { report.groups.append(ExifGroup(title: "相機", rows: camera)) }

        // 時間
        var timeRows: [ExifRow] = []
        if let original = text(exif["DateTimeOriginal"]) {
            timeRows.append(ExifRow(key: "拍攝時間", value: Self.friendly(original)))
        }
        if let digitized = text(exif["DateTimeDigitized"]), digitized != text(exif["DateTimeOriginal"]) {
            timeRows.append(ExifRow(key: "數位化時間", value: Self.friendly(digitized)))
        }
        if let zone = text(exif["TimeZoneOffset"]) ?? text(exif["OffsetTimeOriginal"]) {
            timeRows.append(ExifRow(key: "時區", value: zone))
        }
        if !timeRows.isEmpty { report.groups.append(ExifGroup(title: "時間", rows: timeRows)) }

        // 位置
        if let latitude = gpsDegrees(gps["Latitude"], reference: text(gps["LatitudeRef"])),
           let longitude = gpsDegrees(gps["Longitude"], reference: text(gps["LongitudeRef"])) {
            report.latitude = latitude
            report.longitude = longitude

            var position: [ExifRow] = []
            position.append(ExifRow(key: "經緯度", value: String(format: "%.6f, %.6f", latitude, longitude)))
            position.append(ExifRow(key: "度分秒", value: "\(CoordMath.oneDMS(latitude, positive: "N", negative: "S")) \(CoordMath.oneDMS(longitude, positive: "E", negative: "W"))"))
            if let altitude = number(gps["Altitude"]) {
                report.altitude = altitude
                let reference = number(gps["AltitudeRef"]) ?? 0
                position.append(ExifRow(key: "海拔", value: String(format: "%.1f 公尺%@", altitude, reference == 1 ? "（低於海平面）" : "")))
            }
            if let speed = number(gps["Speed"]) {
                position.append(ExifRow(key: "速度", value: String(format: "%.1f m/s", speed)))
            }
            if let direction = number(gps["ImgDirection"]) {
                position.append(ExifRow(key: "拍攝方位", value: String(format: "%.0f°", direction)))
            }
            if let stamp = text(gps["DateStamp"]) {
                let clock = text(gps["TimeStamp"]) ?? ""
                position.append(ExifRow(key: "定位時間", value: "\(stamp) \(clock) UTC"))
            }
            if let plus = Optional(CoordMath.plusCode(lat: latitude, lon: longitude)) {
                position.append(ExifRow(key: "Plus Code", value: plus))
            }
            report.groups.append(ExifGroup(title: "位置", rows: position))
        }

        // 其他
        var other: [ExifRow] = []
        if let userComment = text(exif["UserComment"]) { other.append(ExifRow(key: "使用者註解", value: userComment)) }
        if let artist = text(tiff["Artist"]) { other.append(ExifRow(key: "作者", value: artist)) }
        if let copyright = text(tiff["Copyright"]) { other.append(ExifRow(key: "版權", value: copyright)) }
        if let descriptionText = text(tiff["ImageDescription"]) { other.append(ExifRow(key: "描述", value: descriptionText)) }
        if !other.isEmpty { report.groups.append(ExifGroup(title: "其他", rows: other)) }

        return report
    }

    private static func friendly(_ raw: String) -> String {
        // 2024:05:01 12:34:56 → 2024-05-01 12:34:56
        let parts = raw.split(separator: " ")
        guard let first = parts.first else { return raw }
        let datePart = first.replacingOccurrences(of: ":", with: "-")
        if parts.count > 1 { return "\(datePart) \(parts[1])" }
        return datePart
    }
}

// MARK: - 清除中繼資料

enum ExifStripper {
    /// 重繪像素後重新壓成 JPEG，EXIF / GPS / 機身資訊全部不帶
    static func strip(_ data: Data, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let flattened = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return flattened.jpegData(compressionQuality: quality)
    }
}

// MARK: - 頁面

struct ExifToolView: View {
    @State private var picked: PhotosPickerItem?
    @State private var originalData: Data?
    @State private var preview: UIImage?
    @State private var report = ExifReport()
    @State private var strippedData: Data?
    @State private var strippedImage: UIImage?
    @State private var working = false
    @State private var status: String?
    @State private var saved = false

    private let accent = TT.blue

    var body: some View {
        TTScreen(title: "EXIF 檢視與清除",
                 subtitle: "PHOTO METADATA",
                 badge: report.hasGPS ? "含位置" : nil,
                 badgeOn: report.hasGPS,
                 accent: accent) {

            pickRow

            if let image = preview {
                imagePreview(image)
                if report.hasGPS {
                    TTPanel(accent: TT.rose) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(TT.rose)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("這張照片藏著拍攝地點")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                Text("直接傳出去，對方能看到你在哪拍的")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                fieldGroups
                stripBlock
            } else {
                TTEmptyHint(icon: "camera.metering.center.weighted",
                            text: "從相簿選一張照片，看它都記錄了什麼")
            }
        }
        .onChange(of: picked) { item in
            guard let item = item else { return }
            load(item)
        }
    }

    // MARK: 選照片

    private var pickRow: some View {
        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                Text(preview == nil ? "從相簿選一張照片" : "換一張照片")
                    .font(.system(size: 14.5, weight: .semibold))
            }
            .foregroundStyle(TT.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [accent, TT.indigo],
                                         startPoint: .leading, endPoint: .trailing))
            )
        }
        .buttonStyle(.plain)
    }

    private func imagePreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    TTPill(text: report.format, color: accent)
                    TTPill(text: report.resolutionText, color: TT.teal)
                    TTPill(text: report.bytesText, color: TT.indigo)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
            )
    }

    // MARK: 欄位

    private var fieldGroups: some View {
        VStack(spacing: 14) {
            ForEach(report.groups) { group in
                TTPanel(accent: accent) {
                    VStack(alignment: .leading, spacing: 4) {
                        TTSectionTitle(text: group.title, accent: accent)
                            .padding(.bottom, 4)

                        ForEach(group.rows) { row in
                            TTKeyRow(key: row.key, value: row.value, accent: accent)
                        }

                        if group.title == "位置", let latitude = report.latitude, let longitude = report.longitude {
                            HStack(spacing: 9) {
                                mapButton(title: "Apple 地圖", apple: true, lat: latitude, lon: longitude)
                                mapButton(title: "Google 地圖", apple: false, lat: latitude, lon: longitude)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }

            TTPill(text: "共讀到 \(report.fieldCount) 項中繼資料", color: TT.teal)
        }
    }

    private func mapButton(title: String, apple: Bool, lat: Double, lon: Double) -> some View {
        Button {
            let text = apple
                ? "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(lat),\(lon)"
                : "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)"
            if let url = URL(string: text) { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "map").font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(TT.lime)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(TT.lime.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 清除區塊

    private var stripBlock: some View {
        VStack(spacing: 13) {
            TTSectionTitle(text: "清除中繼資料", accent: TT.rose)

            TTPanel(accent: TT.rose) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("重新壓一張乾淨的 JPEG：EXIF、GPS、機身序號、拍攝時間全部不帶走，畫面內容不變。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)

                    TTButton(title: working ? "處理中…" : (strippedData == nil ? "清除並產生乾淨版本" : "重新產生"),
                             icon: "eraser",
                             accent: TT.rose,
                             enabled: !working) {
                        strip()
                    }

                    if let strippedData = strippedData {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)

                        HStack(spacing: 10) {
                            TTStat(title: "清理後大小", value: ExifToolView.bytes(strippedData.count), accent: TT.mint)
                            TTStat(title: "省下", value: savedText, accent: TT.mint)
                        }

                        TTButton(title: "儲存到相簿", icon: "square.and.arrow.down", accent: TT.teal) {
                            saveStripped()
                        }

                        if let status = status {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(saved ? TT.mint : .white.opacity(0.4))
                        }
                    }
                }
            }
        }
    }

    private var savedText: String {
        guard let strippedData = strippedData, report.bytes > 0 else { return "—" }
        let delta = report.bytes - strippedData.count
        if delta <= 0 { return "0 KB" }
        return "\(ExifToolView.bytes(delta))"
    }

    private static func bytes(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(count))
    }

    // MARK: 動作

    private func load(_ item: PhotosPickerItem) {
        working = true
        status = nil
        saved = false
        strippedData = nil
        strippedImage = nil

        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                working = false
                guard let data = data else {
                    status = "這張讀不出來，換一張試試"
                    return
                }
                originalData = data
                preview = UIImage(data: data)
                report = ExifReader.read(data: data)
            }
        }
    }

    private func strip() {
        guard let originalData = originalData else { return }
        working = true
        status = nil
        saved = false

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ExifStripper.strip(originalData, quality: 0.95)
            DispatchQueue.main.async {
                working = false
                guard let result = result else {
                    status = "這張處理不了，換一張試試"
                    return
                }
                strippedData = result
                strippedImage = UIImage(data: result)
                status = "已產生乾淨版本，還沒存進相簿"
            }
        }
    }

    private func saveStripped() {
        guard let image = strippedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saved = true
        status = "已存進相簿，這張傳出去不會帶位置"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
