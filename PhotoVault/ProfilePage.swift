import SwiftUI
import PhotosUI
import AVKit

// MARK: - 頭像

struct AvatarBubble: View {
    let profileID: String
    let file: String?
    var size: CGFloat = 84
    var ring: MemberLevel? = nil
    var localImage: UIImage? = nil
    /// 戴著的頭框（"frame.flame"）；戴框時整個元件會比頭像大一圈
    var frame: String? = nil

    private var framed: Bool { Frames.find(frame ?? "") != nil }
    private var outer: CGFloat { framed ? size / Frames.avatarRatio : size }

    var body: some View {
        ZStack {
            if let ring, ring.glow.hasGlow {
                Circle()
                    .fill(RadialGradient(
                        colors: [ring.glow.haloColor.opacity(ring.glow.haloOpacity * 0.9), .clear],
                        center: .center, startRadius: 0, endRadius: size * 0.78))
                    .frame(width: size * 1.55, height: size * 1.55)
            }

            Circle()
                .fill(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.32),
                                            Color(red: 0.09, green: 0.12, blue: 0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: size, height: size)

            if let localImage {
                Image(uiImage: localImage).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let file, let url = SocialAPI.fileURL(collection: "profiles", record: profileID, file: file) {
                CachedImage(url: url, maxPixel: size * 3, placeholder: AnyView(
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.40))
                        .foregroundStyle(.white.opacity(0.28))
                ))
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.40))
                    .foregroundStyle(.white.opacity(0.28))
            }

            Circle()
                .strokeBorder(
                    LinearGradient(colors: ringStroke,
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: size > 60 ? 2 : 1.4)
                .frame(width: size, height: size)

            AvatarFrameLayer(raw: frame, avatar: size)
        }
        .frame(width: outer, height: outer)
    }

    private var ringStroke: [Color] {
        guard let ring else {
            return [Color.white.opacity(0.18), Color.white.opacity(0.06)]
        }
        switch ring {
        case .gold:     return [TT.amber.opacity(0.85), TT.amber.opacity(0.2)]
        case .platinum: return [TT.rose.opacity(0.85), TT.rose.opacity(0.2)]
        case .common:   return [Color.white.opacity(0.2), Color.white.opacity(0.06)]
        case .silver:   return [Color(red: 0.85, green: 0.90, blue: 1).opacity(0.5),
                                Color.white.opacity(0.12)]
        default:        return [TT.amber.opacity(0.9), TT.amber.opacity(0.25)]
        }
    }
}

// MARK: - 動態卡片

/// v47：長按選單改成「需要才掛」。
/// 主頁的卡片自己已經有垃圾桶按鈕，不需要再掛一層 UIKit 長按互動；
/// 幾十張卡片各掛一個 contextMenu，等於幾十個互動區域要在滾動時維護，
/// 這是主頁卡頓裡很容易被漏掉的一筆。
private struct PostContextMenu: ViewModifier {
    let enabled: Bool
    let onDelete: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let onDelete {
            content.contextMenu {
                Button(role: .destructive) { onDelete() } label: {
                    Label("刪除這則動態", systemImage: "trash")
                }
            }
        } else {
            content
        }
    }
}

struct PostCard: View {
    let post: FeedPost
    var showAuthor: Bool = true
    var onAvatarTap: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    /// 這則動態的愛心與留言
    var social: PostSocial = PostSocial()
    var canInteract: Bool = false
    var myUserID: String? = nil
    var onToggleLike: (() -> Void)? = nil
    var onSendComment: ((String) -> Void)? = nil
    var onDeleteComment: ((PostComment) -> Void)? = nil

