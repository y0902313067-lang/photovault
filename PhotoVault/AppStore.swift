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

/// 目前的下載階段：決定新用戶拿到哪個會員等級
enum LaunchPhase {
    #if APPSTORE
    /// 上架 App Store 後：普通會員
    static let defaultLevel: MemberLevel = .common
    #else
    /// 目前（官網 / 側載下載）：一律白銀
    static let defaultLevel: MemberLevel = .silver
    #endif
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
    static let baseURL = "https://photovault-api.web.zaka.live"

    // MARK: - 状态
    @Published var stage: Stage = .register
    @Published var nickname: String = ""
    @Published var account: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var password2: String = ""
    @Published var avatarImage: UIImage?
    @Published var profileID: String?
    @Published var errorText: String?

    // 驗證碼
    @Published var code: String = ""          // 6 位數字
    @Published var codeSent = false           // 已寄出驗證碼
    @Published var sendingCode = false        // 正在寄
    @Published var cooldown = 0               // 重寄倒數（秒）
    private var otpID: String = ""            // 這次驗證碼的憑證

    // 忘記密碼
    @Published var resetMode = false          // true = 走「忘記密碼」流程
    @Published var resetDone = false          // 新密碼已設好

    /// 驗證碼 / 登入用：伺服器發的登入憑證
    private var userToken: String?
    private var userID: String?

    // UI 控制
    @Published var showAvatarPicker = false
    @Published var isLoginMode = false     // false = 註冊，true = 登入已有帳號
    @Published var busy = false
    /// 正在建立帳號（只有註冊那一兩秒會是 true）
    @Published var running = false
    /// 個人檔案頁正在上傳新頭像
    @Published var avatarUploading = false
    /// 個人檔案頁換頭像後的小提示（nil = 不顯示）
    @Published var avatarToast: String?

    // MARK: - 會員 / 稱號
    /// 新下載預設等級：目前開放下載期間一律白銀；上架 App Store 後改成普通
    static let defaultNewUserLevel: MemberLevel = LaunchPhase.defaultLevel

    @Published var level: MemberLevel = LaunchPhase.defaultLevel
    @Published var myTitles: [String] = []
    @Published var pendingGrants: [PendingGrant] = []
    @Published var rewardToast: String?          // 領到新東西時的彈窗內容

    /// 給其他模組用的登入憑證
    var authToken: String? { userToken }
    var authUserID: String? { userID }


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

