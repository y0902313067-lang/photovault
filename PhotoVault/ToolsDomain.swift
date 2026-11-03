import SwiftUI
import UIKit
import Security

// MARK: - 資料

struct DomainReport {
    var domain: String = ""
    var aRecords: [String] = []
    var aaaaRecords: [String] = []
    var nsRecords: [String] = []
    var mxRecords: [String] = []
    var txtRecords: [String] = []
    var cnameRecords: [String] = []

    var registrar: String?
    var created: String?
    var expires: String?
    var updated: String?
    var statuses: [String] = []
    var regNameservers: [String] = []

    var certSubject: String?
    var certIssuer: String?
    var certNotBefore: Date?
    var certNotAfter: Date?

    var dnsError: String?
    var rdapError: String?
    var certError: String?
    var finishedAt = Date()
}

struct CertInfo {
    var subject: String?
    var issuer: String?
    var notBefore: Date?
    var notAfter: Date?
}

// MARK: - 查詢引擎

enum DomainEngine {

    // MARK: DNS over HTTPS（Google 優先，Cloudflare 兜底）

    static func dns(_ name: String, type: String) async -> [String] {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name

        if let list = await dohQuery("https://dns.google/resolve?name=\(escaped)&type=\(type)",
                                     customHost: false),
           !list.isEmpty {
            return list
        }
        if let list = await dohQuery("https://cloudflare-dns.com/dns-query?name=\(escaped)&type=\(type)",
                                     customHost: true),
           !list.isEmpty {
            return list
        }
        return []
    }

    private static func dohQuery(_ urlString: String, customHost: Bool) async -> [String]? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if customHost {
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let status = object["Status"] as? Int, status != 0, status != 3 { return nil }
        guard let answers = object["Answer"] as? [[String: Any]] else { return [] }

        var out: [String] = []
        for item in answers {
            guard let value = item["data"] as? String else { continue }
            out.append(value)
        }
        return out
    }

    // MARK: RDAP（WHOIS 的現代版）

    static func rdap(_ domain: String) async -> (DomainReport?, String?) {
        var report = DomainReport()
        var lastError: String?

        let candidates = rdapCandidates(domain)
        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/rdap+json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request) else {
                lastError = "連不上註冊資料服務"
                continue
            }
            guard let http = response as? HTTPURLResponse else { continue }
            guard http.statusCode == 200 else {
                lastError = http.statusCode == 404 ? "查不到這個網域的註冊資料" : "註冊資料服務回應 \(http.statusCode)"
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "註冊資料格式無法解析"
                continue
            }

            if let events = object["events"] as? [[String: Any]] {
                for event in events {
                    guard let action = event["eventAction"] as? String,
                          let date = event["eventDate"] as? String else { continue }
                    switch action {
                    case "registration": report.created = shortDate(date)
                    case "expiration":   report.expires = shortDate(date)
                    case "last changed": report.updated = shortDate(date)
                    default: break
                    }
                }
            }

            if let statuses = object["status"] as? [String] {
                report.statuses = statuses
            }

            if let servers = object["nameservers"] as? [[String: Any]] {
                for server in servers {
                    if let name = server["ldhName"] as? String {
                        report.regNameservers.append(name.lowercased())
                    }
                }
            }

            if let entities = object["entities"] as? [[String: Any]] {
                for entity in entities {
                    let roles = (entity["roles"] as? [String]) ?? []
                    if roles.contains("registrar") {
                        if let name = vcardName(entity) {
                            report.registrar = name
                        }
                        if report.registrar == nil, let handle = entity["handle"] as? String {
                            report.registrar = handle
                        }
                    }
                }
            }

            return (report, nil)
        }

        return (nil, lastError ?? "查不到註冊資料")
    }

    private static func rdapCandidates(_ domain: String) -> [String] {
        var list = ["https://rdap.org/domain/\(domain)"]
        let lowered = domain.lowercased()
        if lowered.hasSuffix(".com") || lowered.hasSuffix(".net") {
            let tld = lowered.hasSuffix(".com") ? "com" : "net"
            list.append("https://rdap.verisign.com/\(tld)/v1/domain/\(domain)")
        }
        return list
    }

    private static func vcardName(_ entity: [String: Any]) -> String? {
        guard let vcard = entity["vcardArray"] as? [Any], vcard.count > 1,
              let props = vcard[1] as? [Any] else { return nil }
        for prop in props {
            guard let fields = prop as? [Any], fields.count >= 4,
                  let key = fields[0] as? String, key == "fn",
                  let value = fields[3] as? String else { continue }
            return value
        }
        return nil
    }

    static func shortDate(_ raw: String) -> String {
        guard raw.count >= 10 else { return raw }
        let prefix = String(raw.prefix(10))
        if prefix.contains("-") { return prefix }
        // ISO8601 緊湊格式：20100101T120000Z
        let digits = prefix.filter { $0.isNumber }
        if digits.count >= 8 {
            let y = digits.prefix(4)
            let m = digits.dropFirst(4).prefix(2)
            let d = digits.dropFirst(6).prefix(2)
            return "\(y)-\(m)-\(d)"
        }
        return prefix
    }

    // MARK: 憑證

    static func certificate(host: String) async -> (CertInfo?, String?) {
        guard let url = URL(string: "https://\(host)") else { return (nil, "主機名稱無效") }
        let probe = CertProbe()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: probe, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        _ = try? await session.data(for: request)
        session.finishTasksAndInvalidate()

        if let info = probe.info {
            return (info, nil)
        }
        return (nil, "拿不到憑證，可能沒開 HTTPS 或連線失敗")
    }
}

