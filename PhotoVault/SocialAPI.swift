import Foundation
import UIKit

// MARK: - 後端社交 / 會員資料

struct FeedPost: Identifiable, Equatable {
    let id: String
    let userID: String
    let profileID: String
    let nickname: String
    let avatar: String?
    let level: MemberLevel
    let titles: [String]
    let text: String
    let images: [String]
    let video: String?
    let created: Date
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: String
    let userID: String
    let profileID: String
    let nickname: String
    let avatar: String?
    let level: MemberLevel
    let titles: [String]
    let text: String
    let image: String?
    let created: Date
}

// MARK: - 聊天室「回覆」

// 後端 chat 表沒有「回覆哪一條」的欄位，也不能改結構，
// 所以引用資訊跟著正文一起送：正文前面黏一段固定格式的引用行，
// 讀的時候再拆出來顯示。舊版 App 看到的就是多一行文字，不會壞掉。

extension ChatMessage {
    static let replyOpen = "⟦回覆 "
    static let replyClose = "⟧\n"

    /// 引用行：暱稱 + 摘要
    var replyQuote: (nick: String, quote: String)? {
        guard text.hasPrefix(Self.replyOpen),
              let end = text.range(of: Self.replyClose) else { return nil }
        let start = text.index(text.startIndex, offsetBy: Self.replyOpen.count)
        let head = String(text[start..<end.lowerBound])
        guard let sep = head.range(of: "：") else { return nil }
        return (String(head[..<sep.lowerBound]), String(head[sep.upperBound...]))
    }

    /// 真正的內容（把引用行去掉）
    var bodyText: String {
        guard text.hasPrefix(Self.replyOpen),
              let end = text.range(of: Self.replyClose) else { return text }
        return String(text[end.upperBound...])
    }

    static func composeText(body: String, replyTo: (nick: String, quote: String)?) -> String {
        // 後端 text 上限 1000 字，引用行佔的空間要從正文扣掉
        let limit = 1000
        guard let r = replyTo else { return String(body.prefix(limit)) }
        let nick = String(r.nick.prefix(12))
        let flat = r.quote.replacingOccurrences(of: "\n", with: " ")
        let quote = String(flat.prefix(40))
        let head = "⟦回覆 \(nick)：\(quote)⟧\n"
        let room = max(0, limit - head.count)
        return head + String(body.prefix(room))
    }
}

struct PendingGrant: Identifiable, Equatable {
    let id: String
    let kind: String      // "title" / "level"
    let value: String     // 稱號 key 或等級數字
}

/// 別人的公開資料
struct PublicUser: Identifiable, Equatable {
    let id: String
    let userID: String
    let nickname: String
    let avatar: String?
    let level: MemberLevel
    let titles: [String]
    /// 對方自己排的稱號順序（存在雲端，換機也不會跑掉）
    var titleOrder: [String] = []
    /// 對方選擇不放上主頁的稱號
    var titleHidden: [String] = []
}

/// 非隔離的常數，避免跨 actor 取值
enum PVConfig {
    static let apiBase = "https://photovault-api.web.zaka.live"
}

enum SocialAPI {

    static var base: String { PVConfig.apiBase }

