import SwiftUI
import UIKit

// MARK: - 資料結構

struct APIHeaderRow: Identifiable, Equatable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}

struct APIResult {
    var status: Int = 0
    var duration: Double = 0
    var headers: [(String, String)] = []
    var body: String = ""
    var bytes: Int = 0
    var error: String?
    var requestMethod: String = "GET"
    var requestURL: String = ""
}

struct APIHistoryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var method: String
    var url: String
    var at: Date
}

// MARK: - 引擎

enum APIEngine {

    static func send(method: String,
                     urlText: String,
                     headers: [(String, String)],
                     body: String?) async -> APIResult {
        var result = APIResult()
        result.requestMethod = method
        result.requestURL = urlText

        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            result.error = "網址格式不正確，要含 http:// 或 https://"
            return result
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData

        for (key, value) in headers {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { continue }
            request.setValue(value, forHTTPHeaderField: k)
        }

        if method != "GET", method != "HEAD",
           let raw = body, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.httpBody = Data(raw.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                let looksJSON = raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                    || raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
                request.setValue(looksJSON ? "application/json" : "text/plain",
                                 forHTTPHeaderField: "Content-Type")
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            result.duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            result.bytes = data.count

            if let http = response as? HTTPURLResponse {
                result.status = http.statusCode
                var list: [(String, String)] = []
                for (key, value) in http.allHeaderFields {
                    list.append(("\(key)", "\(value)"))
                }
                result.headers = list.sorted { $0.0.lowercased() < $1.0.lowercased() }
            } else {
                result.status = 0
            }

            if let text = String(data: data, encoding: .utf8) {
                result.body = String(text.prefix(120_000))
            } else {
                result.body = "（非 UTF-8 資料，共 \(data.count) bytes，無法以文字顯示）"
            }
            return result
        } catch {
            result.duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            result.error = describe(error)
            return result
        }
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorTimedOut:            return "請求逾時（30 秒）"
        case NSURLErrorCannotFindHost:      return "找不到這個主機，檢查網域是否正確"
        case NSURLErrorCannotConnectToHost: return "連不上主機，可能是埠號不對或被防火牆擋住"
        case NSURLErrorNotConnectedToInternet: return "目前沒有網路連線"
        case NSURLErrorSecureConnectionFailed: return "TLS 交握失敗，憑證可能不被信任"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "系統拒絕明文連線"
        case NSURLErrorCancelled:           return "請求已取消"
        default:                            return ns.localizedDescription
        }
    }

    static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        guard let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    static func curl(method: String, url: String, headers: [(String, String)], body: String?) -> String {
        var out = "curl -X \(method) '\(url)'"
        for (key, value) in headers where !key.trimmingCharacters(in: .whitespaces).isEmpty {
            out += " \\\n  -H '\(key): \(value)'"
        }
        if let body = body, !body.isEmpty, method != "GET" {
            out += " \\\n  --data '\(body.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return out
    }
}

// MARK: - 語法著色

enum JSONHighlighter {

    static func attributed(_ text: String) -> AttributedString {
        let limit = 20_000
        let clipped = text.count > limit ? String(text.prefix(limit)) : text
        var out = AttributedString()
        let chars = Array(clipped)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            if ch == "\"" {
                var j = i + 1
                var escaped = false
                while j < chars.count {
                    let c = chars[j]
                    if escaped {
                        escaped = false
                    } else if c == "\\" {
                        escaped = true
                    } else if c == "\"" {
                        j += 1
                        break
                    }
                    j += 1
                }
                var part = AttributedString(String(chars[i..<j]))
                part.foregroundColor = TT.mint
                out.append(part)
                i = j
                continue
            }

            if ch.isNumber {
                var j = i
                while j < chars.count,
                      chars[j].isNumber || chars[j] == "." || chars[j] == "-"
                        || chars[j] == "+" || chars[j] == "e" || chars[j] == "E" {
                    j += 1
                }
                var part = AttributedString(String(chars[i..<j]))
                part.foregroundColor = TT.amber
                out.append(part)
                i = j
                continue
            }

            if ch.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter {
                    j += 1
                }
                var part = AttributedString(String(chars[i..<j]))
                part.foregroundColor = TT.violet
                out.append(part)
                i = j
                continue
            }

