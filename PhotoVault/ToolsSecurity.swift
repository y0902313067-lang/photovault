import SwiftUI
import Foundation
import AVFoundation
import Vision
import PhotosUI

// MARK: - 風險等級

enum RiskLevel {
    case good, warn, bad

    var color: Color {
        switch self {
        case .good: return TT.mint
        case .warn: return TT.amber
        case .bad:  return TT.rose
        }
    }

    var icon: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad:  return "xmark.octagon.fill"
        }
    }
}

struct URLFinding: Identifiable {
    let id = UUID()
    let level: RiskLevel
    let title: String
    let detail: String
}

struct URLAnalysis {
    var valid = false
    var host = ""
    var scheme = ""
    var score = 0
    var findings: [URLFinding] = []
    var verdict = "待檢測"
    var color: Color = TT.mint
    var parts: [(String, String)] = []
}

// MARK: - 連結分析引擎

enum LinkGuard {

    static let shorteners: Set<String> = [
        "bit.ly", "t.co", "tinyurl.com", "goo.gl", "ow.ly", "is.gd", "buff.ly",
        "cutt.ly", "rb.gy", "shorturl.at", "reurl.cc", "pse.is", "ppt.cc",
        "t.cn", "dwz.cn", "url.cn", "suo.im", "s.id", "rebrand.ly", "tiny.cc"
    ]

    static let riskyTLD: Set<String> = [
        "top", "xyz", "tk", "ml", "ga", "cf", "gq", "work", "click", "link",
        "buzz", "loan", "kim", "men", "date", "review", "country", "stream",
        "download", "racing", "win", "bid", "party", "science", "gdn", "icu"
    ]

    static let lureWords: [String] = [
        "login", "signin", "verify", "verification", "secure", "security",
        "account", "update", "confirm", "password", "wallet", "recovery",
        "unlock", "suspend", "billing", "invoice", "refund", "bonus", "gift",
        "free", "claim", "airdrop", "giveaway", "prize", "winner", "reward",
        "登入", "验证", "驗證", "中奖", "中獎", "免费", "免費", "领取", "領取",
        "红包", "紅包", "客服", "解冻", "解凍"
    ]

    static let brands: [String] = [
        "apple", "icloud", "google", "gmail", "microsoft", "office365",
        "paypal", "binance", "coinbase", "okx", "metamask", "telegram",
        "whatsapp", "facebook", "instagram", "netflix", "amazon", "alipay",
        "wechat", "taobao", "steam", "line", "shopee"
    ]

    static func analyze(_ input: String) -> URLAnalysis {
        var result = URLAnalysis()
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return result }