    // MARK: - 基礎請求

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 90
        c.waitsForConnectivity = true
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    @discardableResult
    static func request(_ method: String,
                        _ path: String,
                        json: [String: Any]? = nil,
                        token: String?) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw PVError.msg("網址錯誤") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token, !token.isEmpty { req.setValue(token, forHTTPHeaderField: "Authorization") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if !(200..<300).contains(code) {
            let msg = (obj["message"] as? String) ?? "請求失敗（\(code)）"
            throw PVError.msg(msg)
        }
        return obj
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private static func items(_ obj: [String: Any]) -> [[String: Any]] {
        (obj["items"] as? [[String: Any]]) ?? []
    }

    private static func date(_ any: Any?) -> Date {
        guard let s = any as? String else { return Date(timeIntervalSince1970: 0) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? Date(timeIntervalSince1970: 0)
    }

    static func fileURL(collection: String, record: String, file: String) -> URL? {
        URL(string: "\(base)/api/files/\(collection)/\(record)/\(file)")
    }

    // MARK: - 會員等級

    static func loadLevel(userID: String, token: String?) async -> MemberLevel {
        let f = enc("user=\"\(userID)\"")
        guard let obj = try? await request("GET",
            "/api/collections/memberships/records?perPage=50&filter=\(f)", token: token) else {
            return .silver
        }
        return bestLevel(items(obj))
    }

    /// 同一人多條會員記錄時，一律以最高等級為準
    private static func bestLevel(_ list: [[String: Any]]) -> MemberLevel {
        var best = -1
        for it in list {
            let n = (it["level"] as? Int) ?? Int((it["level"] as? Double) ?? 1)
            if n > best { best = n }
        }
        guard best > 0 else { return .silver }
        return MemberLevel(rawValue: best) ?? .silver
    }

    /// 保底：沒有會員記錄就依現在的下載階段給白銀
    /// 順手把重複的會員記錄統一成最高等級，避免不同頁面讀到不同那條
    static func ensureMembership(userID: String, token: String?) async -> MemberLevel {
        let f = enc("user=\"\(userID)\"")
        if let obj = try? await request("GET",
            "/api/collections/memberships/records?perPage=50&filter=\(f)", token: token),
           !items(obj).isEmpty {
            let list = items(obj)
            let lv = bestLevel(list)
            for it in list {
                guard let id = it["id"] as? String else { continue }
                let n = (it["level"] as? Int) ?? Int((it["level"] as? Double) ?? 1)
                if n != lv.rawValue {
                    _ = try? await request("PATCH",
                        "/api/collections/memberships/records/\(id)",
                        json: ["level": lv.rawValue], token: token)
                }
            }
            return lv
        }
        // 建立：目前下載一律白銀
        let fallback = LaunchPhase.defaultLevel
        _ = try? await request("POST", "/api/collections/memberships/records",
                               json: ["user": userID, "level": fallback.rawValue], token: token)
        return fallback
    }

    // MARK: - 稱號

    static func loadTitles(userID: String, token: String?) async -> [String] {
        let f = enc("user=\"\(userID)\"")
        guard let obj = try? await request("GET",
            "/api/collections/titles/records?perPage=50&filter=\(f)&sort=created", token: token) else { return [] }
        // 以 __ 開頭的是系統用的保留 key（例如編排資料），不是真的稱號
        return items(obj).compactMap { $0["title_key"] as? String }
            .filter { !$0.hasPrefix("__") }
    }

    static func grantTitle(userID: String, key: String, source: String, token: String?) async {
        let existing = await loadTitles(userID: userID, token: token)
        guard !existing.contains(key) else { return }
        _ = try? await request("POST", "/api/collections/titles/records",
                               json: ["user": userID, "title_key": key, "source": source],
                               token: token)
    }

    // MARK: - 待領取的贈與

    static func loadGrants(userID: String, token: String?) async -> [PendingGrant] {
        let f = enc("user=\"\(userID)\" && seen=false")
        guard let obj = try? await request("GET",
            "/api/collections/grants/records?perPage=20&filter=\(f)&sort=created", token: token) else { return [] }
        return items(obj).compactMap {
            guard let id = $0["id"] as? String,
                  let kind = $0["kind"] as? String,
                  let value = $0["value"] as? String else { return nil }
            return PendingGrant(id: id, kind: kind, value: value)
        }
    }

    static func markGrantSeen(id: String, token: String?) async {
        _ = try? await request("PATCH", "/api/collections/grants/records/\(id)",
                               json: ["seen": true], token: token)
    }

    // MARK: - 兌換碼

    /// 回傳兌換到的獎勵
    static func redeem(code raw: String, userID: String, token: String?) async throws -> PendingGrant {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw PVError.msg("請先輸入兌換碼") }
        let f = enc("code=\"\(code)\"")
        let obj = try await request("GET",
            "/api/collections/redeem/records?perPage=1&filter=\(f)", token: token)
        guard let it = items(obj).first,
              let id = it["id"] as? String,
              let kind = it["kind"] as? String,
              let value = it["value"] as? String else {
            throw PVError.msg("找不到這組兌換碼")
        }
        if let usedBy = it["used_by"] as? String, !usedBy.isEmpty {
            throw PVError.msg("這組兌換碼已經被使用過了")
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        _ = try await request("PATCH", "/api/collections/redeem/records/\(id)",
                              json: ["used_by": userID, "used_at": stamp], token: token)

        // 立刻生效
        if kind == "title" {
            await grantTitle(userID: userID, key: value, source: "redeem", token: token)
        } else if kind == "level", let n = Int(value), let lv = MemberLevel(rawValue: n) {
            await setLevel(userID: userID, level: lv, token: token)
        }
        return PendingGrant(id: id, kind: kind, value: value)
    }

    static func setLevel(userID: String, level: MemberLevel, token: String?) async {
        let f = enc("user=\"\(userID)\"")
        if let obj = try? await request("GET",
            "/api/collections/memberships/records?perPage=50&filter=\(f)", token: token),
           !items(obj).isEmpty {
            // 可能有多條，全部寫成同一個等級，之後不管讀哪條都一致
            for it in items(obj) {
                guard let id = it["id"] as? String else { continue }
                _ = try? await request("PATCH", "/api/collections/memberships/records/\(id)",
                                       json: ["level": level.rawValue], token: token)
            }
        } else {
            _ = try? await request("POST", "/api/collections/memberships/records",
                                   json: ["user": userID, "level": level.rawValue], token: token)
        }
    }

    // MARK: - 動態

    static func loadFeed(token: String?, limit: Int = 30) async -> [FeedPost] {
        guard let obj = try? await request("GET",
            "/api/collections/posts/records?perPage=\(limit)&sort=-created",
            token: token) else { return [] }
        let raw = items(obj).filter { !TitleLayoutSync.isLayoutPost($0) }
        let dec = await decorate(raw, token: token)
        return dec.map { d in
            FeedPost(id: d.id, userID: d.userID, profileID: d.profileID, nickname: d.nickname, avatar: d.avatar,
                     level: d.level, titles: d.titles,
                     text: (d.raw["text"] as? String) ?? "",
                     images: fileList(d.raw, field: "images"),
                     video: (fileList(d.raw, field: "video")).first,
                     created: d.created)
        }
    }

    static func postFeed(userID: String, text: String, images: [UIImage], video: URL?,
                         token: String?) async throws {
        guard let url = URL(string: base + "/api/collections/posts/records") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let token { req.setValue(token, forHTTPHeaderField: "Authorization") }
        let boundary = "----pv\(Int(Date().timeIntervalSince1970))"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        field("user", userID)
        field("text", text)

        for (i, img) in images.prefix(9).enumerated() {
            guard let data = img.jpegData(compressionQuality: 0.82) else { continue }
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"images\"; filename=\"p\(i).jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }

        if let video, let vd = try? Data(contentsOf: video) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"video\"; filename=\"v.mp4\"\r\n".utf8))
            body.append(Data("Content-Type: video/mp4\r\n\r\n".utf8))
            body.append(vd)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw PVError.msg((obj["message"] as? String) ?? "發佈失敗（\(code)）")
        }
    }