            var part = AttributedString(String(ch))
            part.foregroundColor = Color.white.opacity(0.55)
            out.append(part)
            i += 1
        }

        if text.count > limit {
            var tail = AttributedString("\n…（內容超過 \(limit) 字，僅顯示前面部分，可複製全文）")
            tail.foregroundColor = Color.white.opacity(0.3)
            out.append(tail)
        }
        return out
    }
}

// MARK: - 頁面

struct APILabView: View {
    @State private var method = "GET"
    @State private var urlText = ""
    @State private var headers: [APIHeaderRow] = [APIHeaderRow(key: "Accept", value: "application/json")]
    @State private var bodyText = ""
    @State private var result: APIResult?
    @State private var loading = false
    @State private var showHeaders = false
    @State private var rawMode = false
    @State private var copied = false
    @State private var history: [APIHistoryItem] = []

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]
    private let historyKey = "md.api.history"

    private var methodColor: Color {
        switch method {
        case "GET":    return TT.mint
        case "POST":   return TT.blue
        case "PUT":    return TT.amber
        case "PATCH":  return TT.violet
        case "DELETE": return TT.rose
        default:       return TT.teal
        }
    }

    private var statusColor: Color {
        guard let code = result?.status else { return TT.rose }
        if code >= 200 && code < 300 { return TT.mint }
        if code >= 300 && code < 400 { return TT.blue }
        if code >= 400 && code < 500 { return TT.amber }
        return TT.rose
    }

    var body: some View {
        TTScreen(title: "API 測試台",
                 subtitle: "API WORKBENCH",
                 badge: loading ? "SENDING" : (result == nil ? "IDLE" : "\(result?.status ?? 0)"),
                 badgeOn: result != nil,
                 accent: methodColor) {

            requestBlock
            headerBlock
            if method != "GET" && method != "HEAD" {
                bodyBlock
            }

            TTButton(title: loading ? "請求中…" : "發送請求",
                     icon: "paperplane.fill",
                     accent: methodColor,
                     enabled: !loading && !urlText.trimmingCharacters(in: .whitespaces).isEmpty) {
                send()
            }

            if let res = result {
                resultBlock(res)
            } else {
                TTPanel(accent: TT.teal) {
                    TTEmptyHint(icon: "network",
                                text: "填入 API 網址送出\n狀態碼、耗時、回應標頭、JSON 全部攤開看")
                }
            }

            if !history.isEmpty {
                historyBlock
            }
        }
        .onAppear(perform: loadHistory)
    }

    // MARK: 請求

    private var requestBlock: some View {
        TTPanel(accent: methodColor) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(methods, id: \.self) { item in
                            Button {
                                method = item
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(item)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(method == item ? TT.ink : Color.white.opacity(0.5))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(
                                        Capsule().fill(method == item
                                                       ? AnyShapeStyle(methodColor)
                                                       : AnyShapeStyle(Color.white.opacity(0.05)))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }

                TextField("https://api.example.com/v1/items", text: $urlText)
                    .font(.system(size: 13, design: .monospaced))
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
                            .strokeBorder(methodColor.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: 標頭

    private var headerBlock: some View {
        TTPanel(accent: TT.indigo) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("請求標頭 HEADERS")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button {
                        headers.append(APIHeaderRow())
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("新增")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(TT.indigo)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(TT.indigo.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }

                ForEach($headers) { $row in
                    HStack(spacing: 7) {
                        TextField("Key", text: $row.key)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 9)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        TextField("Value", text: $row.value)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 9)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        Button {
                            headers.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(TT.rose.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if headers.isEmpty {
                    Text("沒有自訂標頭，會用系統預設")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.24))
                }
            }
        }
    }

    // MARK: 內容

    private var bodyBlock: some View {
        TTPanel(accent: TT.amber) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("請求內容 BODY")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text("\(bodyText.count) 字元")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.24))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $bodyText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 110)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(TT.amber.opacity(0.2), lineWidth: 1)
                        )
                    if bodyText.isEmpty {
                        Text("{\n  \"key\": \"value\"\n}")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(.horizontal, 14)
                            .padding(.top, 13)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: 結果

    private func resultBlock(_ res: APIResult) -> some View {
        VStack(spacing: 12) {
            TTPanel(accent: statusColor) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(res.status == 0 ? "ERR" : "\(res.status)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusText(res.status))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("\(res.requestMethod) · \(res.requestURL)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        TTStat(title: "耗時", value: String(format: "%.0f", res.duration), unit: "ms", accent: statusColor)
                        TTStat(title: "大小", value: sizeText(res.bytes), accent: TT.teal)
                        TTStat(title: "標頭", value: "\(res.headers.count)", unit: "項", accent: TT.indigo)
                    }

                    if let error = res.error {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(TT.rose)
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(TT.rose.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(TT.rose.opacity(0.10))
                        )
                    }
                }
            }

            if !res.headers.isEmpty {
                headerResultBlock(res)
            }

            if !res.body.isEmpty {
                bodyResultBlock(res)
            }
        }
    }

    private func headerResultBlock(_ res: APIResult) -> some View {
        TTPanel(accent: TT.indigo) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { showHeaders.toggle() }
                } label: {
                    HStack {
                        Text("回應標頭")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Image(systemName: showHeaders ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)

                if showHeaders {
                    VStack(spacing: 0) {
                        ForEach(0..<res.headers.count, id: \.self) { index in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: 1)
                            }
                            TTKeyRow(key: res.headers[index].0,
                                     value: res.headers[index].1,
                                     accent: TT.indigo,
                                     mono: true)
                        }
                    }
                }
            }
        }
    }

    private func bodyResultBlock(_ res: APIResult) -> some View {
        let pretty = APIEngine.prettyJSON(res.body)
        let display = rawMode ? res.body : (pretty ?? res.body)
        let isJSON = pretty != nil

        return TTPanel(accent: TT.mint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("回應內容")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    if isJSON {
                        Button {
                            rawMode.toggle()
                        } label: {
                            Text(rawMode ? "格式化" : "原始")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(TT.amber)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Capsule().fill(TT.amber.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        UIPasteboard.general.string = res.body
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Text(copied ? "已複製" : "複製")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(TT.mint)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(Capsule().fill(TT.mint.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(isJSON && !rawMode ? JSONHighlighter.attributed(display)
                                            : AttributedString(rawPlain(display)))
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 320)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func rawPlain(_ text: String) -> String {
        if text.count > 20_000 {
            return String(text.prefix(20_000)) + "\n…（內容過長，僅顯示前面部分）"
        }
        return text
    }

    // MARK: 歷史

    private var historyBlock: some View {
        VStack(spacing: 10) {
            TTSectionTitle(text: "最近請求", accent: TT.teal)

            VStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                    }
                    Button {
                        method = item.method
                        urlText = item.url
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.method)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(TT.teal)
                                .frame(width: 52, alignment: .leading)
                            Text(item.url)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: 動作

    private func send() {
        guard !loading else { return }
        loading = true
        rawMode = false

        let headerPairs = headers.map { ($0.key, $0.value) }
        let body: String? = (method == "GET" || method == "HEAD") ? nil : bodyText
        let currentMethod = method
        let currentURL = urlText

        Task {
            let res = await APIEngine.send(method: currentMethod,
                                           urlText: currentURL,
                                           headers: headerPairs,
                                           body: body)
            await MainActor.run {
                result = res
                loading = false
                remember(method: currentMethod, url: currentURL)
                if res.error == nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func remember(method: String, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.removeAll { $0.url == trimmed && $0.method == method }
        history.insert(APIHistoryItem(method: method, url: trimmed, at: Date()), at: 0)
        if history.count > 8 { history = Array(history.prefix(8)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let list = try? JSONDecoder().decode([APIHistoryItem].self, from: data) else { return }
        history = list
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 0:   return "沒有回應"
        case 200: return "OK · 成功"
        case 201: return "Created · 已建立"
        case 204: return "No Content · 無內容"
        case 301, 302: return "Redirect · 重新導向"
        case 304: return "Not Modified · 未變更"
        case 400: return "Bad Request · 參數有問題"
        case 401: return "Unauthorized · 需要驗證"
        case 403: return "Forbidden · 沒有權限"
        case 404: return "Not Found · 找不到"
        case 405: return "Method Not Allowed · 方法不支援"
        case 408: return "Request Timeout · 逾時"
        case 429: return "Too Many Requests · 被限流"
        case 500: return "Server Error · 伺服器錯誤"
        case 502: return "Bad Gateway · 上游錯誤"
        case 503: return "Service Unavailable · 服務不可用"
        case 504: return "Gateway Timeout · 上游逾時"
        default:  return code < 400 ? "已回應" : "錯誤"
        }
    }

    private func sizeText(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)" }
        if bytes < 1024 * 1024 { return String(format: "%.1fK", Double(bytes) / 1024) }
        return String(format: "%.1fM", Double(bytes) / 1024 / 1024)
    }
}
