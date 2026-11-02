import SwiftUI
import UIKit
import CoreLocation

// MARK: - 座標數學（全部本機計算）

enum CoordMath {

    /// 一組座標的六種寫法
    struct Result {
        var decimal: String = "—"
        var dms: String = "—"
        var utm: String = "—"
        var twd97: String = "—"
        var twd97Alt: String = "—"
        var mgrs: String = "—"
        var plus: String = "—"
    }

    // MARK: 解析使用者貼上的座標

    static func parse(_ text: String) -> (lat: Double, lon: Double)? {
        let cleaned = text
            .replacingOccurrences(of: "，", with: " ")
            .replacingOccurrences(of: "、", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: "°", with: " ")
            .replacingOccurrences(of: "º", with: " ")
            .replacingOccurrences(of: "′", with: " ")
            .replacingOccurrences(of: "’", with: " ")
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "″", with: " ")
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "“", with: " ")
            .replacingOccurrences(of: "”", with: " ")
            .replacingOccurrences(of: ",", with: " ")

        var numbers: [Double] = []
        var buffer = ""
        for ch in cleaned {
            if ch.isNumber || ch == "." || ch == "-" || ch == "+" {
                buffer.append(ch)
            } else {
                if !buffer.isEmpty {
                    if let value = Double(buffer) { numbers.append(value) }
                    buffer = ""
                }
            }
        }
        if !buffer.isEmpty, let value = Double(buffer) { numbers.append(value) }

        let upper = cleaned.uppercased()
        var latSign = 1.0
        var lonSign = 1.0
        var latMarked = false
        var lonMarked = false

        for ch in upper {
            if ch == "S" { latSign = -1; latMarked = true; break }
            if ch == "N" { latSign = 1; latMarked = true; break }
        }
        for ch in upper {
            if ch == "W" { lonSign = -1; lonMarked = true; break }
            if ch == "E" { lonSign = 1; lonMarked = true; break }
        }

        var lat = 0.0
        var lon = 0.0

        switch numbers.count {
        case 2:
            lat = numbers[0]
            lon = numbers[1]
        case 4:
            lat = abs(numbers[0]) + abs(numbers[1]) / 60
            lon = abs(numbers[2]) + abs(numbers[3]) / 60
        case 5:
            lat = abs(numbers[0]) + abs(numbers[1]) / 60 + abs(numbers[2]) / 3600
            lon = abs(numbers[3]) + abs(numbers[4]) / 60
        case 6:
            lat = abs(numbers[0]) + abs(numbers[1]) / 60 + abs(numbers[2]) / 3600
            lon = abs(numbers[3]) + abs(numbers[4]) / 60 + abs(numbers[5]) / 3600
        default:
            return nil
        }

        if latMarked { lat = abs(lat) * latSign }
        if lonMarked { lon = abs(lon) * lonSign }
        if abs(lat) > 90 || abs(lon) > 180 { return nil }
        return (lat, lon)
    }

    // MARK: 格式化

    static func decimalString(lat: Double, lon: Double) -> String {
        String(format: "%.6f, %.6f", lat, lon)
    }

    static func dmsString(lat: Double, lon: Double) -> String {
        "\(oneDMS(lat, positive: "N", negative: "S")) \(oneDMS(lon, positive: "E", negative: "W"))"
    }

    static func oneDMS(_ value: Double, positive: String, negative: String) -> String {
        let hemisphere = value >= 0 ? positive : negative
        let absolute = abs(value)
        let degree = floor(absolute)
        let minutesTotal = (absolute - degree) * 60
        let minute = floor(minutesTotal)
        var second = (minutesTotal - minute) * 60
        if second >= 59.995 { second = 0 }
        return String(format: "%.0f°%02.0f′%04.1f″%@", degree, minute, second, hemisphere)
    }

    // MARK: 投影（橫麥卡托）

    private static func transverseMercator(lat: Double, lon: Double, lon0: Double,
                                           k0: Double, falseEasting: Double,
                                           a: Double, flattening: Double) -> (x: Double, y: Double) {
        let e2 = flattening * (2 - flattening)
        let ep2 = e2 / (1 - e2)
        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180
        let lon0Rad = lon0 * .pi / 180

        let sinLat = sin(latRad)
        let cosLat = cos(latRad)
        let tanLat = tan(latRad)

        let n = a / sqrt(1 - e2 * sinLat * sinLat)
        let t = tanLat * tanLat
        let c = ep2 * cosLat * cosLat
        let aTerm = (lonRad - lon0Rad) * cosLat

        let m = a * ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * latRad
                     - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) * sin(2 * latRad)
                     + (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) * sin(4 * latRad)
                     - (35 * e2 * e2 * e2 / 3072) * sin(6 * latRad))

        let x = k0 * n * (aTerm
                          + (1 - t + c) * pow(aTerm, 3) / 6
                          + (5 - 18 * t + t * t + 72 * c - 58 * ep2) * pow(aTerm, 5) / 120) + falseEasting

        var y = k0 * (m + n * tanLat * (aTerm * aTerm / 2
                                        + (5 - t + 9 * c + 4 * c * c) * pow(aTerm, 4) / 24
                                        + (61 - 58 * t + t * t + 600 * c - 330 * ep2) * pow(aTerm, 6) / 720))
        if lat < 0 { y += 10000000 }
        return (x, y)
    }

    static func utm(lat: Double, lon: Double) -> (zone: Int, band: String, easting: Double, northing: Double) {
        var zone = Int(floor((lon + 180) / 6)) + 1
        zone = min(max(zone, 1), 60)
        let lon0 = Double((zone - 1) * 6 - 180 + 3)
        let projected = transverseMercator(lat: lat, lon: lon, lon0: lon0,
                                           k0: 0.9996, falseEasting: 500000,
                                           a: 6378137.0, flattening: 1 / 298.257223563)
        let bandIndex = min(max(Int(floor((lat + 80) / 8)), 0), 19)
        let letters = Array("CDEFGHJKLMNPQRSTUVWX")
        return (zone, String(letters[bandIndex]), projected.x, projected.y)
    }

    /// TWD97 二度分帶（GRS80、中央經線 121 或 119、比例 0.9999、西假原點 250000）
    static func twd97(lat: Double, lon: Double, lon0: Double) -> (x: Double, y: Double) {
        transverseMercator(lat: lat, lon: lon, lon0: lon0,
                           k0: 0.9999, falseEasting: 250000,
                           a: 6378137.0, flattening: 1 / 298.257222101)
    }

    static func mgrs(zone: Int, band: String, easting: Double, northing: Double) -> String {
        let columnLetters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let rowLetters = Array("ABCDEFGHJKLMNPQRSTUV")
        var setNumber = zone % 6
        if setNumber == 0 { setNumber = 6 }

        let columnOffsets = [1: 0, 2: 8, 3: 16, 4: 0, 5: 8, 6: 16]
        let rowOffsets = [1: 0, 2: 5, 3: 10, 4: 15, 5: 0, 6: 5]

        let columnOffset = columnOffsets[setNumber] ?? 0
        let rowOffset = rowOffsets[setNumber] ?? 0

        let eastingHundredKm = Int(easting / 100000)
        let northingHundredKm = Int(northing / 100000) % 20

        let columnIndex = ((eastingHundredKm - 1 + columnOffset) % 24 + 24) % 24
        let rowIndex = ((northingHundredKm + rowOffset) % 20 + 20) % 20

        let eastDigits = String(format: "%05d", Int(easting) % 100000)
        let northDigits = String(format: "%05d", Int(northing) % 100000)

        return "\(zone)\(band) \(columnLetters[columnIndex])\(rowLetters[rowIndex]) \(eastDigits) \(northDigits)"
    }

    static func plusCode(lat: Double, lon: Double) -> String {
        let alphabet = Array("23456789CFGHJMPQRVWX")
        var latitude = min(max(lat, -90), 90) + 90
        var longitude = lon
        while longitude < -180 { longitude += 360 }
        while longitude >= 180 { longitude -= 360 }
        longitude += 180

        var latResolution = 20.0
        var lonResolution = 20.0
        var code = ""

        for pair in 0..<5 {
            let latDigit = min(max(Int(latitude / latResolution), 0), 19)
            let lonDigit = min(max(Int(longitude / lonResolution), 0), 19)
            code.append(alphabet[latDigit])
            code.append(alphabet[lonDigit])
            latitude -= Double(latDigit) * latResolution
            longitude -= Double(lonDigit) * lonResolution
            latResolution /= 20
            lonResolution /= 20
            if pair == 3 { code.append("+") }
        }
        return code
    }

    static func build(lat: Double, lon: Double) -> Result {
        var result = Result()
        result.decimal = decimalString(lat: lat, lon: lon)
        result.dms = dmsString(lat: lat, lon: lon)

        let utmValue = utm(lat: lat, lon: lon)
        result.utm = String(format: "%d%@ %.0f E  %.0f N",
                            utmValue.zone, utmValue.band, utmValue.easting, utmValue.northing)
        result.mgrs = mgrs(zone: utmValue.zone, band: utmValue.band,
                           easting: utmValue.easting, northing: utmValue.northing)

        let main = twd97(lat: lat, lon: lon, lon0: 121)
        result.twd97 = String(format: "%.2f E  %.2f N", main.x, main.y)
        let alternate = twd97(lat: lat, lon: lon, lon0: 119)
        result.twd97Alt = String(format: "%.2f E  %.2f N", alternate.x, alternate.y)

        result.plus = plusCode(lat: lat, lon: lon)
        return result
    }
}

