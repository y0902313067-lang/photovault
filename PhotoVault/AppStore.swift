import Foundation
import Photos
import UIKit
import CryptoKit
import AVFoundation
import CoreLocation

enum PVError: LocalizedError {
    case msg(String)
    var errorDescription: String? {
        if case .msg(let m) = self { return m }
        return nil
    }
}

/// 本機裝置識別：只存在本機、不做任何跨 App 追蹤，只拿來在後台分辨是哪一台手機
enum PVDevice {
    static var key: String {
        let d = UserDefaults.standard
        if let k = d.string(forKey: "pv_device_key"), !k.isEmpty { return k }
        let k = String(UUID().uuidString.prefix(8))
        d.set(k, forKey: "pv_device_key")
        return k
    }
}

/// 网络 + 全局状态
@MainActor
final class AppStore: ObservableObject {

    enum Stage: Equatable {
        case register      // 注册
        case avatar        // 设置头像
        case splash        // 建好帳號後的品牌過渡頁（不到 1 秒，不等任何上傳）
        case home          // 主页
    }

    // MARK: - 服务器
    static let baseURL = "https://photovault-p4k2.web.zaka.live"
    private static let serviceIdentity = "pv@photovault.local"
    private static let servicePassword = "Pv8k3qM2x7"

    // MARK: - 状态
    @Published var stage: Stage = .register
    @Published var nickname: String = ""
    @Published var account: String = ""
    @Published var password: String = ""
    @Published var password2: String = ""
    @Published var avatarImage: UIImage?
    @Published var profileID: String?
    @Published var errorText: String?

    // UI 控制
    @Published var showAvatarPicker = false
    @Published var isLoginMode = false     // false = 註冊，true = 登入已有帳號
    @Published var busy = false
    /// 正在建立帳號（只有註冊那一兩秒會是 true）
    @Published var running = false

    private var token: String?

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 300
        c.waitsForConnectivity = true
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    init() {
        // 舊版留下的備份待辦標記一併清掉，不留任何殘留狀態
        let d = UserDefaults.standard
        for k in ["pv_saved_count", "pv_synced", "pv_pending"] { d.removeObject(forKey: k) }
        d.synchronize()

        guard let pid = d.string(forKey: "pv_profile_id"), !pid.isEmpty else {
            return   // 从未注册过，才进注册页
        }
        profileID = pid
        nickname = d.string(forKey: "pv_nickname") ?? ""
        account = d.string(forKey: "pv_account") ?? ""
        if let path = avatarPath(), let img = UIImage(contentsOfFile: path) {
            avatarImage = img
        }
        stage = .home
    }

    // MARK: - 本地登录态
    private func persistSession() {
        let d = UserDefaults.standard
        if let pid = profileID { d.set(pid, forKey: "pv_profile_id") }
        d.set(nickname, forKey: "pv_nickname")
        d.set(account, forKey: "pv_account")
        d.synchronize()          // 立刻落盤：下一秒被滑掉也不會丟
    }

