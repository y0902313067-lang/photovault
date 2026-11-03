import Foundation

/// 聊天紀錄的本機快取
/// - 在線：把伺服器訊息併進來，本機最多留最近 5000 則
/// - 離線：只顯示最近 300 則（更早的看不到）
final class ChatCache {
    static let shared = ChatCache()

    /// 本機硬碟最多保留的則數
    static let diskLimit = 5000
    /// 離線時能看到的最多則數
    static let offlineLimit = 300

    private let url: URL
    private var items: [ChatMessage] = []

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
        if let list = try? dec.decode([ChatMessage].self, from: data) {
            items = list
        }
    }

    private func write() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 對外

    /// 併入伺服器拿到的訊息，回傳合併後的本機紀錄（最多 5000）
    @discardableResult
    func merge(_ incoming: [ChatMessage]) -> [ChatMessage] {
        guard !incoming.isEmpty else { return items }
        var map: [String: ChatMessage] = [:]
        for m in items { map[m.id] = m }
        for m in incoming { map[m.id] = m }
        var list = Array(map.values).sorted { $0.created < $1.created }
        if list.count > Self.diskLimit {
            list = Array(list.suffix(Self.diskLimit))
        }
        items = list
        write()
        return items
    }

    /// 離線時顯示：最近 300 則
    var offlineTail: [ChatMessage] { Array(items.suffix(Self.offlineLimit)) }

    /// 本機全部（最多 5000）
    var all: [ChatMessage] { items }

    func clear() {
        items = []
        write()
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