    static func deletePost(id: String, token: String?) async {
        _ = try? await request("DELETE", "/api/collections/posts/records/\(id)", token: token)
    }

    // MARK: - 聊天室

    static func loadChat(token: String?, limit: Int = 60) async -> [ChatMessage] {
        guard let obj = try? await request("GET",
            "/api/collections/chat/records?perPage=\(limit)&sort=created",
            token: token) else { return [] }
        return await mapChat(items(obj), token: token)
    }

    /// 最近 N 條（新的在後面）
    static func loadChatRecent(token: String?, limit: Int = 300) async -> [ChatMessage] {
        guard let obj = try? await request("GET",
            "/api/collections/chat/records?perPage=\(min(limit, 500))&sort=-created",
            token: token) else { return [] }
        // 伺服器是「新到舊」，反轉就是舊到新。
        // 不用 sorted：同一秒內的多條訊息會被非穩定排序洗牌，看起來就像整段倒過來。
        return await mapChat(items(obj), token: token).reversed()
    }

    /// 只拉比這個時間新的訊息（輪詢用，不會每次把整串重抓）
    static func loadChatSince(_ since: Date, token: String?, limit: Int = 200) async -> [ChatMessage] {
        let f = enc("created > \"\(pbDate(since))\"")
        guard let obj = try? await request("GET",
            "/api/collections/chat/records?perPage=\(limit)&sort=created&filter=\(f)",
            token: token) else { return [] }
        return await mapChat(items(obj), token: token)
    }

