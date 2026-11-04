import SwiftUI
import PhotosUI

// MARK: - 聊天室（公開大廳）
//
// v38 效能改版：
// 1. 畫面只掛最近 220 則（資料仍在記憶體 5000 則裡），要更早的按一下往上載
//    —— 原本一次把 5000 則全塞進 LazyVStack，每次重繪、每幀滾動都要處理 5000 個元素
// 2. 每一則訊息做成獨立的 Equatable 視圖，內容沒變就整行跳過重繪
// 3. 只有「使用者停在底部」時才自動跟隨新訊息，往上翻歷史不會每 6 秒被拽回底部
// 4. 圖片與頭像一律降採樣解碼（見 RemoteImage.swift），不再整張原圖解開

struct ChatRoomView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var picked: PhotosPickerItem?
    @State private var attach: UIImage?
    @State private var sending = false
    @State private var tip: String?
    @State private var guest: String?
    @State private var loading = true
    @State private var timer: Timer?
    @State private var stickToBottom = true
    @State private var didInitialScroll = false
    /// 正在回覆哪一條
    @State private var replying: ReplyTarget?

    /// 一次渲染幾則（往上按一下再加一頁）
    private let pageSize = 220
    @State private var renderCount = 220

    private let bottomID = "pv.chat.bottom"

    private var rendered: ArraySlice<ChatMessage> {
        messages.suffix(max(pageSize, renderCount))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if messages.count > rendered.count {
                                    loadEarlierBar(proxy)
                                }

                                ForEach(rendered) { m in
                                    ChatRow(m: m,
                                            mine: m.userID == (store.authUserID ?? ""),
                                            myLevel: store.level,
                                            myProfileID: store.profileID ?? "",
                                            myAvatar: store.avatarImage,
                                            myFrame: store.myFrame,
                                            onGuest: { pid in
                                                if !pid.isEmpty { guest = pid }
                                            },
                                            onReply: { msg in
                                                let raw = msg.bodyText.isEmpty
                                                    ? (msg.image != nil ? "[圖片]" : "")
                                                    : msg.bodyText
                                                replying = ReplyTarget(nick: msg.nickname, quote: raw)
                                            })
                                    .equatable()
                                    .id(m.id)
                                }

                                if messages.isEmpty && !loading {
                                    VStack(spacing: 8) {
                                        Image(systemName: "bubble.left.and.bubble.right")
                                            .font(.system(size: 26))
                                            .foregroundStyle(.white.opacity(0.16))
                                        Text("大廳還很安靜，說句話吧")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomID)
                                    .onAppear { stickToBottom = true }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { v in
                                    // 往上拖就不要再自動跟隨
                                    if v.translation.height > 10 { stickToBottom = false }
                                }
                        )
                        .onChange(of: messages.count) { _ in
                            guard stickToBottom || !didInitialScroll else { return }
                            scrollDown(proxy, animated: didInitialScroll)
                            didInitialScroll = true
                        }

                        if !stickToBottom && !messages.isEmpty {
                            Button {
                                stickToBottom = true
                                scrollDown(proxy, animated: true)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 11, weight: .heavy))
                                    Text("最新")
                                        .font(.system(size: 11.5, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(Color(red: 0.10, green: 0.13, blue: 0.18)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                        }
                    }
                }

                inputBar
            }
            .background(Backdrop())
            .navigationTitle("聊天室")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .sheet(item: Binding(
                get: { guest.map { GuestBox(id: $0) } },
                set: { guest = $0?.id })) { box in
                ProfilePageView(profileID: box.id, embedded: false)
            }
            .task {
                await load()
                if scenePhase == .active { startPolling() }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    startPolling()
                    Task { await poll() }
                } else {
                    stopPolling()
                }
            }
            .onDisappear { stopPolling() }
        }
    }

    struct GuestBox: Identifiable { let id: String }

    struct ReplyTarget: Identifiable {
        let id = UUID()
        let nick: String
        let quote: String
    }

    // MARK: 往上載入更早

    private func loadEarlierBar(_ proxy: ScrollViewProxy) -> some View {
        Button {
            let anchor = rendered.first?.id
            renderCount = min(messages.count, renderCount + pageSize)
            if let anchor {
                DispatchQueue.main.async {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                Text("載入更早的訊息")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    // MARK: 輸入區

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let replying {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(TT.mint.opacity(0.7))
                        .frame(width: 2.5, height: 26)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("回覆 \(replying.nick)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TT.mint.opacity(0.95))
                        Text(replying.quote)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Button { self.replying = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 14)
            }

            if let attach {
                HStack(spacing: 8) {
                    Image(uiImage: attach).resizable().scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text("已附加 1 張圖片")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button { self.attach = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 14)
            }

            if let tip {
                Text(tip)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TT.rose)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 9) {
                PhotosPicker(selection: $picked, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 38, height: 38)
                }

                TextField("說點什麼…", text: $input)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))

                Button { send() } label: {
                    ZStack {
                        Circle().fill(TT.mint)
                        if sending {
                            ProgressView().tint(Color(red: 0.03, green: 0.09, blue: 0.08))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .disabled(sending || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      && attach == nil && replying == nil))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(
            Color(red: 0.05, green: 0.065, blue: 0.09)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.6)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .onChange(of: picked) { item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: d) {
                    await MainActor.run { attach = img }
                }
                await MainActor.run { picked = nil }
            }
        }
    }

    // MARK: 資料

    /// 首次進場 / 手動刷新：抓最近 300 則（含首頁一次帶回），併進本機快取
    private func load() async {
        // 先用本機快取把畫面填上，開聊天室不用先空等網路
        let cached = ChatCache.shared.tail(ChatCache.diskLimit)
        if !cached.isEmpty {
            await MainActor.run {
                messages = cached
                loading = false
            }
        }

        let recent = await SocialAPI.loadChatRecent(token: store.authToken, limit: 300)
        let list: [ChatMessage]
        if recent.isEmpty {
            // 離線：只顯示本機最近的 300 則
            list = ChatCache.shared.offlineTail
        } else {
            list = ChatCache.shared.merge(recent)
        }
        let tail = Array(list.suffix(ChatCache.diskLimit))
        await MainActor.run {
            messages = tail
            loading = false
        }
    }

    /// 輪詢：只抓比最後一條更新的，且只把「新增的那幾條」接到畫面後面
    private func poll() async {
        let since = await MainActor.run { messages.last?.created ?? Date(timeIntervalSince1970: 0) }
        let fresh = await SocialAPI.loadChatSince(since, token: store.authToken, limit: 200)
        guard !fresh.isEmpty else { return }

        let added = ChatCache.shared.appendNew(fresh)
        guard !added.isEmpty else { return }

        await MainActor.run {
            messages.append(contentsOf: added)
            if messages.count > ChatCache.diskLimit {
                let drop = messages.count - ChatCache.diskLimit
                messages.removeFirst(drop)
                renderCount = max(pageSize, renderCount - drop)
            }
        }
    }

    private func startPolling() {
        stopPolling()
        let t = Timer(timeInterval: 6, repeats: true) { _ in
            Task { await poll() }
        }
        t.tolerance = 1.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func send() {
        guard !sending, let uid = store.authUserID else { return }
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        tip = nil
        Task {
            do {
                let quote = replying.map { (nick: $0.nick, quote: $0.quote) }
                try await SocialAPI.sendChat(userID: uid, text: t, image: attach,
                                             replyTo: quote, token: store.authToken)
                store.bumpTask("socialking", add: 1)
                await MainActor.run {
                    input = ""
                    attach = nil
                    sending = false
                    replying = nil
                    stickToBottom = true
                }
                // 只補抓新的那幾條，不再整批重載
                await poll()
            } catch {
                await MainActor.run {
                    sending = false
                    tip = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 單一則訊息
//
// 獨立成 Equatable 視圖：訊息內容沒變時整行不做 body 求值，
// 滑動與輪詢時省下大量重繪。

private struct ChatRow: View, Equatable {
    let m: ChatMessage
    let mine: Bool
    let myLevel: MemberLevel
    let myProfileID: String
    let myAvatar: UIImage?
    let myFrame: String?
    let onGuest: (String) -> Void
    let onReply: (ChatMessage) -> Void

    static func == (a: ChatRow, b: ChatRow) -> Bool {
        a.m == b.m
            && a.mine == b.mine
            && a.myLevel == b.myLevel
            && a.myProfileID == b.myProfileID
            && a.myAvatar === b.myAvatar
            && a.myFrame == b.myFrame
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if mine { Spacer(minLength: 40) }

            if !mine {
                Button { onGuest(m.profileID) } label: {
                    AvatarBubble(profileID: m.profileID, file: m.avatar, size: 38, ring: m.level,
                                 frame: Frames.equipped(in: m.titles)?.storeKey)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(m.nickname)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    // 自己發的那條用本機目前等級，避免伺服器留有舊記錄時少顯示一階
                    LevelTagInline(level: mine ? myLevel : m.level)
                }
                .frame(maxWidth: mine ? .infinity : nil,
                       alignment: mine ? .trailing : .leading)

                if let q = m.replyQuote {
                    replyBlock(q)
                }

                if !m.bodyText.isEmpty {
                    Text(m.bodyText)
                        .font(.system(size: 14.5))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(mine ? TT.mint.opacity(0.16) : Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(mine ? TT.mint.opacity(0.28)
                                                   : Color.white.opacity(0.06),
                                              lineWidth: 0.8)
                        )
                }

                if let img = m.image,
                   let url = SocialAPI.fileURL(collection: "chat", record: m.id, file: img) {
                    CachedImage(url: url, maxPixel: 380, placeholder: AnyView(
                        ZStack {
                            Color.white.opacity(0.05)
                            ProgressView().tint(.white.opacity(0.35))
                        }
                    ))
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text(shortTime(m.created))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.22))
            }

            if mine {
                AvatarBubble(profileID: myProfileID, file: nil,
                             size: 38, ring: myLevel, localImage: myAvatar,
                             frame: myFrame)
            }

            if !mine { Spacer(minLength: 40) }
        }
        .contextMenu {
            Button {
                onReply(m)
            } label: {
                Label("回覆", systemImage: "arrowshape.turn.up.left.fill")
            }
        }
    }

    /// 引用別人的那段（左側一條細線 + 暱稱 + 摘要）
    private func replyBlock(_ q: (nick: String, quote: String)) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(mine ? TT.mint.opacity(0.55) : Color.white.opacity(0.22))
                .frame(width: 2.5, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(q.nick)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(mine ? TT.mint.opacity(0.85) : Color.white.opacity(0.55))
                    .lineLimit(1)
                Text(q.quote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            .frame(maxWidth: 190, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}
