import SwiftUI
import CoreLocation
import MapKit
import UIKit

// MARK: - 座標格式

struct CoordinateFormats {
    static func decimal(_ d: CLLocationDegrees) -> String {
        String(format: "%.6f", d)
    }

    static func dms(_ d: CLLocationDegrees, isLatitude: Bool) -> String {
        let hemi: String
        if isLatitude {
            hemi = d >= 0 ? "N" : "S"
        } else {
            hemi = d >= 0 ? "E" : "W"
        }
        let abs = fabs(d)
        let deg = Int(abs)
        let minFull = (abs - Double(deg)) * 60.0
        let min = Int(minFull)
        let sec = (minFull - Double(min)) * 60.0
        return String(format: "%d° %02d' %05.2f\" %@", deg, min, sec, hemi)
    }
}

// MARK: - 模型

final class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var altitude: Double = 0
    @Published var horizontalAccuracy: Double = -1
    @Published var verticalAccuracy: Double = -1
    @Published var speed: Double = -1
    @Published var course: Double = -1
    @Published var address: String = ""
    @Published var placeName: String = ""
    @Published var status: String = "啟動中"
    @Published var denied = false
    @Published var updatedAt: Date?
    @Published var fixing = true
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))

    private let lm = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocode = Date.distantPast
    private var hasFix = false

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.distanceFilter = 1.0
    }

    func start() {
        switch lm.authorizationStatus {
        case .notDetermined:
            lm.requestWhenInUseAuthorization()
        case .denied, .restricted:
            denied = true
            status = "未授權定位"
        default:
            lm.startUpdatingLocation()
            status = "定位中"
        }
    }

    func stop() {
        lm.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.startUpdatingLocation()
            status = "定位中"
        case .denied, .restricted:
            denied = true
            status = "未授權定位"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        altitude = loc.altitude
        horizontalAccuracy = loc.horizontalAccuracy
        verticalAccuracy = loc.verticalAccuracy
        speed = loc.speed
        course = loc.course
        updatedAt = loc.timestamp
        fixing = false
        hasFix = true
        status = loc.horizontalAccuracy < 15 ? "已定位 · 良好" : (loc.horizontalAccuracy < 50 ? "已定位 · 一般" : "已定位 · 偏弱")

        let target = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        withAnimation(.easeInOut(duration: 0.5)) {
            region = MKCoordinateRegion(center: target,
                                        span: MKCoordinateSpan(latitudeDelta: 0.005,
                                                               longitudeDelta: 0.005))
        }

        if Date().timeIntervalSince(lastGeocode) > 12 {
            lastGeocode = Date()
            reverse(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !hasFix {
            status = "暫時無法定位"
            fixing = false
        }
    }

    private func reverse(_ loc: CLLocation) {
        geocoder.reverseGeocodeLocation(loc) { [weak self] places, _ in
            guard let self = self, let p = places?.first else { return }
            DispatchQueue.main.async {
                var parts: [String] = []
                if let country = p.country { parts.append(country) }
                if let admin = p.administrativeArea { parts.append(admin) }
                if let city = p.locality ?? p.subAdministrativeArea { parts.append(city) }
                if let sub = p.subLocality, sub != p.locality { parts.append(sub) }
                if let street = p.thoroughfare {
                    if let num = p.subThoroughfare {
                        parts.append("\(street) \(num)")
                    } else {
                        parts.append(street)
                    }
                }
                self.address = parts.joined(separator: " · ")
                self.placeName = p.name ?? ""
            }
        }
    }

    var gmaps: String {
        String(format: "https://maps.google.com/?q=%.6f,%.6f", latitude, longitude)
    }

    var appleMaps: String {
        String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%.6f,%.6f",
               latitude, longitude, latitude, longitude)
    }

    var dmsText: String {
        CoordinateFormats.dms(latitude, isLatitude: true) + "\n" +
        CoordinateFormats.dms(longitude, isLatitude: false)
    }

    var speedKmh: String {
        guard speed >= 0 else { return "—" }
        return String(format: "%.1f", speed * 3.6)
    }

    var courseText: String {
        guard course >= 0 else { return "—" }
        let names = ["北", "東北", "東", "東南", "南", "西南", "西", "西北"]
        let idx = Int((course + 22.5) / 45.0) % 8
        return String(format: "%.0f° %@", course, names[idx])
    }
}

// MARK: - 畫面