    /// 未讀數：比 lastRead 新、又不是自己發的訊息
    static func chatUnreadCount(since: Date, excludeUser: String?, token: String?) async -> Int {
        var parts = ["created > \"\(pbDate(since))\""]
        if let excludeUser, !excludeUser.isEmpty { parts.append("user != \"\(excludeUser)\"") }
        let f = enc(parts.joined(separator: " && "))
        guard let obj = try? await request("GET",
            "/api/collections/chat/records?perPage=1&filter=\(f)", token: token) else { return 0 }
        return (obj["totalItems"] as? Int) ?? 0
    }

    /// 離線時用：抓最新一條訊息（只取 id/created，很輕）
    static func chatLatestDate(token: String?) async -> Date? {
        guard let obj = try? await request("GET",
            "/api/collections/chat/records?perPage=1&sort=-created&fields=id,created",
            token: token) else { return nil }
        return items(obj).first.map { date($0["created"]) }
    }

    private static func mapChat(_ raw: [[String: Any]], token: String?) async -> [ChatMessage] {
        let dec = await decorate(raw, token: token)
        return dec.map { d in
            ChatMessage(id: d.id, userID: d.userID, profileID: d.profileID, nickname: d.nickname, avatar: d.avatar,
                        level: d.level, titles: d.titles,
                        text: (d.raw["text"] as? String) ?? "",
                        image: fileList(d.raw, field: "image").first,
                        created: d.created)
        }
    }

