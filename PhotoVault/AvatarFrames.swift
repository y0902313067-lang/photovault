import SwiftUI

// MARK: - 頭像框
//
// 頭框跟稱號共用同一張 titles 表，靠 key 前綴區分：
//   稱號 → "duke1"、"guard" …
//   頭框 → "frame.flame"
// 這樣不用改後端表結構，別人打開你的主頁／聊天室也看得到你戴的框，
// 而且不會被算成一個稱號（Titles.find 找不到 frame. 開頭的 key）。
//
// 取得方式：只有後台贈送（grants kind = "frame"）或兌換碼（redeem kind = "frame"），
// 不掛任何任務獎勵。

struct FrameDef: Identifiable, Hashable {
    let key: String        // 不含前綴，例如 "flame"
    let name: String
    let image: String
    let note: String       // 取得方式

    var id: String { key }
    var storeKey: String { Frames.prefix + key }
}

enum Frames {
    static let prefix = "frame."

    static let all: [FrameDef] = [
        FrameDef(key: "flame", name: "烈焰之環", image: "frameFlame",
                 note: "官方限量贈送，不掛任務")
    ]

    /// 頭像圓直徑佔整張框的比例
    /// 這款火焰環是從影片逐幀拆出來的，實測挖空圓直徑 = 框寬的 0.636，
    /// 照這個比例擺，頭像才會跟框嚴絲合縫，不會露出框裡的舊照片殘影。
    static let avatarRatio: CGFloat = 0.636

    /// 吃三種寫法："flame" / "frame.flame"
    static func find(_ raw: String) -> FrameDef? {
        guard !raw.isEmpty else { return nil }
        let k = raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
        return all.first { $0.key == k }
    }

    static func storeKey(_ raw: String) -> String {
        raw.hasPrefix(prefix) ? raw : prefix + raw
    }

    /// 已擁有的頭框
    static func owned(in titles: [String]) -> [FrameDef] {
        all.filter { titles.contains($0.storeKey) }
    }

    /// 目前戴著的頭框（目前只有一款，擁有就戴上）
    static func equipped(in titles: [String]) -> FrameDef? {
        for t in titles {
            if let d = find(t) { return d }
        }
        return owned(in: titles).first
    }
}

// MARK: - 疊在頭像外面的框

struct AvatarFrameLayer: View {
    let raw: String?
    let avatar: CGFloat

    private var def: FrameDef? { Frames.find(raw ?? "") }
    private var outer: CGFloat { avatar / Frames.avatarRatio }

    var body: some View {
        if let def {
            Image(def.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: outer, height: outer)
                .allowsHitTesting(false)
        }
    }
}