// MARK: - 取一次目前位置

final class CoordLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var horizontalAccuracy: Double = 0
    @Published var message: String?
    @Published var busy = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func request() {
        busy = true
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            busy = false
            message = "定位權限沒開，可以到設定裡打開"
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            busy = false
            message = "定位權限沒開，可以到設定裡打開"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        busy = false
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        busy = false
        message = "暫時取不到位置，到空曠處再試一次"
    }
}

// MARK: - 頁面

struct CoordConvView: View {
    @StateObject private var locator = CoordLocator()

    @State private var input = "25.033976, 121.564469"
    @State private var copiedKey = ""

    private var coordinate: (lat: Double, lon: Double)? {
        CoordMath.parse(input)
    }

    private var result: CoordMath.Result? {
        guard let coordinate = coordinate else { return nil }
        return CoordMath.build(lat: coordinate.lat, lon: coordinate.lon)
    }

    var body: some View {
        TTScreen(title: "座標轉換器",
                 subtitle: "COORDINATE CONVERTER",
                 badge: coordinate == nil ? nil : "6 種格式",
                 badgeOn: true,
                 accent: TT.lime) {

            inputBlock

            if let result = result {
                mainBlock(result)
                mapBlock
            } else {
                TTEmptyHint(icon: "mappin.slash",
                            text: "貼一組座標進來：\n25.033976, 121.564469\n或 25°02′02.3″N 121°33′52.1″E")
            }

            if let message = locator.message {
                TTPill(text: message, color: TT.amber)
            }

            noteBlock
        }
        .onChange(of: locator.latitude) { newValue in
            guard let lat = newValue, let lon = locator.longitude else { return }
            input = String(format: "%.6f, %.6f", lat, lon)
        }
    }