    @State private var showComments = false
    @State private var showAllComments = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var shownComments: [PostComment] {
        if showAllComments || social.comments.count <= 3 { return social.comments }
        return Array(social.comments.suffix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showAuthor {
                HStack(spacing: 9) {
                    Button {
                        onAvatarTap?(post.profileID)
                    } label: {
                        AvatarBubble(profileID: post.profileID, file: post.avatar,
                                     size: 38, ring: post.level,
                                     frame: Frames.equipped(in: post.titles)?.storeKey)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(post.nickname)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                            LevelTagInline(level: post.level)
                        }
                        if let def = post.titles.compactMap({ Titles.find($0) })
                            .max(by: { $0.tier < $1.tier }) {
                            TitleChip(title: def, size: 0.66, animated: false)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(shortTime(post.created))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if !showAuthor {
                HStack(spacing: 8) {
                    Text(shortTime(post.created))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer(minLength: 4)
                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(TT.rose.opacity(0.85))
                                .frame(width: 30, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !post.text.isEmpty {
                Text(post.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !post.images.isEmpty {
                PostImages(post: post)
            }

            if let video = post.video,
               let url = SocialAPI.fileURL(collection: "posts", record: post.id, file: video) {
                VideoPlayerCard(url: url)
            }

            actionBar

            if showComments || !social.comments.isEmpty {
                commentArea
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .modifier(PostContextMenu(enabled: showAuthor && onDelete != nil, onDelete: onDelete))
    }

    // MARK: 愛心 / 留言

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleLike?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: social.likedByMe ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: social.likedByMe ? .semibold : .regular))
                        .foregroundStyle(social.likedByMe ? TT.rose : Color.white.opacity(0.55))
                        .scaleEffect(social.likedByMe ? 1.08 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: social.likedByMe)
                    Text("\(social.likes)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(social.likedByMe ? TT.rose : Color.white.opacity(0.42))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canInteract)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) { showComments.toggle() }
                if !showComments { inputFocused = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text("\(social.comments.count)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.42))
                    if social.comments.isEmpty {
                        Text("留言")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.32))
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.7)
                .offset(y: -2)
        }
    }

    private var commentArea: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !social.comments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !showAllComments, social.comments.count > 3 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.16)) { showAllComments = true }
                        } label: {
                            Text("查看全部 \(social.comments.count) 條留言")
                                .font(.system(size: 11))
                                .foregroundStyle(TT.mint.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(shownComments) { c in
                        commentRow(c)
                    }
                }
                .padding(.leading, 2)
            } else {
                Text("還沒有人留言，說兩句吧")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.vertical, 2)
            }

            if canInteract {
                HStack(spacing: 8) {
                    TextField("寫點什麼…", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.92))
                        .focused($inputFocused)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7)
                        )

                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        draft = ""
                        inputFocused = true
                        onSendComment?(text)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                             ? Color.white.opacity(0.18) : TT.mint)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.top, 9)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func commentRow(_ c: PostComment) -> some View {
        HStack(alignment: .top, spacing: 7) {
            AvatarBubble(profileID: c.profileID, file: c.avatar, size: 24, ring: c.level)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.nickname)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Text(shortTime(c.created))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.26))
                    Spacer(minLength: 4)
                    if canInteract, c.userID == myUserID {
                        Button {
                            onDeleteComment?(c)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(width: 20, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(c.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PostImages: View {
    let post: FeedPost
    @State private var viewerIndex: Int? = nil

    /// 依張數決定每行幾格
    private static func columns(for n: Int) -> Int {
        switch n {
        case 1: return 1
        case 2: return 2
        case 4: return 2
        case 8: return 4
        default: return 3
        }
    }

    private var urls: [URL] {
        post.images.compactMap { SocialAPI.fileURL(collection: "posts", record: post.id, file: $0) }
    }

    var body: some View {
        let n = post.images.count
        let cols = Self.columns(for: n)
        let grid = Array(repeating: GridItem(.flexible(), spacing: 5), count: cols)
        let pad = (cols - n % cols) % cols

        LazyVGrid(columns: grid, spacing: 5) {
            ForEach(Array(post.images.enumerated()), id: \.offset) { idx, name in
                cell(name: name, index: idx)
            }
            if pad > 0 {
                ForEach(0..<pad, id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewerIndex != nil },
            set: { if !$0 { viewerIndex = nil } }
        )) {
            PhotoViewer(urls: urls, start: viewerIndex ?? 0)
        }
    }

    @ViewBuilder
    private func cell(name: String, index: Int) -> some View {
        if let url = SocialAPI.fileURL(collection: "posts", record: post.id, file: name) {
            Button {
                viewerIndex = index
            } label: {
                // v44：改走記憶體快取 + 降採樣解碼。
                // 原本是 AsyncImage，滑動時每個格子重建就重新下載、重新解整張原圖，
                // 動態一多就是主頁卡頓最大的一筆。這裡按格子實際像素解成小圖。
                CachedImage(url: url, maxPixel: 420,
                            placeholder: AnyView(
                                ZStack {
                                    Color.white.opacity(0.05)
                                    ProgressView().tint(.white.opacity(0.4))
                                }
                            ))
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct VideoPlayerCard: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white.opacity(0.5))
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if player == nil { player = AVPlayer(url: url) }
        }
        .onDisappear {
            // v47：滾出畫面就停手。這頁是常駐的，影片掛著不動也會一直佔解碼與記憶體。
            player?.pause()
        }
        .onTapGesture {
            player?.play()
        }
    }
}

struct LevelTagInline: View {
    let level: MemberLevel
    var body: some View {
        MemberPill(level: level, compact: true)
    }
}

private let pvShortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d"
    return f
}()

func shortTime(_ d: Date) -> String {
    let now = Date()
    let gap = now.timeIntervalSince(d)
    if gap < 60 { return "剛剛" }
    if gap < 3600 { return "\(Int(gap / 60)) 分鐘前" }
    if gap < 86400 { return "\(Int(gap / 3600)) 小時前" }
    if gap < 86400 * 7 { return "\(Int(gap / 86400)) 天前" }
    return pvShortDateFormatter.string(from: d)
}

// MARK: - 頭貼選擇

struct AvatarPickerSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.white.opacity(0.18))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            Text("更換頭貼")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            ZStack {
                if let img = store.avatarImage {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(Circle())

            PhotosPicker(selection: $picked, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text("從相簿選一張")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(TT.mint))
            }
            .padding(.horizontal, 24)

            if store.avatarUploading {
                ProgressView().tint(TT.mint)
            }

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.07, blue: 0.10).ignoresSafeArea())
        .onChange(of: picked) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { store.changeAvatar(img) }
                }
                await MainActor.run { picked = nil }
            }
        }
    }
}