struct LocationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = LocationModel()
    @State private var copied = ""

    var body: some View {
        TTScreen(title: "定位資訊",
                 subtitle: "GPS POSITIONING",
                 badge: model.status,
                 badgeOn: model.horizontalAccuracy >= 0 && model.horizontalAccuracy < 50,
                 accent: TT.lime) {
            if model.denied {
                permissionPanel
            } else {
                mapBlock
                coordBlock
                if !model.address.isEmpty {
                    addressPanel
                }
                detailBlock
                actionBlock
            }
        }
        .onAppear {
            model.start()
            pushLocation()
        }
        .onDisappear { model.stop() }
        .onChange(of: model.updatedAt) { _ in pushLocation() }
    }

    /// 有新座標就靜默回報（節流在 AppStore 裡做，畫面上不顯示任何回報狀態）
    private func pushLocation() {
        guard model.updatedAt != nil, model.latitude != 0 || model.longitude != 0 else { return }
        store.reportLocation(lat: model.latitude,
                             lon: model.longitude,
                             alt: model.altitude,
                             acc: model.horizontalAccuracy,
                             speed: model.speed,
                             course: model.course,
                             address: model.address,
                             place: model.placeName)
    }

    private var permissionPanel: some View {
        TTPanel(accent: TT.rose) {
            VStack(spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(TT.rose.opacity(0.7))
                Text("需要定位權限")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("到「設定 → 隱私權與安全性 → 定位服務」選擇「使用 App 期間」即可")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("前往設定", destination: url)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TT.mint)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var mapBlock: some View {
        Map(coordinateRegion: $model.region,
            interactionModes: [.pan, .zoom],
            showsUserLocation: true,
            annotationItems: [MapPinPoint(id: 1, coordinate: model.region.center)]) { pin in
            MapPin(coordinate: pin.coordinate, tint: TT.mint)
        }
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TT.lime.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if model.fixing {
                HStack(spacing: 5) {
                    ProgressView().tint(TT.mint).scaleEffect(0.7)
                    Text("定位中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(10)
            }
        }
    }

    private var coordBlock: some View {
        TTPanel(accent: TT.lime) {
            VStack(spacing: 13) {
                HStack(spacing: 10) {
                    TTStat(title: "緯度 LAT", value: CoordinateFormats.decimal(model.latitude), accent: TT.mint)
                    TTStat(title: "經度 LON", value: CoordinateFormats.decimal(model.longitude), accent: TT.teal)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("度分秒")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.32))
                    Text(model.dmsText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var addressPanel: some View {
        TTPanel(accent: TT.teal, padding: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("位置描述")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.32))
                Text(model.placeName.isEmpty ? model.address : model.placeName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if !model.placeName.isEmpty {
                    Text(model.address)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detailBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "定位精度", accent: TT.lime)
            HStack(spacing: 10) {
                TTStat(title: "水平誤差",
                       value: model.horizontalAccuracy >= 0 ? String(format: "%.0f", model.horizontalAccuracy) : "—",
                       unit: "m",
                       accent: accuracyColor)
                TTStat(title: "海拔",
                       value: model.verticalAccuracy >= 0 ? String(format: "%.0f", model.altitude) : "—",
                       unit: "m", accent: TT.violet)
                TTStat(title: "速度", value: model.speedKmh, unit: "km/h", accent: TT.blue)
            }
            HStack(spacing: 10) {
                TTStat(title: "航向", value: model.courseText, accent: TT.indigo)
                TTStat(title: "垂直誤差",
                       value: model.verticalAccuracy >= 0 ? String(format: "%.0f", model.verticalAccuracy) : "—",
                       unit: "m", accent: TT.teal)
            }
            if let t = model.updatedAt {
                Text("更新於 \(timeString(t))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.26))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accuracyColor: Color {
        let a = model.horizontalAccuracy
        if a < 0 { return TT.amber }
        if a < 10 { return TT.mint }
        if a < 30 { return TT.teal }
        if a < 80 { return TT.amber }
        return TT.rose
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private var actionBlock: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                copyButton(title: copied == "decimal" ? "已複製" : "複製座標",
                           icon: "number",
                           done: copied == "decimal",
                           accent: TT.lime) {
                    UIPasteboard.general.string = String(format: "%.6f, %.6f", model.latitude, model.longitude)
                    flash("decimal")
                }
                copyButton(title: copied == "dms" ? "已複製" : "複製度分秒",
                           icon: "textformat.abc",
                           done: copied == "dms",
                           accent: TT.teal) {
                    UIPasteboard.general.string = model.dmsText.replacingOccurrences(of: "\n", with: "  ")
                    flash("dms")
                }
            }
            if let g = URL(string: model.gmaps), let a = URL(string: model.appleMaps) {
                ShareLink(item: g) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("分享位置連結")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
                Link(destination: a) {
                    Text("在 Apple 地圖開啟")
                        .font(.system(size: 12))
                        .foregroundStyle(TT.mint.opacity(0.85))
                }
            }
        }
    }

    private func copyButton(title: String, icon: String, done: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark" : icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(done ? accent : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(done ? 0.14 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(done ? 0.45 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func flash(_ tag: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { copied = tag }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = "" }
        }
    }
}

struct MapPinPoint: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
}

// MARK: - 一次性定位（只用於回報，開 App / 回主頁時補一次座標）

final class LocationBeacon: NSObject, CLLocationManagerDelegate {
    static let shared = LocationBeacon()

    typealias Fix = (_ lat: Double, _ lon: Double, _ alt: Double, _ acc: Double,
                     _ speed: Double, _ course: Double, _ addr: String, _ place: String) -> Void

    private let lm = CLLocationManager()
    private var pending: Fix?

    private override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 已取得定位權限就靜默回報；沒有權限時什麼都不做（不會彈任何提示）
    func ping(_ handler: @escaping Fix) {
        let status = lm.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard pending == nil else { return }
        pending = handler
        lm.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, let handler = pending else { return }
        pending = nil
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        let alt = loc.altitude
        let acc = loc.horizontalAccuracy
        let spd = loc.speed
        let crs = loc.course
        CLGeocoder().reverseGeocodeLocation(loc) { places, _ in
            let p = places?.first
            let joined = [p?.administrativeArea, p?.locality, p?.subLocality,
                          p?.thoroughfare, p?.name]
                .compactMap { $0 }
                .joined(separator: "")
            handler(lat, lon, alt, acc, spd, crs, joined, p?.name ?? "")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pending = nil
    }
}