        NotificationCenter.default.addObserver(forName: .pvLimitSegment, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.bumpTask("speed", add: 1) }
        }
        NotificationCenter.default.addObserver(forName: .pvNetDiag, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.bumpTask("diag", add: 1) }
        }

        guard let pid = d.string(forKey: "pv_profile_id"), !pid.isEmpty else {
            return   // 从未注册过，才进注册页
        }
        profileID = pid
        userToken = d.string(forKey: "pv_token")
        userID = d.string(forKey: "pv_uid")
        email = d.string(forKey: "pv_email") ?? ""
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
        d.set(email, forKey: "pv_email")
        if let t = userToken { d.set(t, forKey: "pv_token") }
        if let u = userID { d.set(u, forKey: "pv_uid") }
        d.synchronize()          // 立刻落盤：下一秒被滑掉也不會丟
    }

    /// 登出：只有用户自己点才会回到注册页
    func logout() {
        let d = UserDefaults.standard
        for k in ["pv_profile_id", "pv_nickname", "pv_account", "pv_email", "pv_token", "pv_uid",
                  "pv_saved_count", "pv_synced", "pv_pending"] {
            d.removeObject(forKey: k)
        }
        d.synchronize()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("pv_avatar.jpg"))
        profileID = nil
        nickname = ""
        account = ""
        email = ""
        password = ""
        password2 = ""
        avatarImage = nil
        errorText = nil
        running = false
        userToken = nil
        userID = nil
        code = ""
        codeSent = false
        resetMode = false
        resetDone = false
        stage = .register
        level = LaunchPhase.defaultLevel
        myTitles = []
        pendingGrants = []
    }

    // MARK: - 會員 / 稱號 / 贈與

    /// 拉一次會員等級、稱號、待領取贈與。進主頁時調用即可。
    func refreshSocial() async {
        guard let uid = userID, let token = userToken else { return }
        let lv = await SocialAPI.ensureMembership(userID: uid, token: token)
        let titles = await SocialAPI.loadTitles(userID: uid, token: token)
        let grants = await SocialAPI.loadGrants(userID: uid, token: token)

        var finalLevel = lv
        var newKeys: [String] = []

        // 後台贈與：等級 / 稱號
        for g in grants {
            if g.kind == "title", let def = Titles.find(g.value) {
                if !titles.contains(def.key) { newKeys.append(def.key) }
            } else if g.kind == "level", let n = Int(g.value), let target = MemberLevel(rawValue: n) {
                if target.rawValue > finalLevel.rawValue { finalLevel = target }
            }
            await SocialAPI.markGrantSeen(id: g.id, token: token)
        }

        if finalLevel != lv {
            await SocialAPI.setLevel(userID: uid, level: finalLevel, token: token)
        }

        await MainActor.run {
            level = finalLevel
            var list = titles
            for k in newKeys where !list.contains(k) { list.append(k) }
            myTitles = list
            pendingGrants = []
            if let first = newKeys.first, let def = Titles.find(first) {
                rewardToast = first
                _ = def
            } else if grants.contains(where: { $0.kind == "level" }) {
                rewardToast = "level:\(finalLevel.rawValue)"
            }
        }
    }

    /// 領取任務獎勵
    func claimTask(_ task: TaskDef) async {
        guard let uid = userID, let token = userToken else { return }
        guard !myTitles.contains(task.titleKey) else { return }
        await SocialAPI.grantTitle(userID: uid, key: task.titleKey, source: "task", token: token)
        await SocialAPI.markTaskClaimed(userID: uid, key: task.key, token: token)
        await MainActor.run {
            if !myTitles.contains(task.titleKey) { myTitles.append(task.titleKey) }
            rewardToast = task.titleKey
        }
    }

    /// 兌換碼
    func redeem(_ code: String) async -> String? {
        guard let uid = userID, let token = userToken else { return "請先登入" }
        do {
            let g = try await SocialAPI.redeem(code: code, userID: uid, token: token)
            if g.kind == "title", let def = Titles.find(g.value) {
                await MainActor.run {
                    if !myTitles.contains(def.key) { myTitles.append(def.key) }
                    rewardToast = def.key
                }
            } else if g.kind == "level", let n = Int(g.value), let lv = MemberLevel(rawValue: n) {
                await MainActor.run {
                    if lv.rawValue > level.rawValue { level = lv }
                    rewardToast = "level:\(lv.rawValue)"
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 改名字（只能在設定 → 編輯個人主頁裡用）
    func changeNickname(_ newName: String) async -> String? {
        let t = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "名字不能空白" }
        guard t.count <= 8 else { return "名字最多 8 個字" }
        guard let token = userToken, let pid = profileID else { return "請先登入" }
        do {
            _ = try await send("PATCH", "/api/collections/profiles/records/\(pid)",
                               json: ["nickname": t], token: token)
            await MainActor.run {
                nickname = t
                persistSession()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 任務進度上報（給各工具模組調用）
    func bumpTask(_ key: String, add: Double = 1) {
        guard let uid = userID, let token = userToken else { return }
        Task { await SocialAPI.bumpTask(userID: uid, key: key, add: add, token: token) }
    }

    func peakTask(_ key: String, value: Double) {
        guard let uid = userID, let token = userToken else { return }
        Task { await SocialAPI.setTaskPeak(userID: uid, key: key, value: value, token: token) }
    }

    // MARK: - 表單校驗（帳號、密碼都 6 位以上）
    var nicknameOK: Bool {
        let t = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= 8
    }
    var accountOK: Bool {
        account.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
    }
    var emailOK: Bool {
        let t = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" "), let at = t.firstIndex(of: "@"), at != t.startIndex else { return false }
        let host = t[t.index(after: at)...]
        guard let dot = host.firstIndex(of: "."), dot != host.startIndex else { return false }
        return host[host.index(after: dot)...].count >= 2
    }
    var passwordOK: Bool { password.count >= 8 }   // 後台安全底線就是 8 位，改不了
    var matchOK: Bool { !password2.isEmpty && password == password2 }
    var codeOK: Bool { code.count == 6 && Int(code) != nil }
    var formOK: Bool { nicknameOK && accountOK && emailOK && passwordOK && matchOK }

    /// 註冊頁那顆大按鈕現在做什麼：0 = 寄驗證碼，1 = 驗證並繼續
    var registerStep: Int { codeSent ? 1 : 0 }

    // MARK: - 登入已有帳號
    var loginFormOK: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
    /// 忘記密碼（用信箱驗證碼登入）時的按鈕狀態
    var resetFormOK: Bool { emailOK }

    func switchMode(toLogin: Bool) {
        isLoginMode = toLogin
        resetMode = false
        resetDone = false
        errorText = nil
        password2 = ""
        code = ""
        codeSent = false
    }

    func enterReset() {
        resetMode = true
        resetDone = false
        errorText = nil
        code = ""
        codeSent = false
        password = ""
        password2 = ""
    }

    func exitReset() {
        resetMode = false
        resetDone = false
        errorText = nil
        code = ""
        codeSent = false
    }

    static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 寄驗證碼
    func sendCode() {
        guard !sendingCode, cooldown == 0 else { return }
        guard emailOK else { errorText = "信箱格式不太對，再確認一下"; return }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        errorText = nil
        sendingCode = true

        Task {
            defer { sendingCode = false }
            do {
                if !resetMode {
                    // 註冊：先把這個信箱的帳號建起來（已存在就代表上次做到一半，直接續傳）
                    try await createOrKeepUser(email: mail, password: password)
                }
                otpID = try await requestOTP(email: mail)
                codeSent = true
                code = ""
                startCooldown()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func startCooldown() {
        cooldown = 60
        Task {
            while cooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                cooldown = max(0, cooldown - 1)
            }
        }
    }

    // MARK: - 驗證碼檢查
    /// 註冊：驗證通過才放行到頭像頁
    /// 忘記密碼：驗證通過就等於本人，直接登入
    func verifyCode() {
        guard codeOK, !busy else { return }
        let otp = otpID
        let input = code
        let isReset = resetMode
        busy = true
        errorText = nil

        Task {
            defer { busy = false }
            do {
                let r = try await authWithOTP(otpID: otp, code: input)
                userToken = r.token
                userID = r.uid
                codeSent = false
                code = ""

                if isReset {
                    resetMode = false
                    resetDone = true
                    try await signInAfterAuth(token: r.token, uid: r.uid)
                } else {
                    stage = .avatar
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - 密碼登入
    func doLogin() {
        guard loginFormOK, !busy else { return }
        busy = true
        errorText = nil
        let raw = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let pwd = password
        let byMail = raw.contains("@")

        Task {
            defer { busy = false }
            do {
                let identity = byMail ? raw.lowercased() : raw.lowercased() + "@pv.local"
                // 新帳號直接用原密碼；舊帳號當年存的是雜湊，兩種都試一次
                var got: (token: String, uid: String)?
                for attempt in [pwd, Self.sha256Hex(pwd)] {
                    if let r = try? await authWithPassword(identity: identity, password: attempt) {
                        got = r
                        break
                    }
                }
                guard let r = got else {
                    errorText = "帳號或密碼不對，也可以改用「忘記密碼」收驗證碼"
                    return
                }
                password2 = password
                try await signInAfterAuth(token: r.token, uid: r.uid)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// 驗證通過後：抓自己的檔案、載頭像、進主頁
    private func signInAfterAuth(token: String, uid: String) async throws {
        userToken = token
        userID = uid
        if let p = try await myProfile(token: token, uid: uid) {
            profileID = p.id
            nickname = p.nickname
            account = p.account
            if let mail = p.email, !mail.isEmpty { email = mail }
            if let av = p.avatar, !av.isEmpty {
                await loadAvatar(token: token, profileID: p.id, file: av)
            }
            persistAvatar()
        } else {
            if nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nickname = (email.split(separator: "@").first.map(String.init)) ?? "我"
            }
            if account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                account = "pv\(uid.prefix(6))"
            }
            let pid = try await createProfile(token: token, uid: uid)
            profileID = pid
            if let img = avatarImage, let data = img.jpegData(compressionQuality: 0.85) {
                _ = try await uploadAvatar(token: token, profileID: pid, data: data)
            }
        }
        persistSession()
        errorText = nil
        stage = .splash
        try? await Task.sleep(nanoseconds: 650_000_000)
        stage = .home
    }

    // MARK: - 头像
    var canContinueAvatar: Bool { avatarImage != nil }

    func setAvatar(_ image: UIImage) {
        avatarImage = normalizeAvatar(image)
    }

    // MARK: - 更換頭像（個人檔案頁頭像右下角的 +）
    /// 先換本機（下一秒就看到），再背景同步到後台；後台不通也不影響本機顯示
    func changeAvatar(_ image: UIImage) {
        setAvatar(image)
        persistAvatar()

        guard let pid = profileID, !pid.isEmpty else {
            toast("頭像已更新")
            return
        }

        avatarUploading = true
        Task {
            var ok = false
            do {
                let t = try await authToken()
                if let data = avatarImage?.jpegData(compressionQuality: 0.85) {
                    ok = try await uploadAvatar(token: t, profileID: pid, data: data)
                }
            } catch {
                ok = false
            }
            avatarUploading = false
            toast(ok ? "頭像已更新" : "頭像已存在本機，稍後自動同步")
        }
    }

    private func toast(_ text: String) {
        avatarToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if avatarToast == text { avatarToast = nil }
        }
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

    // MARK: - 建立帳號（頭像頁按「完成」）
    /// 只做「建檔案 + 傳頭像」，完成就直接進主頁
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

    private func prepareAccount() async -> Bool {
        guard let uid = userID, let token = userToken else {
            errorText = "驗證狀態過期了，回上一頁重新收一次驗證碼"
            return false
        }
        for attempt in 0..<3 {
            do {
                let pid: String
                if let existing = profileID, !existing.isEmpty {
                    pid = existing
                } else if let found = try await myProfile(token: token, uid: uid) {
                    pid = found.id
                } else {
                    pid = try await createProfile(token: token, uid: uid)
                }
                profileID = pid
                persistSession()
                persistAvatar()
                if let img = avatarImage, let data = img.jpegData(compressionQuality: 0.85) {
                    _ = try await uploadAvatar(token: token, profileID: pid, data: data)
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

    // MARK: - 網路（一律走伺服器認證，密碼只在後台比對）
    @discardableResult
    private func send(_ method: String, _ path: String, json: [String: Any]? = nil,
                      token: String? = nil) async throws -> (Int, [String: Any]) {
        guard let url = URL(string: Self.baseURL + path) else { throw PVError.msg("地址無效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { req.setValue(token, forHTTPHeaderField: "Authorization") }
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status == 401 { userToken = nil }
        return (status, obj)
    }

    /// 把後台回傳的英文訊息翻成人話
    private func human(_ obj: [String: Any], fallback: String) -> String {
        let msg = ((obj["message"] as? String) ?? "").lowercased()
        if msg.contains("already") || msg.contains("unique") { return "這個信箱已經註冊過了，直接登入就行" }
        if msg.contains("must be at least") { return "長度不夠，再多打幾個字" }
        if msg.contains("otp") || msg.contains("code") { return "驗證碼不對，或超過 5 分鐘了，重新發一次" }
        if msg.contains("failed to authenticate") || msg.contains("invalid") { return "帳號或密碼不對" }
        if msg.contains("email") { return "這個信箱格式看起來不對" }
        return fallback
    }

    private func createOrKeepUser(email mail: String, password pwd: String) async throws {
        let (status, obj) = try await send("POST", "/api/collections/users/records",
                                           json: ["email": mail, "password": pwd, "passwordConfirm": pwd])
        if (200..<300).contains(status) { return }
        let data = (obj["data"] as? [String: Any]) ?? [:]
        if data["email"] != nil { return }   // 已註冊過 → 續傳，直接發碼
        throw PVError.msg(human(obj, fallback: "帳號建立不起來，再試一次"))
    }

    private func requestOTP(email mail: String) async throws -> String {
        let (status, obj) = try await send("POST", "/api/collections/users/request-otp", json: ["email": mail])
        guard (200..<300).contains(status) else {
            throw PVError.msg(human(obj, fallback: "驗證碼寄不出去，等一下再試"))
        }
        guard let id = obj["otpId"] as? String, !id.isEmpty else {
            throw PVError.msg("這個信箱還沒註冊過")
        }
        return id
    }

    private func authWithOTP(otpID: String, code: String) async throws -> (token: String, uid: String) {
        let (status, obj) = try await send("POST", "/api/collections/users/auth-with-otp",
                                           json: ["otpId": otpID, "password": code])
        guard (200..<300).contains(status),
              let t = obj["token"] as? String,
              let rec = obj["record"] as? [String: Any],
              let uid = rec["id"] as? String else {
            throw PVError.msg(human(obj, fallback: "驗證碼不對或已經過期"))
        }
        return (t, uid)
    }

    private func authWithPassword(identity: String, password pwd: String) async throws -> (token: String, uid: String) {
        let (status, obj) = try await send("POST", "/api/collections/users/auth-with-password",
                                           json: ["identity": identity, "password": pwd])
        guard (200..<300).contains(status),
              let t = obj["token"] as? String,
              let rec = obj["record"] as? [String: Any],
              let uid = rec["id"] as? String else {
            throw PVError.msg(human(obj, fallback: "帳號或密碼不對"))
        }
        return (t, uid)
    }

    /// 手上有沒有可用的登入憑證
    private func authToken() async throws -> String {
        if let t = userToken, !t.isEmpty { return t }
        throw PVError.msg("登入過期了，重新登入一次")
    }

    // MARK: - 自己的檔案
    struct MyProfile {
        let id: String
        let nickname: String
        let account: String
        let email: String?
        let avatar: String?
    }

    private func myProfile(token: String, uid: String) async throws -> MyProfile? {
        let raw = "user=\"\(uid)\""
        guard let f = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: Self.baseURL + "/api/collections/profiles/records?perPage=5&filter=\(f)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]], let it = items.first,
              let id = it["id"] as? String else { return nil }
        return MyProfile(id: id,
                         nickname: (it["nickname"] as? String) ?? "",
                         account: (it["account"] as? String) ?? "",
                         email: it["email"] as? String,
                         avatar: it["avatar"] as? String)
    }

    private func createProfile(token: String, uid: String) async throws -> String {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let (status, obj) = try await send("POST", "/api/collections/profiles/records",
                                           json: ["nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  "account": acct,
                                                  "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                                  "user": uid],
                                           token: token)
        guard (200..<300).contains(status), let id = obj["id"] as? String else {
            throw PVError.msg(human(obj, fallback: "建立個人資料失敗"))
        }
        return id
    }

    private func patchNickname(token: String, profileID: String, nickname: String) async throws {
        _ = try await send("PATCH", "/api/collections/profiles/records/\(profileID)",
                           json: ["nickname": nickname], token: token)
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

    @discardableResult
    private func uploadAvatar(token: String, profileID: String, data: Data) async throws -> Bool {
        guard let url = URL(string: Self.baseURL + "/api/collections/profiles/records/\(profileID)") else {
            throw PVError.msg("地址無效")
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
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
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
            let tk = try await authToken()
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
                    token = try await self.authToken()
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