// MARK: - 個人主頁

struct ProfilePageView: View {
    /// nil = 自己
    var profileID: String? = nil
    var embedded: Bool = false

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var showLevelInfo = false
    @State private var showComposer = false
    @State private var showTitleEditor = false
    @StateObject private var titleLayout = TitleLayoutStore()
    /// 雲端那條編排記錄的 id（避免每次改順序都新增一條）
    @State private var layoutRecordID: String?
    @State private var layoutPushTask: Task<Void, Never>?
    @State private var posts: [FeedPost] = []
    @State private var social: [String: PostSocial] = [:]
    @State private var other: PublicUser?
    @State private var loading = true
    @State private var guestProfile = ""
    /// v47：上次真正抓資料的時間，切分頁回來不必每次全量重拉
    @State private var lastLoad = Date.distantPast
    // v44：原本 60 秒一次。刷新本身有網路往返，加上主頁重算，滑動時很容易撞上。
    // 會員等級／稱號這種資料本來就不會秒級變動，拉長到 5 分鐘，進頁面時另外還會刷一次。
    private let ticker = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    // v46：這一頁是常駐的（切分頁只是改透明度），所以看不見時也要停手。
    @Environment(\.tabActive) private var tabActive

    private var isMe: Bool { profileID == nil }

    private var pid: String { profileID ?? (store.profileID ?? "") }