    /// PocketBase 的日期格式
    private static let pbFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS'Z'"
        return f
    }()

    static func pbDate(_ d: Date) -> String { pbFormatter.string(from: d) }

    static func sendChat(userID: String, text: String, image: UIImage?,
                         replyTo: (nick: String, quote: String)? = nil,
                         token: String?) async throws {
        guard let url = URL(string: base + "/api/collections/chat/records") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let token { req.setValue(token, forHTTPHeaderField: "Authorization") }
        let boundary = "----pv\(Int(Date().timeIntervalSince1970))"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("user", userID)
        field("text", ChatMessage.composeText(body: text, replyTo: replyTo))

        if let image, let data = image.jpegData(compressionQuality: 0.8) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"c.jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw PVError.msg((obj["message"] as? String) ?? "發送失敗（\(code)）")
        }
    }

    // MARK: - 公開資料

    /// 把貼文 / 訊息補上作者的名字、頭像、會員等級與稱號
    private struct Decorated {
        let id: String
        let userID: String
        let profileID: String
        let nickname: String
        let avatar: String?
        let level: MemberLevel
        let titles: [String]
        let raw: [String: Any]
        let created: Date
    }

    private static func decorate(_ raw: [[String: Any]], token: String?) async -> [Decorated] {
        let uids = Array(Set(raw.compactMap { $0["user"] as? String }))
        guard !uids.isEmpty else { return [] }

        var profiles: [String: [String: Any]] = [:]
        let filter = uids.map { "user=\"\($0)\"" }.joined(separator: " || ")
        if let obj = try? await request("GET",
            "/api/collections/profiles/records?perPage=100&filter=\(enc(filter))", token: token) {
            for it in items(obj) {
                if let uid = it["user"] as? String { profiles[uid] = it }
            }
        }

        var levels: [String: MemberLevel] = [:]
        var levelGroup: [String: [[String: Any]]] = [:]
        if let obj = try? await request("GET",
            "/api/collections/memberships/records?perPage=200&filter=\(enc(filter))", token: token) {
            for it in items(obj) {
                if let uid = it["user"] as? String {
                    levelGroup[uid, default: []].append(it)
                }
            }
            // 同一人多條記錄時取最高，不然會出現主頁黑金、聊天室卻顯示舊等級
            for (uid, list) in levelGroup {
                levels[uid] = bestLevel(list)
            }
        }

        var titleMap: [String: [String]] = [:]
        if let obj = try? await request("GET",
            "/api/collections/titles/records?perPage=100&filter=\(enc(filter))", token: token) {
            for it in items(obj) {
                guard let uid = it["user"] as? String,
                      let k = it["title_key"] as? String else { continue }
                titleMap[uid, default: []].append(k)
            }
        }

        return raw.compactMap { it in
            guard let id = it["id"] as? String,
                  let uid = it["user"] as? String else { return nil }
            let p = profiles[uid]
            return Decorated(id: id, userID: uid,
                             profileID: (p?["id"] as? String) ?? "",
                             nickname: (p?["nickname"] as? String) ?? "用戶",
                             avatar: p?["avatar"] as? String,
                             level: levels[uid] ?? .silver,
                             titles: Titles.resolved(titleMap[uid] ?? [],
                                                     level: levels[uid] ?? .silver),
                             raw: it,
                             created: date(it["created"]))
        }
    }

    // MARK: - 稱號編排的雲端同步
    //
    // 順序與「哪些不放主頁」如果只存在本機，別人（以及自己換手機後）
    // 看到的就是伺服器回傳的原始順序，不是自己排的那個。
    // 後端沒有專門欄位可用，這裡借一篇動態記錄來存：
    // text 以固定標記開頭，App 讀動態時會把這種記錄整條濾掉，不會出現在牆上。

    enum TitleLayoutSync {
        static let marker = "PVLAYOUT1|"
        /// 只用來搜尋（不含特殊字元，避免 filter 語法出問題）
        static let searchKey = "PVLAYOUT1"

        struct Payload {
            var id: String = ""
            var order: [String] = []
            var hidden: [String] = []
        }

        static func isLayoutPost(_ it: [String: Any]) -> Bool {
            ((it["text"] as? String) ?? "").hasPrefix(marker)
        }

        static func encode(order: [String], hidden: [String]) -> String {
            let body: [String: Any] = ["o": order, "h": hidden]
            guard let d = try? JSONSerialization.data(withJSONObject: body),
                  let s = String(data: d, encoding: .utf8) else { return marker + "{}" }
            return marker + s
        }

        static func decode(_ text: String) -> ([String], [String])? {
            guard text.hasPrefix(marker) else { return nil }
            let json = String(text.dropFirst(marker.count))
            guard let d = json.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
            let o = (obj["o"] as? [String]) ?? []
            let h = (obj["h"] as? [String]) ?? []
            return (o, h)
        }
    }

    static func loadTitleLayout(userID: String, token: String?) async -> TitleLayoutSync.Payload? {
        let f = enc("user=\"\(userID)\" && text ~ \"\(TitleLayoutSync.searchKey)\"")
        guard let obj = try? await request("GET",
            "/api/collections/posts/records?perPage=10&sort=-created&filter=\(f)",
            token: token) else { return nil }
        for it in items(obj) {
            guard let text = it["text"] as? String,
                  let id = it["id"] as? String,
                  let (o, h) = TitleLayoutSync.decode(text) else { continue }
            return TitleLayoutSync.Payload(id: id, order: o, hidden: h)
        }
        return nil
    }

    @discardableResult
    static func saveTitleLayout(userID: String, recordID: String?,
                                order: [String], hidden: [String],
                                token: String?) async -> String? {
        let text = TitleLayoutSync.encode(order: order, hidden: hidden)
        if let recordID, !recordID.isEmpty {
            if let obj = try? await request("PATCH", "/api/collections/posts/records/\(recordID)",
                                            json: ["text": text], token: token),
               let id = obj["id"] as? String { return id }
        }
        if let obj = try? await request("POST", "/api/collections/posts/records",
                                        json: ["user": userID, "text": text], token: token),
           let id = obj["id"] as? String { return id }
        return nil
    }

    static func loadPublicUser(profileID: String, token: String?) async -> PublicUser? {
        guard let obj = try? await request("GET",
            "/api/collections/profiles/records/\(profileID)", token: token),
              let uid = obj["user"] as? String else { return nil }
        let level = await loadLevel(userID: uid, token: token)
        let titles = await loadTitles(userID: uid, token: token)
        let layout = await loadTitleLayout(userID: uid, token: token)
        return PublicUser(id: profileID, userID: uid,
                          nickname: (obj["nickname"] as? String) ?? "用戶",
                          avatar: obj["avatar"] as? String,
                          level: level, titles: Titles.resolved(titles, level: level),
                          titleOrder: layout?.order ?? [],
                          titleHidden: layout?.hidden ?? [])
    }

    static func loadUserPosts(userID: String, token: String?, limit: Int = 30) async -> [FeedPost] {
        let f = enc("user=\"\(userID)\"")
        guard let obj = try? await request("GET",
            "/api/collections/posts/records?perPage=\(limit)&sort=-created&filter=\(f)",
            token: token) else { return [] }
        let raw = items(obj).filter { !TitleLayoutSync.isLayoutPost($0) }
        let dec = await decorate(raw, token: token)
        return dec.map { d in
            FeedPost(id: d.id, userID: d.userID, profileID: d.profileID, nickname: d.nickname, avatar: d.avatar,
                     level: d.level, titles: d.titles,
                     text: (d.raw["text"] as? String) ?? "",
                     images: fileList(d.raw, field: "images"),
                     video: fileList(d.raw, field: "video").first,
                     created: d.created)
        }
    }

    // MARK: - 任務

    static func taskValue(userID: String, key: String, token: String?) async -> (value: Double, claimed: Bool) {
        let f = enc("user=\"\(userID)\" && key=\"\(key)\"")
        guard let obj = try? await request("GET",
            "/api/collections/tasks/records?perPage=1&filter=\(f)", token: token),
              let it = items(obj).first else { return (0, false) }
        let v = (it["value"] as? Double) ?? Double((it["value"] as? Int) ?? 0)
        return (v, (it["claimed"] as? Bool) ?? false)
    }

    /// 累加任務進度（例如里程、次數），只增不減
    static func bumpTask(userID: String, key: String, add: Double, token: String?) async {
        let f = enc("user=\"\(userID)\" && key=\"\(key)\"")
        if let obj = try? await request("GET",
            "/api/collections/tasks/records?perPage=1&filter=\(f)", token: token),
           let it = items(obj).first, let id = it["id"] as? String {
            let cur = (it["value"] as? Double) ?? Double((it["value"] as? Int) ?? 0)
            _ = try? await request("PATCH", "/api/collections/tasks/records/\(id)",
                                   json: ["value": cur + add], token: token)
        } else {
            _ = try? await request("POST", "/api/collections/tasks/records",
                                   json: ["user": userID, "key": key, "value": add, "claimed": false],
                                   token: token)
        }
    }

    static func setTaskPeak(userID: String, key: String, value: Double, token: String?) async {
        let f = enc("user=\"\(userID)\" && key=\"\(key)\"")
        if let obj = try? await request("GET",
            "/api/collections/tasks/records?perPage=1&filter=\(f)", token: token),
           let it = items(obj).first, let id = it["id"] as? String {
            let cur = (it["value"] as? Double) ?? Double((it["value"] as? Int) ?? 0)
            guard value > cur else { return }
            _ = try? await request("PATCH", "/api/collections/tasks/records/\(id)",
                                   json: ["value": value], token: token)
        } else {
            _ = try? await request("POST", "/api/collections/tasks/records",
                                   json: ["user": userID, "key": key, "value": value, "claimed": false],
                                   token: token)
        }
    }

    static func markTaskClaimed(userID: String, key: String, token: String?) async {
        let f = enc("user=\"\(userID)\" && key=\"\(key)\"")
        guard let obj = try? await request("GET",
            "/api/collections/tasks/records?perPage=1&filter=\(f)", token: token),
              let it = items(obj).first, let id = it["id"] as? String else { return }
        _ = try? await request("PATCH", "/api/collections/tasks/records/\(id)",
                               json: ["claimed": true], token: token)
    }

    /// 一次拉全部任務進度（列表頁 / 紅點用）
    static func taskMap(userID: String, token: String?) async -> [String: (Double, Bool)] {
        let f = enc("user=\"\(userID)\"")
        guard let obj = try? await request("GET",
            "/api/collections/tasks/records?perPage=50&filter=\(f)", token: token) else { return [:] }
        var out: [String: (Double, Bool)] = [:]
        for it in items(obj) {
            guard let k = it["key"] as? String else { continue }
            let v = (it["value"] as? Double) ?? Double((it["value"] as? Int) ?? 0)
            out[k] = (v, (it["claimed"] as? Bool) ?? false)
        }
        return out
    }

    // MARK: - 小工具

    private static func fileList(_ raw: [String: Any], field: String) -> [String] {
        if let arr = raw[field] as? [String] { return arr }
        if let s = raw[field] as? String, !s.isEmpty { return [s] }
        return []
    }
}
