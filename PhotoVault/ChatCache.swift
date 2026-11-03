import Foundation

/// 聊天紀錄的本機快取
/// - 在線：把伺服器訊息併進來，本機最多留最近 5000 則
/// - 離線：只顯示最近 300 則（更早的看不到）
///
/// 效能重點（v37）：
/// 1. 輪詢時只「併入新的幾條」，不再整個陣列重建＋重新排序（原本 5000 則每 6 秒跑一次）
/// 2. 寫硬碟改成延遲合併寫，而且一定在背景序列佇列上做，不卡畫面
/// 3. 用 id 集合做去重，取代每次建整張字典
final class ChatCache {
    static let shared = ChatCache()

    /// 本機硬碟最多保留的則數
    static let diskLimit = 5000
    /// 離線時能看到的最多則數
    static let offlineLimit = 300

    private let url: URL
    private let io = DispatchQueue(label: "pv.chat.cache.io", qos: .utility)
    private let lock = NSLock()

    private var items: [ChatMessage] = []
    private var ids: Set<String> = []
    private var writeScheduled = false

    /// 快取格式版本：舊版的存檔把時間截到秒，同秒訊息順序已經亂了，
    /// 升上來先丟掉重抓一次，之後就都是正確順序
    private static let formatVersion = 2
    private static let versionKey = "pv.chat.cache.version"

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("pv_chat_cache.json")

        let saved = UserDefaults.standard.integer(forKey: Self.versionKey)
        if saved < Self.formatVersion {
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.set(Self.formatVersion, forKey: Self.versionKey)
        }
        read()
    }

    // MARK: 時間精度
    //
    // 原本用 .iso8601 存檔，時間只到「秒」。同一秒內連續發的幾條訊息
    // 存回來後 created 全部一樣，重排時順序就散了（離線重開會看到整段倒過來）。
    // 這裡改成帶毫秒，解碼則新舊格式都吃。

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(isoFull.string(from: date))
        }
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let t = isoFull.date(from: s) { return t }
            if let t = isoPlain.date(from: s) { return t }
            return Date(timeIntervalSince1970: 0)
        }
        return d
    }

    /// 穩定排序：時間相同時保留原本的先後，不會把同秒的訊息洗牌
    private static func stableSorted(_ list: [ChatMessage]) -> [ChatMessage] {
        list.enumerated()
            .sorted { a, b in
                if a.element.created == b.element.created { return a.offset < b.offset }
                return a.element.created < b.element.created
            }
            .map { $0.element }
    }

    // MARK: 讀寫

    private func read() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let list = try? Self.makeDecoder().decode([ChatMessage].self, from: data) else { return }
        // 先依時間排好，之後 append 才能直接往後接（同秒的保持原順序）
        let sorted = Self.stableSorted(list)
        var seen = Set<String>()
        var unique: [ChatMessage] = []
        unique.reserveCapacity(sorted.count)
        for m in sorted where !seen.contains(m.id) {
            seen.insert(m.id)
            unique.append(m)
        }
        items = unique.count > Self.diskLimit ? Array(unique.suffix(Self.diskLimit)) : unique
        ids = Set(items.map { $0.id })
    }

    /// 寫入排程：短時間內多次變動只寫一次，且在背景做
    private func scheduleWrite() {
        lock.lock()
        if writeScheduled {
            lock.unlock()
            return
        }
        writeScheduled = true
        lock.unlock()

        io.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.writeScheduled = false
            let snapshot = self.items
            self.lock.unlock()
            self.write(snapshot)
        }
    }

    private func write(_ snapshot: [ChatMessage]) {
        guard let data = try? Self.makeEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: 對外

    /// 首次載入／手動刷新：併進整批並回傳合併後的完整清單（最多 5000）
    @discardableResult
    func merge(_ incoming: [ChatMessage]) -> [ChatMessage] {
        guard !incoming.isEmpty else { return snapshot() }

        lock.lock()
        var added: [ChatMessage] = []
        for m in incoming where !ids.contains(m.id) {
            ids.insert(m.id)
            added.append(m)
        }
        guard !added.isEmpty else {
            let same = items
            lock.unlock()
            return same
        }
        added = Self.stableSorted(added)

        // 絕大多數情況新資料都比現有最新的一條還新，直接往後接就好
        if let last = items.last, added.first!.created < last.created {
            items.append(contentsOf: added)
            items = Self.stableSorted(items)
        } else {
            items.append(contentsOf: added)
        }
        trimLocked()
        let merged = items
        lock.unlock()

        scheduleWrite()
        return merged
    }

    /// 輪詢：只併入沒見過的，回傳「新增的那幾條」（呼叫端直接 append 到畫面陣列即可）
    @discardableResult
    func appendNew(_ incoming: [ChatMessage]) -> [ChatMessage] {
        guard !incoming.isEmpty else { return [] }

        lock.lock()
        var added: [ChatMessage] = []
        for m in incoming where !ids.contains(m.id) {
            ids.insert(m.id)
            added.append(m)
        }
        guard !added.isEmpty else {
            lock.unlock()
            return []
        }
        added = Self.stableSorted(added)

        var needsSort = false
        if let last = items.last, added.first!.created < last.created { needsSort = true }
        items.append(contentsOf: added)
        if needsSort { items = Self.stableSorted(items) }
        var removed = false
        if items.count > Self.diskLimit {
            let drop = items.count - Self.diskLimit
            for m in items.prefix(drop) { ids.remove(m.id) }
            items.removeFirst(drop)
            removed = true
        }
        var kept = added
        if removed {
            let oldest = items.first?.created ?? .distantPast
            kept = added.filter { $0.created >= oldest }
        }
        lock.unlock()

        scheduleWrite()
        return kept
    }

    /// 只保留最近 N 則（回傳尾巴）
    func tail(_ limit: Int) -> [ChatMessage] {
        lock.lock()
        let list = Array(items.suffix(limit))
        lock.unlock()
        return list
    }

    /// 離線時顯示：最近 300 則
    var offlineTail: [ChatMessage] { tail(Self.offlineLimit) }

    /// 本機全部（最多 5000）
    var all: [ChatMessage] { snapshot() }

    var count: Int {
        lock.lock()
        let n = items.count
        lock.unlock()
        return n
    }

    func clear() {
        lock.lock()
        items = []
        ids = []
        lock.unlock()
        scheduleWrite()
    }

    private func snapshot() -> [ChatMessage] {
        lock.lock()
        let list = items
        lock.unlock()
        return list
    }

    /// 呼叫前必須已持有 lock
    private func trimLocked() {
        if items.count > Self.diskLimit {
            let drop = items.count - Self.diskLimit
            for m in items.prefix(drop) { ids.remove(m.id) }
            items.removeFirst(drop)
        }
    }
}

// MARK: - 聊天室已讀時間

enum ChatReadMark {
    private static let key = "pv.chat.lastRead.v1"

    static var lastRead: Date {
        let t = UserDefaults.standard.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : Date(timeIntervalSince1970: 0)
    }

    static func markRead(_ date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
    }
}
