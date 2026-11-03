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

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("pv_chat_cache.json")
        read()
    }

    // MARK: 讀寫

    private func read() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let list = try? dec.decode([ChatMessage].self, from: data) else { return }
        // 先依時間排好，之後 append 才能直接往後接
        let sorted = list.sorted { $0.created < $1.created }
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
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(snapshot) else { return }
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
        added.sort { $0.created < $1.created }

        // 絕大多數情況新資料都比現有最新的一條還新，直接往後接就好
        if let last = items.last, added.first!.created < last.created {
            items.append(contentsOf: added)
            items.sort { $0.created < $1.created }
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
        added.sort { $0.created < $1.created }

        var needsSort = false
        if let last = items.last, added.first!.created < last.created { needsSort = true }
        items.append(contentsOf: added)
        if needsSort { items.sort { $0.created < $1.created } }
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