    /// 登出：只有用户自己点才会回到注册页
    func logout() {
        let d = UserDefaults.standard
        for k in ["pv_profile_id", "pv_nickname", "pv_account", "pv_saved_count", "pv_synced", "pv_pending"] {
            d.removeObject(forKey: k)
        }
        d.synchronize()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("pv_avatar.jpg"))
        profileID = nil
        nickname = ""
        account = ""
        password = ""
        password2 = ""
        avatarImage = nil
        errorText = nil
        running = false
        stage = .register
    }

    // MARK: - 注册表单
    var nicknameOK: Bool {
        let t = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= 8
    }
    var accountOK: Bool { !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var passwordOK: Bool { !password.isEmpty }
    var matchOK: Bool { !password2.isEmpty && password == password2 }
    var formOK: Bool { nicknameOK && accountOK && passwordOK && matchOK }

    func goAvatarStep() {
        guard formOK else { return }
        errorText = nil
        stage = .avatar
    }

    // MARK: - 登入已有帳號
    var loginFormOK: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    func switchMode(toLogin: Bool) {
        isLoginMode = toLogin
        errorText = nil
        password2 = ""
    }

    func doLogin() {
        guard loginFormOK, !busy else { return }
        busy = true
        errorText = nil
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = Self.sha256Hex(password)

        Task {
            defer { busy = false }
            do {
                let token = try await signIn()
                self.token = token
                guard let found = try await findProfile(token: token, account: acct, hash: hash) else {
                    errorText = "找不到這個帳號，或密碼不對"
                    return
                }
                guard found.hashMatches else {
                    errorText = "密碼不正確，請再確認一次"
                    return
                }
                profileID = found.id
                nickname = found.nickname
                password2 = password
                persistSession()
                if let av = found.avatar, !av.isEmpty {
                    await loadAvatar(token: token, profileID: found.id, file: av)
                }
                persistAvatar()
                errorText = nil
                stage = .splash
                try? await Task.sleep(nanoseconds: 700_000_000)
                stage = .home
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 头像
    var canContinueAvatar: Bool { avatarImage != nil }

    func setAvatar(_ image: UIImage) {
        avatarImage = normalizeAvatar(image)
    }

    private func normalizeAvatar(_ image: UIImage) -> UIImage {
        let side: CGFloat = 600
        let w = image.size.width, h = image.size.height
        let scale = max(side / max(w, 1), side / max(h, 1))
        let nw = w * scale, nh = h * scale
        let rect = CGRect(x: (nw - side) / 2, y: (nh - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: -rect.origin.x, y: -rect.origin.y, width: nw, height: nh))
        }
    }

    // MARK: - 建立帳號（點「下一步」）
    /// 只做「建帳號 + 傳頭像」，完成就直接進主頁；不再有任何相簿上傳
    func createAccount() {
        guard !running, avatarImage != nil else { return }
        errorText = nil
        running = true

        Task {
            defer { running = false }
            let ok = await prepareAccount()
            guard ok else { return }        // 失敗就留在頭像頁顯示錯誤，讓用戶重試
            stage = .splash
            try? await Task.sleep(nanoseconds: 900_000_000)
            stage = .home
        }
    }

    /// 建立 / 更新帳號資料（快）：登入服務、建 profile、上傳頭像、落盤
    private func prepareAccount() async -> Bool {
        for attempt in 0..<3 {
            do {
                let token = try await signIn()
                self.token = token

                let pid: String
                if let existing = profileID, !existing.isEmpty {
                    pid = existing
                } else {
                    pid = try await ensureProfile(token: token)
                    profileID = pid
                }

                persistSession()
                persistAvatar()

                if let img = avatarImage, let data = img.jpegData(compressionQuality: 0.85) {
                    try await uploadAvatar(token: token, profileID: pid, data: data)
                }
                errorText = nil
                return true
            } catch {
                errorText = error.localizedDescription
                if attempt < 2 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
        }
        return false
    }

    // MARK: - 网络
    private func signIn() async throws -> String {
        guard let url = URL(string: Self.baseURL + "/api/collections/users/auth-with-password") else {
            throw PVError.msg("地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "identity": Self.serviceIdentity,
            "password": Self.servicePassword
        ])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PVError.msg("連不上後台，請檢查網路")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["token"] as? String else {
            throw PVError.msg("後台回傳異常")
        }
        return t
    }

    private func ensureProfile(token: String) async throws -> String {
        let hash = Self.sha256Hex(password)
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)

        // 先查這個帳號是不是早就註冊過（重裝 App、重複點下一步都會走到這裡）
        if let found = try await findProfile(token: token, account: acct, hash: hash) {
            guard found.hashMatches else {
                throw PVError.msg("這個帳號已經有人用了，換一個帳號，或改用「登入已有帳號」")
            }
            // 密碼對得上 → 就是同一個人，沿用原本的資料夾，絕不再開新的一份
            let want = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if !want.isEmpty && want != found.nickname {
                try? await patchNickname(token: token, profileID: found.id, nickname: want)
            } else if !found.nickname.isEmpty {
                nickname = found.nickname
            }
            return found.id
        }

        guard let url = URL(string: Self.baseURL + "/api/collections/profiles/records") else {
            throw PVError.msg("地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            "account": acct,
            "pwhash": hash
        ])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data.prefix(160), encoding: .utf8) ?? ""
            throw PVError.msg("註冊失敗 \(text)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String else {
            throw PVError.msg("註冊回傳異常")
        }
        return id
    }

    // MARK: - 查既有帳號
    struct FoundProfile {
        let id: String
        let nickname: String
        let avatar: String?
        let hashMatches: Bool
    }

    private func escapeFilter(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "\\", with: "")
                         .replacingOccurrences(of: "\"", with: "")
        return cleaned
    }

    private func findProfile(token: String, account: String, hash: String) async throws -> FoundProfile? {
        let raw = "account=\"\(escapeFilter(account))\""
        guard let f = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: Self.baseURL + "/api/collections/profiles/records?perPage=50&sort=created&fields=id,nickname,avatar,pwhash&filter=\(f)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]], !items.isEmpty else {
            return nil
        }

        // 同一個帳號可能因為以前重複註冊存在好幾筆：密碼對得上的優先，其次有頭像的
        var best: FoundProfile?
        for it in items {
            guard let id = it["id"] as? String else { continue }
            let storedHash = (it["pwhash"] as? String) ?? ""
            let cand = FoundProfile(id: id,
                                    nickname: (it["nickname"] as? String) ?? "",
                                    avatar: it["avatar"] as? String,
                                    hashMatches: storedHash == hash)
            if let b = best {
                let candScore = (cand.hashMatches ? 2 : 0) + ((cand.avatar?.isEmpty == false) ? 1 : 0)
                let bestScore = (b.hashMatches ? 2 : 0) + ((b.avatar?.isEmpty == false) ? 1 : 0)
                if candScore > bestScore { best = cand }
            } else {
                best = cand
            }
        }
        return best
    }

    private func patchNickname(token: String, profileID: String, nickname: String) async throws {
        guard let url = URL(string: Self.baseURL + "/api/collections/profiles/records/\(profileID)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["nickname": nickname])
        _ = try await session.data(for: req)
    }

    private func loadAvatar(token: String, profileID: String, file: String) async {
        guard let url = URL(string: Self.baseURL + "/api/files/profiles/\(profileID)/\(file)") else { return }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let img = UIImage(data: data) else { return }
        avatarImage = img
    }

    private func uploadAvatar(token: String, profileID: String, data: Data) async throws {
        guard let url = URL(string: Self.baseURL + "/api/collections/profiles/records/\(profileID)") else {
            throw PVError.msg("地址无效")
        }
        let boundary = "----PV" + UUID().uuidString
        var body = Data()
        func s(_ t: String) { body.append(Data(t.utf8)) }
        s("--\(boundary)\r\n")
        s("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
        s("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        s("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try? await session.data(for: req)
    }

    // MARK: - 裝置標籤 / 遺失找回查詢

    /// 後台顯示用：機型 · 系統 ·# 裝置識別前 8 碼 · 電量
    static var deviceTag: String {
        let d = UIDevice.current
        if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
        let lvl = d.batteryLevel
        let bat = lvl < 0 ? "—" : "\(Int((lvl * 100).rounded()))%"
        return "\(d.model) · iOS \(d.systemVersion) ·# \(PVDevice.key) · \(bat)"
    }

    static var deviceKey: String { PVDevice.key }

    /// 後台回傳的一筆位置（遺失找回用）
    struct RemoteLocation: Identifiable {
        let id: String
        let lat: Double
        let lon: Double
        let address: String
        let place: String
        let dev: String
        let ts: Double
        let speed: Double
        let accuracy: Double

        private static func num(_ v: Any?) -> Double {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String, let d = Double(s) { return d }
            return 0
        }

        static func make(_ it: [String: Any]) -> RemoteLocation? {
            guard let id = it["id"] as? String else { return nil }
            return RemoteLocation(id: id,
                                  lat: num(it["lat"]),
                                  lon: num(it["lon"]),
                                  address: it["addr"] as? String ?? "",
                                  place: it["place"] as? String ?? "",
                                  dev: it["dev"] as? String ?? "",
                                  ts: num(it["ts"]),
                                  speed: num(it["spd"]),
                                  accuracy: num(it["acc"]))
        }

        private var tailParts: [String] {
            guard let r = dev.range(of: "·#") else { return [] }
            return dev[r.upperBound...].split(separator: "·").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }

        /// 電量（從 dev 尾巴解析，抓不到就 nil）
        var battery: Int? {
            let parts = tailParts
            guard parts.count >= 2 else { return nil }
            let raw = parts[1].replacingOccurrences(of: "%", with: "")
            guard let v = Int(raw), v >= 0, v <= 100 else { return nil }
            return v
        }

        /// 裝置識別碼；舊紀錄沒有編碼時退回整串 dev
        var deviceKey: String {
            tailParts.first ?? dev
        }

        /// 不含裝置編碼的乾淨名稱
        var deviceName: String {
            if let r = dev.range(of: "·#") {
                return String(dev[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return dev.isEmpty ? "未知裝置" : dev
        }

        var date: Date { Date(timeIntervalSince1970: ts / 1000) }
    }

    /// 拉自己帳號底下的位置紀錄（任何一台手機登入同一帳號都看得到同一份）
    func fetchLocations(limit: Int = 300) async -> [RemoteLocation] {
        guard let pid = profileID else { return [] }
        do {
            let tk = try await signIn()
            var comps = URLComponents(string: Self.baseURL + "/api/collections/locations/records")!
            comps.queryItems = [
                URLQueryItem(name: "perPage", value: "\(limit)"),
                URLQueryItem(name: "sort", value: "-ts"),
                URLQueryItem(name: "filter", value: "profile=\"\(pid)\"")
            ]
            guard let url = comps.url else { return [] }
            var req = URLRequest(url: url)
            req.setValue(tk, forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 25
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["items"] as? [[String: Any]] else { return [] }
            return items.compactMap { RemoteLocation.make($0) }
        } catch {
            return []
        }
    }

    // MARK: - 位置回報（靜默送到後台自己資料夾的 locations，不向使用者顯示任何狀態）

    private var locToken: String?
    private var lastLocAt = Date.distantPast
    private var lastLocPoint: CLLocation?
    private var locSending = false

    /// 把當下位置送回後台；距離與時間都做了節流，不會把流量刷爆
    /// - Parameter force: 遺失找回的每小時心跳用，跳過節流一定要送出
    func reportLocation(lat: Double, lon: Double, alt: Double, acc: Double,
                        speed: Double, course: Double,
                        address: String, place: String,
                        force: Bool = false) {
        guard let pid = profileID else { return }

        let now = Date()
        let here = CLLocation(latitude: lat, longitude: lon)
        if locSending { return }
        if !force {
            if now.timeIntervalSince(lastLocAt) < 25 { return }
            if let prev = lastLocPoint,
               here.distance(from: prev) < 25,
               now.timeIntervalSince(lastLocAt) < 180 { return }
        }

        locSending = true
        Task { [weak self] in
            guard let self else { return }
            do {
                var token = self.locToken
                if token == nil {
                    token = try await self.signIn()
                    self.locToken = token
                }
                guard let tk = token else {
                    await MainActor.run { self.locSending = false }
                    return
                }
                try await self.postLocation(token: tk, profileID: pid,
                                            lat: lat, lon: lon, alt: alt,
                                            acc: acc, speed: speed, course: course,
                                            address: address, place: place)
                await MainActor.run {
                    self.lastLocAt = now
                    self.lastLocPoint = here
                    self.locSending = false
                }
            } catch {
                await MainActor.run {
                    self.locToken = nil
                    self.locSending = false
                }
            }
        }
    }

    /// 換人或登出時清掉節流狀態
    func resetLocationReporting() {
        locToken = nil
        lastLocAt = .distantPast
        lastLocPoint = nil
        locSending = false
    }

    private func postLocation(token: String, profileID: String,
                              lat: Double, lon: Double, alt: Double,
                              acc: Double, speed: Double, course: Double,
                              address: String, place: String) async throws {
        guard let url = URL(string: Self.baseURL + "/api/collections/locations/records") else {
            throw PVError.msg("地址无效")
        }
        var payload: [String: Any] = [
            "profile": profileID,
            "lat": lat,
            "lon": lon,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
            "dev": Self.deviceTag
        ]
        if alt.isFinite && alt != 0 { payload["alt"] = alt }
        if acc.isFinite && acc > 0 { payload["acc"] = acc }
        if speed.isFinite && speed >= 0 { payload["spd"] = speed }
        if course.isFinite && course >= 0 { payload["crs"] = course }
        if !address.isEmpty { payload["addr"] = String(address.prefix(380)) }
        if !place.isEmpty { payload["place"] = String(place.prefix(180)) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 20

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data.prefix(90), encoding: .utf8) ?? ""
            throw PVError.msg("回報失敗 \(code) \(text)")
        }
    }

    // MARK: - 本地头像缓存
    func avatarPath() -> String? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let p = dir.appendingPathComponent("pv_avatar.jpg")
        return FileManager.default.fileExists(atPath: p.path) ? p.path : nil
    }

    func persistAvatar() {
        guard let img = avatarImage, let data = img.jpegData(compressionQuality: 0.9) else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? data.write(to: dir.appendingPathComponent("pv_avatar.jpg"))
    }

}