        var candidate = raw
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            candidate = "https://" + raw
        }

        guard let url = URL(string: candidate),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            result.findings = [URLFinding(level: .bad,
                                          title: "無法解析",
                                          detail: "這串內容不是有效的網址，請貼上完整連結。")]
            result.verdict = "格式錯誤"
            result.color = TT.rose
            return result
        }

        result.valid = true
        result.host = host
        result.scheme = url.scheme?.lowercased() ?? ""
        result.parts = buildParts(url, host: host)

        var score = 0
        var list: [URLFinding] = []
        let h = host
        let lowerHost = h

        // 1. 加密傳輸
        if result.scheme == "https" {
            list.append(URLFinding(level: .good, title: "HTTPS 加密連線",
                                   detail: "連線內容有加密，但不代表網站本身可信。"))
        } else {
            score += 22
            list.append(URLFinding(level: .bad, title: "未使用 HTTPS",
                                   detail: "明文傳輸，帳號密碼可能在途中被截取。"))
        }

        // 2. IP 直連
        if isIPAddress(lowerHost) {
            score += 30
            list.append(URLFinding(level: .bad, title: "網址直接使用 IP",
                                   detail: "正常服務幾乎不會用純 IP，這是釣魚與惡意站常見特徵。"))
        }

        // 3. 非標準端口
        if let port = url.port, port != 80, port != 443 {
            score += 14
            list.append(URLFinding(level: .warn, title: "使用非標準端口 \(port)",
                                   detail: "正式網站一般走 443，特殊端口需提高警覺。"))
        }

        // 4. 使用者資訊技巧
        if let atIndex = url.absoluteString.range(of: "@"),
           let schemeRange = url.absoluteString.range(of: "://") {
            let after = url.absoluteString[schemeRange.upperBound...]
            if after.firstIndex(of: "@") == atIndex.lowerBound {
                score += 26
                list.append(URLFinding(level: .bad, title: "含 @ 偽裝技巧",
                                       detail: "網址裡的 @ 前面是假身分，真正連線的是 @ 後面的網域。"))
            }
        }

        // 5. punycode / 非 ASCII
        if lowerHost.contains("xn--") {
            score += 24
            list.append(URLFinding(level: .bad, title: "Punycode 網域",
                                   detail: "網域含編碼字元，常被用來偽裝長得相似的外文字母。"))
        } else if !lowerHost.unicodeScalars.allSatisfy({ $0.isASCII }) {
            score += 22
            list.append(URLFinding(level: .bad, title: "網域含非英文字元",
                                   detail: "可能是視覺仿冒的國際化網域。"))
        }

        // 6. 短連結
        let root = rootDomain(h)
        if shorteners.contains(root) || shorteners.contains(h) {
            score += 18
            list.append(URLFinding(level: .warn, title: "短連結服務",
                                   detail: "看不到真正目的地，\(root) 常被拿來包裝釣魚連結。"))
        }

        // 7. 高風險頂級域
        let tld = h.split(separator: ".").last.map(String.init) ?? ""
        if riskyTLD.contains(tld) {
            score += 16
            list.append(URLFinding(level: .warn, title: "高風險頂級域 .\(tld)",
                                   detail: "此類域名註冊便宜，釣魚站比例偏高。"))
        }

        // 8. 品牌仿冒（近似拼寫）
        if let brand = closestBrand(h) {
            score += 32
            list.append(URLFinding(level: .bad, title: "疑似仿冒 \(brand)",
                                   detail: "網域與官方品牌 \(brand) 高度相似，但並非其正式域名。"))
        }

        // 9. 品牌詞出現在子域卻不是主域
        for brand in brands {
            if h.contains(brand), root != "\(brand).com", !root.hasSuffix("." + brand + ".com") {
                if h.hasPrefix(brand + ".") || h.contains("." + brand + ".") {
                    score += 26
                    list.append(URLFinding(level: .bad,
                                           title: "品牌詞被放在子域",
                                           detail: "看起來像 \(brand)，但真正的主域是 \(root)。"))
                    break
                }
            }
        }

        // 10. 誘導字詞
        let whole = url.absoluteString.lowercased()
        let hits = lureWords.filter { whole.contains($0) }
        if hits.count >= 3 {
            score += 20
            list.append(URLFinding(level: .bad, title: "大量誘導字詞",
                                   detail: "出現 \(hits.prefix(4).joined(separator: "、")) 等 \(hits.count) 個高危關鍵詞。"))
        } else if !hits.isEmpty {
            score += 8
            list.append(URLFinding(level: .warn, title: "含誘導字詞",
                                   detail: "包含 \(hits.joined(separator: "、"))，需確認對方身分。"))
        }

        // 11. 網域層級
        let labels = h.split(separator: ".").count
        if labels >= 5 {
            score += 12
            list.append(URLFinding(level: .warn, title: "子域層級過深",
                                   detail: "共 \(labels) 層，常用來稀釋視覺焦點、掩蓋真正主域。"))
        }

        // 12. 域名長度
        if h.count > 40 {
            score += 10
            list.append(URLFinding(level: .warn, title: "網域過長",
                                   detail: "長度 \(h.count) 字元，正常品牌域名通常更短。"))
        }

        // 13. 連字號
        let dashCount = h.filter { $0 == "-" }.count
        if dashCount >= 3 {
            score += 12
            list.append(URLFinding(level: .warn, title: "網域含多個連字號",
                                   detail: "共 \(dashCount) 個，是自動生成的仿冒域名常見特徵。"))
        }

        // 14. 編碼字元
        let percentCount = whole.components(separatedBy: "%").count - 1
        if percentCount >= 6 {
            score += 12
            list.append(URLFinding(level: .warn, title: "含大量編碼字元",
                                   detail: "共 \(percentCount) 處 % 編碼，可能刻意藏起真實內容。"))
        }

        // 15. 參數數量
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = comps.queryItems, items.count > 6 {
            score += 6
            list.append(URLFinding(level: .warn, title: "參數過多",
                                   detail: "共 \(items.count) 個查詢參數，可能是追蹤連結或自動生成頁面。"))
        }

        if list.isEmpty {
            list.append(URLFinding(level: .good, title: "未發現明顯異常",
                                   detail: "結構上沒有典型釣魚特徵，但仍需自行確認網站身分。"))
        }

        result.findings = list
        result.score = min(score, 100)

        switch result.score {
        case 50...:
            result.verdict = "高風險"
            result.color = TT.rose
        case 20..<50:
            result.verdict = "可疑"
            result.color = TT.amber
        default:
            result.verdict = "低風險"
            result.color = TT.mint
        }
        return result
    }

    static func buildParts(_ url: URL, host: String) -> [(String, String)] {
        var out: [(String, String)] = []
        out.append(("完整主機", host))
        out.append(("主域名", rootDomain(host)))
        out.append(("協議", (url.scheme ?? "—").uppercased()))
        if let port = url.port { out.append(("端口", "\(port)")) }
        let path = url.path
        out.append(("路徑", path.isEmpty ? "/" : path))
        if let q = url.query, !q.isEmpty {
            out.append(("參數", q.count > 60 ? String(q.prefix(60)) + "…" : q))
        }
        return out
    }

    static func rootDomain(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        if parts.count <= 2 { return host }
        return parts.suffix(2).joined(separator: ".")
    }

    static func isIPAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard let n = Int(p), n >= 0, n <= 255 else { return false }
            return true
        }
    }

    static func closestBrand(_ host: String) -> String? {
        let core = host.split(separator: ".").first.map(String.init) ?? host
        for b in brands {
            if core == b { return nil }
            let d = levenshtein(core, b)
            if d > 0 && d <= 2 && b.count >= 4 {
                return b
            }
            if core.hasPrefix(b) && core.count - b.count <= 4 && core != b {
                return b
            }
        }
        return nil
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let sa = Array(a)
        let sb = Array(b)
        if sa.isEmpty { return sb.count }
        if sb.isEmpty { return sa.count }
        var prev = Array(0...sb.count)
        var cur = [Int](repeating: 0, count: sb.count + 1)
        for i in 1...sa.count {
            cur[0] = i
            for j in 1...sb.count {
                let cost = sa[i - 1] == sb[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[sb.count]
    }
}

// MARK: - 連結檢查頁

struct LinkCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var result: URLAnalysis? = nil
    @State private var scanning = false
    @FocusState private var focused: Bool

    private let samples = ["apple.com", "https://bit.ly/3xYz", "http://192.168.1.9/login"]

    var body: some View {
        TTScreen(title: "連結安全檢查",
                 subtitle: "LINK GUARD",
                 badge: "LOCAL",
                 accent: TT.teal) {
            inputBlock
            if let r = result {
                scoreBlock(r)
                partsBlock(r)
                findingsBlock(r)
                adviceBlock(r)
            } else {
                TTPanel(accent: TT.teal) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("怎麼用")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        bullet("把收到的連結整段貼進來，按「開始檢測」")
                        bullet("會逐項檢查加密、域名結構、仿冒拼寫、誘導字詞等 15 項特徵")
                        bullet("全程在本機判斷，不會把網址送到任何伺服器")
                    }
                }
            }
        }
    }

    private var inputBlock: some View {
        VStack(spacing: 10) {
            TTPanel(accent: TT.teal) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundStyle(TT.teal)
                        TextField("", text: $input, prompt: Text("貼上要檢查的網址…")
                            .foregroundColor(.white.opacity(0.24)))
                            .font(.system(size: 13.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit { run() }
                        if !input.isEmpty {
                            Button {
                                input = ""
                                result = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(TT.teal.opacity(focused ? 0.55 : 0.16), lineWidth: 1))

                    HStack(spacing: 7) {
                        ForEach(samples, id: \.self) { s in
                            Button {
                                input = s
                                run()
                            } label: {
                                Text(s.count > 22 ? String(s.prefix(20)) + "…" : s)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    TTButton(title: scanning ? "檢測中…" : "開始檢測",
                             icon: "shield.lefthalf.filled",
                             accent: TT.teal,
                             enabled: !input.trimmingCharacters(in: .whitespaces).isEmpty && !scanning) {
                        run()
                    }
                }
            }
        }
    }

    private func scoreBlock(_ r: URLAnalysis) -> some View {
        TTPanel(accent: r.color) {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        TTRing(progress: Double(r.score) / 100.0, accent: r.color, lineWidth: 7)
                            .frame(width: 76, height: 76)
                        VStack(spacing: 0) {
                            Text("\(r.score)")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("風險")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(r.verdict)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(r.color)
                        Text(r.host)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                        Text(r.score >= 50 ? "不建議在此頁面輸入任何資料"
                             : r.score >= 20 ? "可開啟，但不要輸入帳號密碼"
                             : "結構正常，仍需確認對方身分")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }

                TTMeterBar(ratio: Double(r.score) / 100.0, accent: r.color)
            }
        }
    }

    private func partsBlock(_ r: URLAnalysis) -> some View {
        TTPanel(accent: TT.blue, padding: 14) {
            VStack(spacing: 0) {
                ForEach(Array(r.parts.enumerated()), id: \.offset) { idx, item in
                    TTKeyRow(key: item.0, value: item.1, mono: true)
                    if idx < r.parts.count - 1 {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
        }
    }

    private func findingsBlock(_ r: URLAnalysis) -> some View {
        VStack(spacing: 9) {
            TTSectionTitle(text: "逐項檢測 · \(r.findings.count) 項", accent: r.color)
            ForEach(r.findings) { f in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: f.level.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(f.level.color)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(f.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(f.level.color.opacity(0.14), lineWidth: 1))
            }
        }
    }

    private func adviceBlock(_ r: URLAnalysis) -> some View {
        TTPanel(accent: TT.amber) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(TT.amber)
                    Text("通用自保原則")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                bullet("不確定就先別點，改用官方 App 或自行輸入網址")
                bullet("任何頁面要求輸入助記詞、簡訊驗證碼，一律是詐騙")
                bullet("域名差一個字母、換個後綴，就可能是完全不同的網站")
            }
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3).padding(.top, 5)
            Text(t)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run() {
        focused = false
        scanning = true
        let text = input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.3)) {
                result = LinkGuard.analyze(text)
            }
            scanning = false
        }
    }
}

// MARK: - QR 內容解析

enum QRContent {
    static func describe(_ code: String) -> (title: String, kind: String, lines: [(String, String)], url: String?) {
        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = raw.uppercased()

        if upper.hasPrefix("WIFI:") {
            var ssid = "", type = "", pass = "", hidden = ""
            for seg in raw.dropFirst(5).split(separator: ";") {
                let parts = seg.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0].uppercased() {
                case "S": ssid = parts[1]
                case "T": type = parts[1]
                case "P": pass = parts[1]
                case "H": hidden = parts[1]
                default: break
                }
            }
            var ls: [(String, String)] = [("WiFi 名稱", ssid)]
            if !type.isEmpty { ls.append(("加密方式", type.uppercased())) }
            ls.append(("密碼", pass.isEmpty ? "（開放網路）" : pass))
            if !hidden.isEmpty { ls.append(("隱藏網路", hidden == "true" ? "是" : "否")) }
            return ("WiFi 連線設定", "WIFI", ls, nil)
        }

        if upper.hasPrefix("BEGIN:VCARD") {
            var name = "", tel = "", email = "", org = ""
            for line in raw.split(separator: "\n") {
                let l = String(line)
                if l.hasPrefix("FN:") { name = String(l.dropFirst(3)) }
                if l.hasPrefix("TEL") { tel = l.components(separatedBy: ":").last ?? "" }
                if l.hasPrefix("EMAIL") { email = l.components(separatedBy: ":").last ?? "" }
                if l.hasPrefix("ORG:") { org = String(l.dropFirst(4)) }
            }
            var ls: [(String, String)] = []
            if !name.isEmpty { ls.append(("姓名", name)) }
            if !org.isEmpty { ls.append(("公司", org)) }
            if !tel.isEmpty { ls.append(("電話", tel)) }
            if !email.isEmpty { ls.append(("信箱", email)) }
            if ls.isEmpty { ls.append(("內容", raw)) }
            return ("電子名片", "VCARD", ls, nil)
        }

        if upper.hasPrefix("MAILTO:") {
            return ("電子郵件", "EMAIL", [("收件人", String(raw.dropFirst(7)))], nil)
        }
        if upper.hasPrefix("TEL:") {
            return ("電話號碼", "TEL", [("號碼", String(raw.dropFirst(4)))], nil)
        }
        if upper.hasPrefix("SMSTO:") {
            let body = String(raw.dropFirst(6))
            let p = body.components(separatedBy: ":")
            return ("簡訊", "SMS", [("號碼", p.first ?? ""), ("內容", p.count > 1 ? p[1] : "")], nil)
        }
        if upper.hasPrefix("GEO:") {
            let body = String(raw.dropFirst(4))
            let p = body.components(separatedBy: ",")
            return ("地理座標", "GEO", [("緯度", p.first ?? ""),
                                       ("經度", p.count > 1 ? p[1] : "")], nil)
        }

        let lower = raw.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || looksLikeDomain(raw) {
            let fixed = lower.hasPrefix("http") ? raw : "https://" + raw
            return ("網址連結", "URL", [("連結", fixed)], fixed)
        }

        return ("純文字", "TEXT", [("內容", raw)], nil)
    }

    static func looksLikeDomain(_ s: String) -> Bool {
        guard !s.contains(" ") else { return false }
        let parts = s.split(separator: ".")
        guard parts.count >= 2, let last = parts.last, last.count >= 2 else { return false }
        return last.allSatisfy { $0.isLetter }
    }
}

