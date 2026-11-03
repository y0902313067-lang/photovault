import SwiftUI

// MARK: - 稱號定義

struct TitleDef: Identifiable, Hashable {
    let key: String
    let name: String
    let image: String
    let colors: [Color]
    let edge: Color
    let glow: Color
    let tier: Int          // 0 = 樸素, 1 = 一層金光, 2 = 雙層輝光, 3 = 最強輝光
    let how: String        // 取得方式

    var id: String { key }

    static func == (a: TitleDef, b: TitleDef) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

enum Titles {
    static let all: [TitleDef] = [
        TitleDef(key: "speed", name: "測速達人", image: "tt1",
                 colors: [Color(red: 0.12, green: 0.31, blue: 0.53),
                          Color(red: 0.25, green: 0.56, blue: 0.77),
                          Color(red: 0.40, green: 0.76, blue: 0.88)],
                 edge: Color(red: 0.62, green: 0.86, blue: 1.0),
                 glow: Color(red: 0.45, green: 0.78, blue: 1.0),
                 tier: 0,
                 how: "累積經過 10 個限速路段"),

        TitleDef(key: "diag", name: "診斷專家", image: "tt2",
                 colors: [Color(red: 0.05, green: 0.35, blue: 0.31),
                          Color(red: 0.09, green: 0.63, blue: 0.55),
                          Color(red: 0.25, green: 0.85, blue: 0.72)],
                 edge: Color(red: 0.55, green: 0.95, blue: 0.85),
                 glow: Color(red: 0.35, green: 0.90, blue: 0.78),
                 tier: 0,
                 how: "完成一次網路診斷"),

        TitleDef(key: "pw", name: "安全密碼", image: "tt3",
                 colors: [Color(red: 0.10, green: 0.36, blue: 0.23),
                          Color(red: 0.18, green: 0.61, blue: 0.37),
                          Color(red: 0.33, green: 0.79, blue: 0.50)],
                 edge: Color(red: 0.60, green: 0.96, blue: 0.74),
                 glow: Color(red: 0.38, green: 0.88, blue: 0.58),
                 tier: 0,
                 how: "輸入一組 81 分的密碼"),

        TitleDef(key: "walk", name: "健走達人", image: "tt4",
                 colors: [Color(red: 0.42, green: 0.23, blue: 0.07),
                          Color(red: 0.72, green: 0.45, blue: 0.20),
                          Color(red: 0.88, green: 0.63, blue: 0.35)],
                 edge: Color(red: 1.0, green: 0.84, blue: 0.62),
                 glow: Color(red: 1.0, green: 0.72, blue: 0.42),
                 tier: 0,
                 how: "累積步行 10 公里"),

        TitleDef(key: "db", name: "獅吼功", image: "tt5",
                 colors: [Color(red: 0.43, green: 0.12, blue: 0.16),
                          Color(red: 0.70, green: 0.23, blue: 0.28),
                          Color(red: 0.88, green: 0.38, blue: 0.44)],
                 edge: Color(red: 1.0, green: 0.66, blue: 0.70),
                 glow: Color(red: 1.0, green: 0.45, blue: 0.52),
                 tier: 0,
                 how: "使用分貝計測到 100 分貝以上"),

        TitleDef(key: "fx", name: "外交官", image: "tt6",
                 colors: [Color(red: 0.16, green: 0.21, blue: 0.38),
                          Color(red: 0.29, green: 0.37, blue: 0.66),
                          Color(red: 0.49, green: 0.56, blue: 0.85)],
                 edge: Color(red: 0.72, green: 0.79, blue: 1.0),
                 glow: Color(red: 0.60, green: 0.68, blue: 1.0),
                 tier: 0,
                 how: "查看即時匯率 3 次"),

        TitleDef(key: "dad", name: "金主爸爸", image: "tt7",
                 colors: [Color(red: 0.55, green: 0.38, blue: 0.08),
                          Color(red: 0.86, green: 0.66, blue: 0.22),
                          Color(red: 0.98, green: 0.84, blue: 0.44)],
                 edge: Color(red: 1.0, green: 0.88, blue: 0.56),
                 glow: Color(red: 1.0, green: 0.78, blue: 0.32),
                 tier: 1,
                 how: "由官方贈與，或輸入兌換碼"),

        TitleDef(key: "grand", name: "金主爺爺", image: "tt8",
                 colors: [Color(red: 0.62, green: 0.42, blue: 0.05),
                          Color(red: 0.95, green: 0.72, blue: 0.20),
                          Color(red: 1.0, green: 0.92, blue: 0.62)],
                 edge: Color(red: 1.0, green: 0.93, blue: 0.70),
                 glow: Color(red: 1.0, green: 0.82, blue: 0.36),
                 tier: 2,
                 how: "由官方贈與，或輸入兌換碼"),

        TitleDef(key: "rich", name: "超級富豪", image: "tt9",
                 colors: [Color(red: 0.30, green: 0.16, blue: 0.52),
                          Color(red: 0.62, green: 0.42, blue: 0.80),
                          Color(red: 1.0, green: 0.95, blue: 0.78),
                          Color(red: 0.86, green: 0.66, blue: 0.24)],
                 edge: Color(red: 1.0, green: 0.96, blue: 0.82),
                 glow: Color(red: 0.86, green: 0.72, blue: 1.0),
                 tier: 3,
                 how: "由官方贈與，或輸入兌換碼"),

        // 三階王爵：黑金一星／二星 → 金，三星／四星再疊血鑽，五星三個全拿
        TitleDef(key: "duke1", name: "黑金王爵", image: "tt11",
                 colors: [Color(red: 0.09, green: 0.07, blue: 0.06),
                          Color(red: 0.24, green: 0.18, blue: 0.07),
                          Color(red: 0.55, green: 0.40, blue: 0.12),
                          Color(red: 0.93, green: 0.74, blue: 0.32)],
                 edge: Color(red: 1.0, green: 0.90, blue: 0.60),
                 glow: Color(red: 1.0, green: 0.78, blue: 0.30),
                 tier: 4,
                 how: "黑金一星／二星自動獲得"),

        TitleDef(key: "duke2", name: "血鑽王爵", image: "tt12",
                 colors: [Color(red: 0.08, green: 0.03, blue: 0.04),
                          Color(red: 0.30, green: 0.04, blue: 0.08),
                          Color(red: 0.55, green: 0.09, blue: 0.14),
                          Color(red: 0.82, green: 0.22, blue: 0.26)],
                 edge: Color(red: 1.0, green: 0.72, blue: 0.62),
                 glow: Color(red: 1.0, green: 0.25, blue: 0.32),
                 tier: 5,
                 how: "黑金三星／四星自動獲得"),

        TitleDef(key: "duke3", name: "深淵王爵", image: "tt13",
                 colors: [Color(red: 0.04, green: 0.03, blue: 0.09),
                          Color(red: 0.14, green: 0.08, blue: 0.28),
                          Color(red: 0.33, green: 0.18, blue: 0.60),
                          Color(red: 0.62, green: 0.42, blue: 0.94)],
                 edge: Color(red: 0.86, green: 0.76, blue: 1.0),
                 glow: Color(red: 0.62, green: 0.42, blue: 1.0),
                 tier: 6,
                 how: "黑金五星自動獲得（最高階）"),

        // 工具成就稱號：做一次對應的事就拿到
        TitleDef(key: "netdoc", name: "資訊老師", image: "tt14",
                 colors: [Color(red: 0.05, green: 0.14, blue: 0.36),
                          Color(red: 0.10, green: 0.34, blue: 0.72),
                          Color(red: 0.28, green: 0.72, blue: 0.95)],
                 edge: Color(red: 0.65, green: 0.92, blue: 1.0),
                 glow: Color(red: 0.35, green: 0.78, blue: 1.0),
                 tier: 1,
                 how: "打開網域資訊工具一次"),

        TitleDef(key: "north", name: "漂向北方", image: "tt15",
                 colors: [Color(red: 0.03, green: 0.26, blue: 0.31),
                          Color(red: 0.06, green: 0.52, blue: 0.56),
                          Color(red: 0.34, green: 0.86, blue: 0.80)],
                 edge: Color(red: 0.62, green: 1.0, blue: 0.93),
                 glow: Color(red: 0.24, green: 0.90, blue: 0.80),
                 tier: 1,
                 how: "用指南針指著北方一次"),

        TitleDef(key: "gearhead", name: "裝備組的", image: "tt16",
                 colors: [Color(red: 0.12, green: 0.16, blue: 0.20),
                          Color(red: 0.30, green: 0.38, blue: 0.45),
                          Color(red: 0.68, green: 0.49, blue: 0.20)],
                 edge: Color(red: 1.0, green: 0.79, blue: 0.45),
                 glow: Color(red: 1.0, green: 0.62, blue: 0.20),
                 tier: 1,
                 how: "點開裝置資訊一次"),

        TitleDef(key: "shake67", name: "6767", image: "tt17",
                 colors: [Color(red: 0.22, green: 0.05, blue: 0.36),
                          Color(red: 0.52, green: 0.16, blue: 0.76),
                          Color(red: 0.88, green: 0.30, blue: 0.70)],
                 edge: Color(red: 1.0, green: 0.68, blue: 0.92),
                 glow: Color(red: 0.85, green: 0.35, blue: 1.0),
                 tier: 2,
                 how: "用重力感測晃動 67 次"),

        TitleDef(key: "mathprof", name: "數學老師", image: "tt18",
                 colors: [Color(red: 0.03, green: 0.15, blue: 0.12),
                          Color(red: 0.06, green: 0.32, blue: 0.25),
                          Color(red: 0.16, green: 0.60, blue: 0.43)],
                 edge: Color(red: 0.62, green: 0.96, blue: 0.78),
                 glow: Color(red: 0.30, green: 0.85, blue: 0.60),
                 tier: 1,
                 how: "點開單位換算一次"),

        TitleDef(key: "qrartist", name: "QR藝術家", image: "tt19",
                 colors: [Color(red: 0.09, green: 0.09, blue: 0.27),
                          Color(red: 0.34, green: 0.20, blue: 0.62),
                          Color(red: 0.17, green: 0.60, blue: 0.72)],
                 edge: Color(red: 0.85, green: 0.85, blue: 1.0),
                 glow: Color(red: 0.55, green: 0.55, blue: 1.0),
                 tier: 2,
                 how: "用 QR 工作室做出一個二維碼"),

        TitleDef(key: "diceluck", name: "愛拼才會贏", image: "tt20",
                 colors: [Color(red: 0.28, green: 0.04, blue: 0.09),
                          Color(red: 0.60, green: 0.11, blue: 0.19),
                          Color(red: 0.84, green: 0.36, blue: 0.29)],
                 edge: Color(red: 1.0, green: 0.78, blue: 0.55),
                 glow: Color(red: 1.0, green: 0.42, blue: 0.30),
                 tier: 1,
                 how: "用隨機決策的骰子擲一次"),

        TitleDef(key: "tophat", name: "高利戴帽子", image: "tt21",
                 colors: [Color(red: 0.09, green: 0.06, blue: 0.04),
                          Color(red: 0.27, green: 0.19, blue: 0.09),
                          Color(red: 0.54, green: 0.39, blue: 0.14)],
                 edge: Color(red: 0.96, green: 0.83, blue: 0.52),
                 glow: Color(red: 0.90, green: 0.70, blue: 0.28),
                 tier: 1,
                 how: "用貸款試算算一次"),

        TitleDef(key: "nicejob", name: "好棒棒餒", image: "tt22",
                 colors: [Color(red: 0.32, green: 0.09, blue: 0.17),
                          Color(red: 0.70, green: 0.25, blue: 0.33),
                          Color(red: 0.90, green: 0.48, blue: 0.40)],
                 edge: Color(red: 1.0, green: 0.82, blue: 0.62),
                 glow: Color(red: 1.0, green: 0.55, blue: 0.45),
                 tier: 1,
                 how: "發一篇動態"),

        TitleDef(key: "socialking", name: "超級社牛", image: "tt23",
                 colors: [Color(red: 0.34, green: 0.07, blue: 0.09),
                          Color(red: 0.70, green: 0.19, blue: 0.19),
                          Color(red: 0.84, green: 0.33, blue: 0.43)],
                 edge: Color(red: 1.0, green: 0.70, blue: 0.66),
                 glow: Color(red: 1.0, green: 0.35, blue: 0.32),
                 tier: 2,
                 how: "在聊天室發一次言"),

        TitleDef(key: "admin", name: "官方管理員", image: "tt10",
                 colors: [Color(red: 0.10, green: 0.24, blue: 0.48),
                          Color(red: 0.24, green: 0.46, blue: 0.82),
                          Color(red: 0.72, green: 0.85, blue: 1.0)],
                 edge: Color(red: 0.80, green: 0.90, blue: 1.0),
                 glow: Color(red: 0.55, green: 0.75, blue: 1.0),
                 tier: 1,
                 how: "僅由官方後台授予")
    ]

    static let order: [String: Int] = {
        var m: [String: Int] = [:]
        for (i, t) in all.enumerated() { m[t.key] = i }
        return m
    }()

    static func find(_ key: String) -> TitleDef? { all.first { $0.key == key } }

    /// 後台 / 兌換碼可以發的（7 / 8 / 9 ＋ 三階王爵）＋ 管理員
    static var grantable: [TitleDef] {
        all.filter { ["dad", "grand", "rich", "duke1", "duke2", "duke3", "admin"].contains($0.key) }
    }

    /// 會員等級自動帶的王爵稱號（只往上疊，升星不收回）
    static func dukeTitles(for level: MemberLevel) -> [String] {
        switch level {
        case .black1, .black2:  return ["duke1"]
        case .black3, .black4:  return ["duke1", "duke2"]
        case .black5:           return ["duke1", "duke2", "duke3"]
        default:                return []
        }
    }

    /// 把後台／兌換碼發的稱號，與等級自動獲得的王爵合併（去重）
    static func resolved(_ owned: [String], level: MemberLevel) -> [String] {
        var list = owned
        for k in dukeTitles(for: level) where !list.contains(k) { list.append(k) }
        return list
    }
}