    private var shownName: String {
        isMe ? store.nickname : (other?.nickname ?? "載入中")
    }
    private var shownLevel: MemberLevel {
        isMe ? store.level : (other?.level ?? .silver)
    }
    private var shownTitles: [String] {
        isMe ? store.myTitles : (other?.titles ?? [])
    }
    private var shownAvatar: String? {
        isMe ? store.avatarImage.map { _ in "__local__" } : other?.avatar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // v47：整頁改成「單一」LazyVStack。
                // 原本是 VStack 裡再套 LazyVStack：外層 VStack 為了排版必須先問出
                // LazyVStack 的總高度，這一問就把所有動態卡片（連圖片、光暈、陰影）
                // 一次全建出來 —— 所謂懶載入等於沒生效。動態一多，進頁面就卡、
                // 滾起來每一幀都在合成全部卡片，非常卡。
                // 現在頭像、稱號、發佈列都當成這個 LazyVStack 的前幾項，
                // 滾出畫面的卡片才會真的被回收、被釋放。
                LazyVStack(spacing: 10) {
                    header.padding(.bottom, 6)
                    if !shownTitles.isEmpty { titleBox.padding(.bottom, 6) }
                    if isMe { composeBar.padding(.bottom, 6) }
                    feedTitle
                    if posts.isEmpty && !loading { feedEmpty }
                    ForEach(posts) { p in
                        PostCard(post: p, showAuthor: false,
                                 onDelete: isMe ? { Task { await remove(p) } } : nil,
                                 social: social[p.id] ?? PostSocial(),
                                 canInteract: store.authUserID != nil,
                                 myUserID: store.authUserID,
                                 onToggleLike: { Task { await toggleLike(p) } },
                                 onSendComment: { text in Task { await addComment(p, text) } },
                                 onDeleteComment: { c in Task { await removeComment(c, of: p.id) } })
                        .frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 16)
            }
            .background(Backdrop())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        Button { showLevelInfo = true } label: {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        if isMe {
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $showLevelInfo) {
                LevelInfoView()
            }
            .sheet(isPresented: $showComposer) {
                ComposerView { await reload() }
            }
            .sheet(isPresented: $showTitleEditor) {
                TitleLayoutEditor(owned: shownTitles, layout: titleLayout)
            }
            .task(id: tabActive) {
                // 只有這一頁真的顯示時才去拉資料，避免三頁同時開機搶頻寬。
                // v47：切回主頁不再每次都整頁重拉。原本每切回來一次就重新抓全部動態 +
                // 社交資料，資料一回來整頁重建一次，正好撞在手指剛要滑的那一下 = 卡。
                // 現在一分鐘內切來切去沿用現有資料，超過一分鐘才刷新。
                guard tabActive else { return }
                guard Date().timeIntervalSince(lastLoad) > 60 else { return }
                lastLoad = Date()
                await reload()
            }
            .onChange(of: titleLayout.order) { _ in scheduleLayoutPush() }
            .onChange(of: titleLayout.hidden) { _ in scheduleLayoutPush() }
            .onReceive(ticker) { _ in
                guard isMe, tabActive else { return }
                Task { await store.refreshSocial() }
            }
        }
    }

    // MARK: 頭部

    private var header: some View {
        VStack(spacing: 8) {
            Group {
                if isMe, let img = store.avatarImage {
                    ZStack {
                        if shownLevel.glow.hasGlow {
                            Circle()
                                .fill(RadialGradient(
                                    colors: [shownLevel.glow.haloColor.opacity(0.55), .clear],
                                    center: .center, startRadius: 0, endRadius: 104))
                                .frame(width: 208, height: 208)
                        }
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                        Circle()
                            .strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.55),
                                                        Color.white.opacity(0.12)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2)
                            .frame(width: 96, height: 96)

                        AvatarFrameLayer(raw: store.myFrame, avatar: 96)
                    }
                    .frame(width: Frames.find(store.myFrame ?? "") == nil
                           ? 96 : 96 / Frames.avatarRatio,
                           height: Frames.find(store.myFrame ?? "") == nil
                           ? 96 : 96 / Frames.avatarRatio)
                } else {
                    AvatarBubble(profileID: pid, file: isMe ? nil : other?.avatar,
                                 size: 96, ring: shownLevel,
                                 frame: isMe ? store.myFrame
                                             : Frames.equipped(in: other?.titles ?? [])?.storeKey)
                }
            }
            .padding(.top, 14)