    // MARK: 輸入

    private var inputBlock: some View {
        TTPanel(accent: TT.lime) {
            VStack(alignment: .leading, spacing: 12) {
                TTSectionTitle(text: "貼上座標", accent: TT.lime)

                HStack(spacing: 8) {
                    TextField("25.033976, 121.564469", text: $input)
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding(.horizontal, 11)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )

                    if !input.isEmpty {
                        Button {
                            input = ""
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let coordinate = coordinate {
                    Text(String(format: "已解析：%.6f, %.6f", coordinate.lat, coordinate.lon))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(TT.lime.opacity(0.75))
                } else if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("這個格式讀不出來，試 25.0339, 121.5645 或加上 N/E 標記")
                        .font(.system(size: 10.5))
                        .foregroundStyle(TT.amber.opacity(0.8))
                }

                HStack(spacing: 9) {
                    smallButton(title: "目前位置", icon: "location.fill", accent: TT.lime) {
                        locator.request()
                    }
                    smallButton(title: "貼上剪貼簿", icon: "doc.on.clipboard", accent: TT.teal) {
                        if let text = UIPasteboard.general.string {
                            input = text
                        }
                    }
                    smallButton(title: "複製全部", icon: "square.on.square", accent: TT.blue) {
                        copyAll()
                    }
                }
            }
        }
    }

    private func smallButton(title: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accent.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 結果

    private func mainBlock(_ result: CoordMath.Result) -> some View {
        VStack(spacing: 0) {
            copyRow(key: "十進位 DD", value: result.decimal, icon: "number")
            divider
            copyRow(key: "度分秒 DMS", value: result.dms, icon: "ruler")
            divider
            copyRow(key: "UTM", value: result.utm, icon: "square.grid.3x3")
            divider
            copyRow(key: "TWD97 二度分帶 121", value: result.twd97, icon: "map")
            divider
            copyRow(key: "TWD97 二度分帶 119", value: result.twd97Alt, icon: "map")
            divider
            copyRow(key: "MGRS", value: result.mgrs, icon: "grid")
            divider
            copyRow(key: "Plus Code", value: result.plus, icon: "plus.square.on.square")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TT.lime.opacity(0.2), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
    }

    private func copyRow(key: String, value: String, icon: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copiedKey = key
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if copiedKey == key { copiedKey = "" }
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TT.lime.opacity(0.7))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(key)
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.38))
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                Text(copiedKey == key ? "已複製" : "複製")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(copiedKey == key ? TT.lime : .white.opacity(0.3))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 地圖

    private var mapBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "在地圖上打開", accent: TT.teal)