// MARK: - 憑證抓取

final class CertProbe: NSObject, URLSessionDelegate {
    var info: CertInfo?

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            capture(trust)
        }
        completionHandler(.performDefaultHandling, nil)
    }

    private func capture(_ trust: SecTrust) {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return }

        var result = CertInfo()
        result.subject = SecCertificateCopySubjectSummary(leaf) as String?

        let der = SecCertificateCopyData(leaf) as Data
        let parsed = X509Lite.parse(der)
        result.notBefore = parsed.notBefore
        result.notAfter = parsed.notAfter
        if let first = parsed.commonNames.first {
            result.issuer = first
        }

        info = result
    }
}

// MARK: - 憑證解析（iOS 沒有現成的欄位讀取 API，直接解 DER）

enum X509Lite {

    struct TLV {
        var tag: UInt8
        var start: Int
        var end: Int
    }

    static func tlv(_ bytes: [UInt8], _ index: Int, _ limit: Int) -> TLV? {
        guard index + 2 <= limit else { return nil }
        var cursor = index
        let tag = bytes[cursor]
        cursor += 1
        var length = Int(bytes[cursor])
        cursor += 1

        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, cursor + count <= limit else { return nil }
            var value = 0
            for _ in 0..<count {
                value = (value << 8) | Int(bytes[cursor])
                cursor += 1
            }
            length = value
        }

        let end = cursor + length
        guard end <= limit, end >= cursor else { return nil }
        return TLV(tag: tag, start: cursor, end: end)
    }

    static func children(_ bytes: [UInt8], _ node: TLV) -> [TLV] {
        var out: [TLV] = []
        var cursor = node.start
        var guardCount = 0
        while cursor < node.end, guardCount < 40 {
            guard let item = tlv(bytes, cursor, node.end) else { break }
            out.append(item)
            cursor = item.end
            guardCount += 1
        }
        return out
    }

    static func parse(_ data: Data) -> (notBefore: Date?, notAfter: Date?, commonNames: [String]) {
        let bytes = [UInt8](data)
        var notBefore: Date?
        var notAfter: Date?

        if let root = tlv(bytes, 0, bytes.count), root.tag == 0x30 {
            let rootKids = children(bytes, root)
            if let tbs = rootKids.first, tbs.tag == 0x30 {
                let tbsKids = children(bytes, tbs)
                for kid in tbsKids where kid.tag == 0x30 {
                    let inner = children(bytes, kid)
                    guard inner.count == 2 else { continue }
                    guard inner[0].tag == 0x17 || inner[0].tag == 0x18 else { continue }
                    notBefore = time(bytes, inner[0])
                    notAfter = time(bytes, inner[1])
                    if notBefore != nil || notAfter != nil { break }
                }
            }
        }

        return (notBefore, notAfter, commonNames(bytes))
    }

    static func time(_ bytes: [UInt8], _ node: TLV) -> Date? {
        guard let text = String(bytes: bytes[node.start..<node.end], encoding: .utf8) else { return nil }
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: "Z", with: "")
        if let plus = raw.firstIndex(of: "+") { raw = String(raw[raw.startIndex..<plus]) }

        let formats = ["yyMMddHHmmss", "yyMMddHHmm", "yyyyMMddHHmmss", "yyyyMMddHHmm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// 掃出所有 Common Name（issuer 的 CN 在憑證結構裡排在 subject 前面）
    static func commonNames(_ bytes: [UInt8]) -> [String] {
        var results: [String] = []
        var i = 0
        while i + 6 < bytes.count {
            if bytes[i] == 0x06, bytes[i + 1] == 0x03,
               bytes[i + 2] == 0x55, bytes[i + 3] == 0x04, bytes[i + 4] == 0x03 {
                var cursor = i + 5
                let tag = bytes[cursor]
                if tag == 0x0C || tag == 0x13 || tag == 0x16 {
                    cursor += 1
                    var length = Int(bytes[cursor])
                    cursor += 1
                    if length & 0x80 != 0 {
                        let count = length & 0x7f
                        var value = 0
                        var read = 0
                        while read < count, cursor < bytes.count {
                            value = (value << 8) | Int(bytes[cursor])
                            cursor += 1
                            read += 1
                        }
                        length = value
                    }
                    if cursor + length <= bytes.count,
                       let text = String(bytes: bytes[cursor..<(cursor + length)], encoding: .utf8) {
                        results.append(text)
                    }
                }
                i += 5
                continue
            }
            i += 1
        }
        return results
    }
}