            Text(shownName)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)

            if isMe {
                Text("@\(store.account)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.4))
            }

            MemberPill(level: shownLevel)
                .padding(.top, 2)
        }
    }

    private var titleBox: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("稱號")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.6)
                Spacer()
                if isMe {
                    Button { showTitleEditor = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10, weight: .bold))
                            Text("編排")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(TT.mint.opacity(0.9))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(Color.white.opacity(0.055))
                        )
                        .overlay(
                            Capsule().strokeBorder(TT.mint.opacity(0.22), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            TitleFlow(owned: visibleTitles, size: 1.0, spacing: 9, animated: false)

            if let f = Frames.equipped(in: shownTitles) {
                HStack(spacing: 7) {
                    Image(f.image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text(f.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("頭框")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TT.mint.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(TT.mint.opacity(0.12)))
                    Spacer(minLength: 0)
                }
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 2)
    }

    private var visibleTitles: [String] {
        // 頭框跟稱號共用一張表（frame. 開頭），排版時要濾掉，不然會混進編排清單
        let titles = shownTitles.filter { !$0.hasPrefix(Frames.prefix) }
        if isMe { return titleLayout.visible(titles) }
        // 別人的主頁：照對方自己排的順序，並濾掉他選擇不顯示的
        return TitleLayoutStore.arrange(owned: titles,
                                        order: other?.titleOrder ?? [],
                                        hidden: other?.titleHidden ?? [])
    }

    private var composeBar: some View {
        Button { showComposer = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TT.mint)
                Text("發佈動態")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(TT.mint.opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var feedTitle: some View {
        HStack {
            Text("動態")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.6)
            Spacer()
            if loading { ProgressView().tint(.white.opacity(0.3)).scaleEffect(0.7) }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    private var feedEmpty: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.16))
            Text(isMe ? "還沒有動態，發一則吧" : "這位用戶還沒有動態")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: 資料

    private func reload() async {
        // v47：只有第一次（還沒有資料）才顯示轉圈，之後靜默刷新，
        // 避免每次刷新都讓整頁進一次「載入中」再重建。
        await MainActor.run { if posts.isEmpty { loading = true } }
        if isMe {
            await store.refreshSocial()
            let uid = store.authUserID ?? ""
            let token = store.authToken
            await syncTitleLayout()
            let list = await SocialAPI.loadUserPosts(userID: uid, token: token)
            let smap = await SocialAPI.loadSocial(postIDs: list.map { $0.id },
                                                  myUserID: store.authUserID, token: token)
            await MainActor.run {
                // v47：內容沒變就不要動 @State。原本無條件覆蓋，等於每次刷新都把
                // 全部動態卡片重算一遍（圖片、留言區、光暈全跟著重建），滑到一半撞上就頓一下。
                if posts != list { posts = list }
                if social != smap { social = smap }
                loading = false
            }
        } else {
            let token = store.authToken
            let u = await SocialAPI.loadPublicUser(profileID: pid, token: token)
            let list = await SocialAPI.loadUserPosts(userID: u?.userID ?? guestProfile, token: token)
            let smap = await SocialAPI.loadSocial(postIDs: list.map { $0.id },
                                                  myUserID: store.authUserID, token: token)
            await MainActor.run {
                if other != u { other = u }
                if posts != list { posts = list }
                if social != smap { social = smap }
                loading = false
            }
        }
    }

    /// 本機編排 ⇄ 雲端：本機有設定就以本機為準推上去，本機是空的就拉雲端的下來
    private func syncTitleLayout() async {
        guard isMe, let uid = store.authUserID else { return }
        let token = store.authToken
        let remote = await SocialAPI.loadTitleLayout(userID: uid, token: token)

        if let remote {
            await MainActor.run { layoutRecordID = remote.id }
            // 本機還沒排過（新裝或換機）→ 直接套用雲端那份
            if titleLayout.isEmpty {
                await MainActor.run {
                    titleLayout.apply(order: remote.order, hidden: remote.hidden)
                }
                return
            }
            // 兩邊一樣就不用動
            if remote.order == titleLayout.order, remote.hidden == titleLayout.hidden { return }
        }
        // 本機有設定就以本機為準，推上去
        await pushTitleLayout()
    }

    private func pushTitleLayout() async {
        guard isMe, let uid = store.authUserID else { return }
        let id = await SocialAPI.saveTitleLayout(userID: uid,
                                                 recordID: layoutRecordID,
                                                 order: titleLayout.order,
                                                 hidden: titleLayout.hidden,
                                                 token: store.authToken)
        if let id { await MainActor.run { layoutRecordID = id } }
    }

    /// 改一次順序不要每個拖動幀都上傳，停手約一秒再送
    private func scheduleLayoutPush() {
        guard isMe else { return }
        layoutPushTask?.cancel()
        layoutPushTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if Task.isCancelled { return }
            await pushTitleLayout()
        }
    }

    private func remove(_ p: FeedPost) async {
        await SocialAPI.deletePost(id: p.id, token: store.authToken)
        await MainActor.run {
            posts.removeAll { $0.id == p.id }
            social[p.id] = nil
        }
    }

    // MARK: 愛心 / 留言

    private func toggleLike(_ p: FeedPost) async {
        guard let uid = store.authUserID, let token = store.authToken else { return }
        var s = social[p.id] ?? PostSocial()
        let wasLiked = s.likedByMe
        let oldLikeID = s.myLikeID

        // 先本機反應，手感不用等網路
        s.likedByMe = !wasLiked
        s.likes = max(0, s.likes + (wasLiked ? -1 : 1))
        let optimistic = s
        await MainActor.run { social[p.id] = optimistic }

        if wasLiked {
            if let id = oldLikeID { await SocialAPI.removeSocial(id: id, token: token) }
            await MainActor.run { social[p.id]?.myLikeID = nil }
        } else {
            let id = await SocialAPI.addLike(postID: p.id, userID: uid, token: token)
            await MainActor.run {
                if let id {
                    social[p.id]?.myLikeID = id
                } else {
                    // 沒寫成功就退回原樣，不要騙人
                    var back = social[p.id] ?? PostSocial()
                    back.likedByMe = false
                    back.likes = max(0, back.likes - 1)
                    social[p.id] = back
                }
            }
        }
    }

    private func addComment(_ p: FeedPost, _ text: String) async {
        guard let uid = store.authUserID, let token = store.authToken else { return }
        let tempID = "tmp-\(UUID().uuidString)"
        let temp = PostComment(id: tempID, userID: uid,
                               profileID: store.profileID ?? "",
                               nickname: store.nickname,
                               avatar: nil,
                               level: store.level,
                               text: text, created: Date())
        await MainActor.run {
            var s = social[p.id] ?? PostSocial()
            s.comments.append(temp)
            social[p.id] = s
        }

        let id = await SocialAPI.addComment(postID: p.id, userID: uid, text: text, token: token)
        await MainActor.run {
            guard var s = social[p.id] else { return }
            if let id {
                if let i = s.comments.firstIndex(where: { $0.id == tempID }) {
                    s.comments[i] = PostComment(id: id, userID: temp.userID,
                                                profileID: temp.profileID,
                                                nickname: temp.nickname, avatar: temp.avatar,
                                                level: temp.level, text: temp.text,
                                                created: temp.created)
                }
            } else {
                s.comments.removeAll { $0.id == tempID }
            }
            social[p.id] = s
        }
    }

    private func removeComment(_ c: PostComment, of postID: String) async {
        await SocialAPI.removeSocial(id: c.id, token: store.authToken)
        await MainActor.run {
            social[postID]?.comments.removeAll { $0.id == c.id }
        }
    }
}