            HStack(spacing: 9) {
                smallButton(title: "Apple 地圖", icon: "map.fill", accent: TT.teal) {
                    openMap(apple: true)
                }
                smallButton(title: "Google 地圖", icon: "globe", accent: TT.blue) {
                    openMap(apple: false)
                }
            }
        }
    }

    private func openMap(apple: Bool) {
        guard let coordinate = coordinate else { return }
        let lat = coordinate.lat
        let lon = coordinate.lon
        let text = apple
            ? "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(lat),\(lon)"
            : "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)"
        if let url = URL(string: text) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: 說明

    private var noteBlock: some View {
        TTPanel(accent: TT.amber) {
            VStack(alignment: .leading, spacing: 9) {
                TTSectionTitle(text: "關於這些格式", accent: TT.amber)
                noteRow("十進位 DD", "Google 地圖、Apple 地圖貼上去就能定位")
                noteRow("度分秒 DMS", "導航語音、電子地圖標示常用")
                noteRow("UTM", "全球通用方格，登山與軍事地圖慣用")
                noteRow("TWD97", "台灣地籍、地政與工程圖慣用；本島多為 121，金門馬祖用 119")
                noteRow("MGRS", "軍用地圖方格，UTM 的精簡寫法")
                noteRow("Plus Code", "Google 的短地址，適合口頭報位置")
            }
        }
    }

    private func noteRow(_ key: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(TT.amber.opacity(0.5))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 複製全部

    private func copyAll() {
        guard let result = result else { return }
        let text = """
        十進位：\(result.decimal)
        度分秒：\(result.dms)
        UTM：\(result.utm)
        TWD97(121)：\(result.twd97)
        TWD97(119)：\(result.twd97Alt)
        MGRS：\(result.mgrs)
        Plus Code：\(result.plus)
        """
        UIPasteboard.general.string = text
        copiedKey = "全部"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedKey == "全部" { copiedKey = "" }
        }
    }
}