// MARK: - 頁面

struct DomainInfoView: View {
    @EnvironmentObject var store: AppStore
    @State private var input = ""
    @State private var report: DomainReport?
    @State private var loading = false
    @State private var stage = ""
    @State private var failed: String?

    private var certColor: Color {
        guard let date = report?.certNotAfter else { return TT.rose }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return TT.rose }
        if days < 21 { return TT.amber }
        return TT.mint
    }

    var body: some View {
        TTScreen(title: "網域資訊",
                 subtitle: "DOMAIN INTELLIGENCE",
                 badge: loading ? "QUERY" : (report == nil ? "IDLE" : "REPORT"),
                 badgeOn: report != nil,
                 accent: TT.blue) {

            searchBlock

            if loading {
                TTPanel(accent: TT.blue) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(TT.blue)
                        Text(stage.isEmpty ? "查詢中…" : stage)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            if let message = failed {
                TTPanel(accent: TT.rose) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(TT.rose)
                        Text(message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(TT.rose.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let rep = report {
                summaryBlock(rep)
                dnsBlock(rep)
                whoisBlock(rep)
                certBlock(rep)
                noticeBlock
            } else if !loading && failed == nil {
                TTPanel(accent: TT.blue) {
                    TTEmptyHint(icon: "globe",
                                text: "輸入網域（例如 example.com）\n一次查完 DNS、註冊資料與 HTTPS 憑證")
                }
            }
        }
        .onAppear { store.bumpTask("netdoc", add: 1) }
    }

    // MARK: 查詢

    private var searchBlock: some View {
        TTPanel(accent: TT.blue) {
            VStack(alignment: .leading, spacing: 11) {
                TextField("example.com", text: $input)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TT.blue.opacity(0.25), lineWidth: 1)
                    )

                TTButton(title: loading ? "查詢中…" : "產生技術報告",
                         icon: "magnifyingglass",
                         accent: TT.blue,
                         enabled: !loading && !normalizedDomain.isEmpty) {
                    run()
                }
            }
        }
    }

    private var normalizedDomain: String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = text.replacingOccurrences(of: "https://", with: "")
        text = text.replacingOccurrences(of: "http://", with: "")
        if let slash = text.firstIndex(of: "/") {
            text = String(text[text.startIndex..<slash])
        }
        if let colon = text.firstIndex(of: ":") {
            text = String(text[text.startIndex..<colon])
        }
        return text
    }

    // MARK: 摘要

    private func summaryBlock(_ rep: DomainReport) -> some View {
        TTPanel(accent: TT.blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [TT.blue.opacity(0.9), TT.indigo.opacity(0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(TT.ink)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rep.domain)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("查詢於 \(timeText(rep.finishedAt))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    TTStat(title: "A 記錄", value: "\(rep.aRecords.count)", unit: "筆", accent: TT.blue)
                    TTStat(title: "MX", value: "\(rep.mxRecords.count)", unit: "筆", accent: TT.teal)
                    TTStat(title: "憑證", value: certDays(rep), unit: "天", accent: certColor)
                }
            }
        }
    }

    // MARK: DNS

    private func dnsBlock(_ rep: DomainReport) -> some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "DNS 記錄", accent: TT.teal)

            TTPanel(accent: TT.teal) {
                VStack(spacing: 0) {
                    recordRows("A", rep.aRecords)
                    divider()
                    recordRows("AAAA", rep.aaaaRecords)
                    divider()
                    recordRows("CNAME", rep.cnameRecords)
                    divider()
                    recordRows("MX", rep.mxRecords)
                    divider()
                    recordRows("NS", rep.nsRecords)
                    divider()
                    recordRows("TXT", rep.txtRecords)
                }
            }

            if let err = rep.dnsError {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundStyle(TT.amber.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    private func recordRows(_ label: String, _ values: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(TT.teal)
                .frame(width: 48, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if values.isEmpty {
                    Text("—")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.22))
                } else {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func divider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
    }

    // MARK: 註冊資料

    private func whoisBlock(_ rep: DomainReport) -> some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "註冊資料 RDAP", accent: TT.violet)

            TTPanel(accent: TT.violet) {
                VStack(spacing: 0) {
                    TTKeyRow(key: "註冊商", value: rep.registrar ?? "—", accent: TT.violet)
                    divider()
                    TTKeyRow(key: "建立日期", value: rep.created ?? "—", accent: TT.violet, mono: true)
                    divider()
                    TTKeyRow(key: "到期日期", value: rep.expires ?? "—", accent: TT.violet, mono: true)
                    divider()
                    TTKeyRow(key: "最後更新", value: rep.updated ?? "—", accent: TT.violet, mono: true)
                    divider()
                    TTKeyRow(key: "網域狀態",
                             value: rep.statuses.isEmpty ? "—" : rep.statuses.joined(separator: "\n"),
                             accent: TT.violet, mono: true)
                    divider()
                    TTKeyRow(key: "名稱伺服器",
                             value: rep.regNameservers.isEmpty ? "—" : rep.regNameservers.joined(separator: "\n"),
                             accent: TT.violet, mono: true)
                }
            }

            if let err = rep.rdapError {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundStyle(TT.amber.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: 憑證

    private func certBlock(_ rep: DomainReport) -> some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "HTTPS 憑證", accent: certColor)

            TTPanel(accent: certColor) {
                VStack(spacing: 0) {
                    TTKeyRow(key: "主體", value: rep.certSubject ?? "—", accent: certColor, mono: true)
                    divider()
                    TTKeyRow(key: "簽發者", value: rep.certIssuer ?? "—", accent: certColor)
                    divider()
                    TTKeyRow(key: "生效日", value: dateText(rep.certNotBefore), accent: certColor, mono: true)
                    divider()
                    TTKeyRow(key: "到期日", value: dateText(rep.certNotAfter), accent: certColor, mono: true)
                    divider()
                    TTKeyRow(key: "剩餘", value: certDays(rep) + " 天", accent: certColor, mono: true)
                }
            }

            if let err = rep.certError {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundStyle(TT.amber.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    private var noticeBlock: some View {
        TTPanel(accent: TT.amber, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("關於註冊人")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.4))
                Text("這幾年註冊商幾乎都開了隱私保護，持有人姓名、電話、地址在公開資料裡查不到。這裡顯示的是註冊商、日期、狀態這些仍然公開的欄位，查不到的部分不會假裝有。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 動作

    private func run() {
        let domain = normalizedDomain
        guard !domain.isEmpty, !loading else { return }

        loading = true
        failed = nil
        report = nil
        stage = "查 DNS…"

        Task {
            var rep = DomainReport()
            rep.domain = domain

            async let a = DomainEngine.dns(domain, type: "A")
            async let aaaa = DomainEngine.dns(domain, type: "AAAA")
            async let ns = DomainEngine.dns(domain, type: "NS")
            async let mx = DomainEngine.dns(domain, type: "MX")
            async let txt = DomainEngine.dns(domain, type: "TXT")
            async let cname = DomainEngine.dns(domain, type: "CNAME")

            let (ra, raaaa, rns, rmx, rtxt, rcname) = await (a, aaaa, ns, mx, txt, cname)
            rep.aRecords = ra
            rep.aaaaRecords = raaaa
            rep.nsRecords = rns
            rep.mxRecords = rmx
            rep.txtRecords = rtxt
            rep.cnameRecords = rcname
            if ra.isEmpty && raaaa.isEmpty && rns.isEmpty {
                rep.dnsError = "查不到 DNS 記錄，網域可能不存在或還沒設定解析"
            }

            await MainActor.run { stage = "查註冊資料…" }

            let rdap = await DomainEngine.rdap(domain)
            if let info = rdap.0 {
                rep.registrar = info.registrar
                rep.created = info.created
                rep.expires = info.expires
                rep.updated = info.updated
                rep.statuses = info.statuses
                rep.regNameservers = info.regNameservers
            } else {
                rep.rdapError = rdap.1
            }

            await MainActor.run { stage = "檢查憑證…" }

            let cert = await DomainEngine.certificate(host: domain)
            if let info = cert.0 {
                rep.certSubject = info.subject
                rep.certIssuer = info.issuer
                rep.certNotBefore = info.notBefore
                rep.certNotAfter = info.notAfter
            } else {
                rep.certError = cert.1
            }

            rep.finishedAt = Date()

            let snap = rep
            let noData = snap.aRecords.isEmpty && snap.aaaaRecords.isEmpty
                && snap.registrar == nil && snap.certNotAfter == nil
            await MainActor.run {
                if noData {
                    failed = "這個網域查不到任何資料，確認一下拼字（不用打 https:// 或路徑）"
                }
                report = snap
                loading = false
                stage = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func certDays(_ rep: DomainReport) -> String {
        guard let date = rep.certNotAfter else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return "\(days)"
    }
}