// MARK: - QR 掃描相機

final class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scanned: String = ""
    @Published var status: String = "待機"
    @Published var failed: Bool = false

    let session = AVCaptureSession()
    private var configured = false
    private let queue = DispatchQueue(label: "mint.qr.session")

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    if ok { self?.start() } else { self?.fail("沒有相機權限") }
                }
            }
        default:
            fail("相機權限被關閉")
        }
    }

    func start() {
        if !configured {
            guard configure() else {
                fail("無法啟動相機")
                return
            }
            configured = true
        }
        status = "掃描中"
        failed = false
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func fail(_ msg: String) {
        status = msg
        failed = true
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr, .ean13, .ean8, .code128, .code39, .pdf417, .aztec, .dataMatrix]
        }
        session.commitConfiguration()
        return true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else { return }
        if value != scanned {
            scanned = value
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let v = CameraPreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

// MARK: - QR 頁

struct QRScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRScanner()
    @State private var picked: PhotosPickerItem?
    @State private var manual = false
    @State private var manualText = ""
    @State private var imageCode: String = ""

    private var activeCode: String {
        !scanner.scanned.isEmpty ? scanner.scanned : (!imageCode.isEmpty ? imageCode : manualText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        TTScreen(title: "QR 內容預覽",
                 subtitle: "QR INSPECTOR",
                 badge: scanner.failed ? "OFF" : "SCAN",
                 badgeOn: !scanner.failed,
                 accent: TT.violet) {
            cameraBlock
            pickerBlock
            if activeCode.isEmpty {
                manualBlock
            } else {
                resultBlock(activeCode)
            }
        }
        .onAppear { scanner.requestAndStart() }
        .onDisappear { scanner.stop() }
        .onChange(of: picked) { _ in loadImage() }
    }

    private var cameraBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.55))
            if !scanner.failed {
                CameraPreview(session: scanner.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            // 掃描框
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TT.mint.opacity(0.55), lineWidth: 1.6)
                .frame(width: 190, height: 190)
            cornerMarks

            if !scanner.failed {
                TTSweep(accent: TT.mint)
                    .frame(width: 190, height: 190)
                    .mask(RoundedRectangle(cornerRadius: 18).frame(width: 190, height: 190))
            }

            if scanner.failed {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(scanner.status)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("請到「設定 → 隱私權與安全性 → 相機」開啟權限")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(height: 300)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 5) {
                Circle().fill(scanner.failed ? TT.rose : TT.mint)
                    .frame(width: 5, height: 5)
                Text(scanner.failed ? "相機未啟用" : "對準 QR Code，自動辨識")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(12)
        }
    }

    private var cornerMarks: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Path { p in
                    let w: CGFloat = 190
                    let l: CGFloat = 17
                    switch i {
                    case 0:
                        p.move(to: CGPoint(x: 0, y: l))
                        p.addLine(to: .zero)
                        p.addLine(to: CGPoint(x: l, y: 0))
                    case 1:
                        p.move(to: CGPoint(x: w - l, y: 0))
                        p.addLine(to: CGPoint(x: w, y: 0))
                        p.addLine(to: CGPoint(x: w, y: l))
                    case 2:
                        p.move(to: CGPoint(x: w, y: w - l))
                        p.addLine(to: CGPoint(x: w, y: w))
                        p.addLine(to: CGPoint(x: w - l, y: w))
                    default:
                        p.move(to: CGPoint(x: l, y: w))
                        p.addLine(to: CGPoint(x: 0, y: w))
                        p.addLine(to: CGPoint(x: 0, y: w - l))
                    }
                }
                .stroke(TT.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .frame(width: 190, height: 190)
    }

    private var pickerBlock: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $picked, matching: .images) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 12))
                    Text("從相簿識別")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                manual.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 12))
                    Text("手動貼上")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(manual ? TT.violet.opacity(0.18) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(manual ? TT.violet.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var manualBlock: some View {
        TTPanel(accent: TT.violet) {
            VStack(spacing: 9) {
                TextField("", text: $manualText, prompt: Text("貼上 QR 裡的內容…")
                    .foregroundColor(.white.opacity(0.24)),
                          axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2...5)
                if !manualText.isEmpty {
                    Button {
                        manual = false
                    } label: {
                        Text("解析這段內容")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(TT.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 11).fill(TT.mint))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultBlock(_ code: String) -> some View {
        let info = QRContent.describe(code)
        let urlAnalysis = info.url != nil ? LinkGuard.analyze(info.url!) : nil

        return VStack(spacing: 12) {
            TTPanel(accent: TT.mint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(TT.mint.opacity(0.14))
                                .frame(width: 34, height: 34)
                            Image(systemName: qrIcon(info.kind))
                                .font(.system(size: 14))
                                .foregroundStyle(TT.mint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Text(info.kind)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(TT.mint.opacity(0.6))
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Text("複製")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(TT.mint)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(TT.mint.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(info.lines.enumerated()), id: \.offset) { idx, item in
                            TTKeyRow(key: item.0, value: item.1, mono: item.0 == "密碼" || item.0 == "內容")
                            if idx < info.lines.count - 1 {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
                    }

                    Text(code)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let r = urlAnalysis {
                TTPanel(accent: r.color) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("連結安全預檢")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            TTPill(text: "\(r.verdict) · \(r.score)", color: r.color)
                        }
                        TTMeterBar(ratio: Double(r.score) / 100.0, accent: r.color)
                        ForEach(r.findings.prefix(4)) { f in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: f.level.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(f.level.color)
                                Text(f.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                            }
                        }
                        if let u = info.url, let real = URL(string: u) {
                            Link(destination: real) {
                                HStack(spacing: 5) {
                                    Image(systemName: "safari")
                                    Text("仍要開啟（自行承擔風險）")
                                }
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(r.color)
                            }
                        }
                    }
                }
            }

            Button {
                scanner.scanned = ""
                imageCode = ""
                manualText = ""
            } label: {
                Text("重新掃描")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }

    private func qrIcon(_ kind: String) -> String {
        switch kind {
        case "URL":   return "link"
        case "WIFI":  return "wifi"
        case "VCARD": return "person.text.rectangle"
        case "EMAIL": return "envelope"
        case "TEL":   return "phone"
        case "SMS":   return "message"
        case "GEO":   return "location"
        default:      return "text.alignleft"
        }
    }

    private func loadImage() {
        guard let item = picked else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data),
                  let cg = img.cgImage else { return }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr, .ean13, .code128, .pdf417, .aztec, .dataMatrix]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])
            let codes = (request.results ?? []).compactMap { $0.payloadStringValue }
            await MainActor.run {
                if let first = codes.first {
                    imageCode = first
                    scanner.scanned = ""
                } else {
                    imageCode = ""
                    scanner.status = "這張圖裡沒有找到條碼"
                }
            }
        }
    }
}

// MARK: - 密碼強度

struct PasswordCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var revealed = false

    private let weakList: Set<String> = [
        "123456", "password", "123456789", "12345678", "qwerty", "abc123",
        "111111", "123123", "admin", "iloveyou", "000000", "654321",
        "qwerty123", "1q2w3e4r", "sunshine", "password1", "88888888"
    ]

    private var analysis: (score: Int, bits: Double, label: String, color: Color, items: [(String, Bool)]) {
        let p = password
        guard !p.isEmpty else {
            return (0, 0, "待輸入", TT.mint, [])
        }
        var pool = 0
        let hasLower = p.range(of: "[a-z]", options: .regularExpression) != nil
        let hasUpper = p.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasDigit = p.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSymbol = p.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        if hasLower { pool += 26 }
        if hasUpper { pool += 26 }
        if hasDigit { pool += 10 }
        if hasSymbol { pool += 33 }
        let bits = p.isEmpty ? 0 : log2(pow(Double(max(pool, 2)), Double(p.count)))
        let isWeak = weakList.contains(p.lowercased())
        let hasRepeat = hasRun(p, run: 3)
        let hasSequence = hasSequential(p)

        var score = 0
        score += min(45, Int(bits / 2.2))
        if p.count >= 12 { score += 18 }
        if p.count >= 16 { score += 10 }
        if hasSymbol { score += 8 }
        if isWeak { score = min(score, 8) }
        if hasRepeat { score -= 8 }
        if hasSequence { score -= 8 }
        score = max(0, min(100, score))

        var label = "弱"
        var color = TT.rose
        if score >= 75 { label = "很強"; color = TT.mint }
        else if score >= 50 { label = "中等"; color = TT.amber }
        else if score >= 25 { label = "偏弱"; color = TT.rose }

        let items: [(String, Bool)] = [
            ("長度 ≥ 12 位", p.count >= 12),
            ("含小寫字母", hasLower),
            ("含大寫字母", hasUpper),
            ("含數字", hasDigit),
            ("含符號", hasSymbol),
            ("非常見弱密碼", !isWeak),
            ("無連續重複字元", !hasRepeat),
            ("無鍵盤／數字序列", !hasSequence)
        ]
        return (score, bits, label, color, items)
    }

    var body: some View {
        TTScreen(title: "密碼強度",
                 subtitle: "PASSPHRASE ANALYZER",
                 badge: "OFFLINE",
                 accent: TT.rose) {
            TTPanel(accent: TT.rose) {
                VStack(spacing: 11) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(TT.rose)
                        Group {
                            if revealed {
                                TextField("", text: $password,
                                          prompt: Text("輸入要檢測的密碼…").foregroundColor(.white.opacity(0.24)))
                            } else {
                                SecureField("", text: $password,
                                            prompt: Text("輸入要檢測的密碼…").foregroundColor(.white.opacity(0.24)))
                            }
                        }
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                        Button {
                            revealed.toggle()
                        } label: {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(TT.rose.opacity(0.2), lineWidth: 1))

                    Text("全程在本機計算，不會連網、不會保存")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !password.isEmpty {
                let a = analysis
                TTPanel(accent: a.color) {
                    VStack(spacing: 13) {
                        HStack(spacing: 16) {
                            ZStack {
                                TTRing(progress: Double(a.score) / 100.0, accent: a.color, lineWidth: 7)
                                    .frame(width: 78, height: 78)
                                VStack(spacing: 0) {
                                    Text("\(a.score)")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                    Text("分")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(a.label)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(a.color)
                                Text(String(format: "熵值 ≈ %.0f bits", a.bits))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(crackTime(a.bits, label: a.label))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer(minLength: 0)
                        }
                        TTMeterBar(ratio: Double(a.score) / 100.0, accent: a.color)
                    }
                }

                TTPanel(accent: TT.blue, padding: 14) {
                    VStack(spacing: 0) {
                        ForEach(Array(a.items.enumerated()), id: \.offset) { idx, item in
                            HStack(spacing: 9) {
                                Image(systemName: item.1 ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.1 ? TT.mint : Color.white.opacity(0.18))
                                Text(item.0)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.white.opacity(item.1 ? 0.8 : 0.35))
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            if idx < a.items.count - 1 {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
                    }
                }
            }
        }
    }

    private func crackTime(_ bits: Double, label: String) -> String {
        guard bits > 0 else { return "—" }
        // 假設每秒 100 億次猜測
        let seconds = pow(2, bits - 1) / 1e10
        if seconds < 1 { return "離線暴力破解：幾乎瞬間" }
        if seconds < 60 { return String(format: "離線暴力破解：約 %.0f 秒", seconds) }
        if seconds < 3600 { return String(format: "離線暴力破解：約 %.0f 分鐘", seconds / 60) }
        if seconds < 86400 { return String(format: "離線暴力破解：約 %.0f 小時", seconds / 3600) }
        if seconds < 31536000 { return String(format: "離線暴力破解：約 %.0f 天", seconds / 86400) }
        let years = seconds / 31536000
        if years > 1e9 { return "離線暴力破解：理論上不可行" }
        return String(format: "離線暴力破解：約 %.0f 年", years)
    }

    private func hasRun(_ s: String, run: Int) -> Bool {
        let chars = Array(s)
        guard chars.count >= run else { return false }
        var count = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1] { count += 1; if count >= run { return true } }
            else { count = 1 }
        }
        return false
    }

    private func hasSequential(_ s: String) -> Bool {
        let seqs = ["0123456789", "9876543210", "abcdefghijklmnopqrstuvwxyz", "qwertyuiop", "asdfghjkl"]
        let lower = s.lowercased()
        for seq in seqs {
            let chars = Array(seq)
            for i in 0...(chars.count - 4) {
                let piece = String(chars[i..<(i + 4)])
                if lower.contains(piece) { return true }
            }
        }
        return false
    }
}
