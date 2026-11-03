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
        }
        .frame(width: size, height: size)
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

struct PostCard: View {
    let post: FeedPost
    var showAuthor: Bool = true
    var onAvatarTap: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showAuthor {
                HStack(spacing: 9) {
                    Button {
                        onAvatarTap?(post.profileID)
                    } label: {
                        AvatarBubble(profileID: post.profileID, file: post.avatar,
                                     size: 38, ring: post.level)
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
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Label("刪除這則動態", systemImage: "trash")
                }
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color.white.opacity(0.05)
                            ProgressView().tint(.white.opacity(0.4))
                        }
                    }
                }
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
    @State private var other: PublicUser?
    @State private var loading = true
    @State private var guestProfile = ""
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
                VStack(spacing: 16) {
                    header
                    if !shownTitles.isEmpty { titleBox }
                    if isMe { composeBar }
                    feedSection
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
            .task { await reload() }
            .onChange(of: titleLayout.order) { _ in scheduleLayoutPush() }
            .onChange(of: titleLayout.hidden) { _ in scheduleLayoutPush() }
            .onReceive(ticker) { _ in
                guard isMe else { return }
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
                    }
                    .frame(width: 96, height: 96)
                } else {
                    AvatarBubble(profileID: pid, file: isMe ? nil : other?.avatar,
                                 size: 96, ring: shownLevel)
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
            TitleFlow(owned: visibleTitles, size: 1.0, spacing: 9)
        }
        .padding(.horizontal, 2)
    }

    private var visibleTitles: [String] {
        if isMe { return titleLayout.visible(shownTitles) }
        // 別人的主頁：照對方自己排的順序，並濾掉他選擇不顯示的
        return TitleLayoutStore.arrange(owned: shownTitles,
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

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            if posts.isEmpty && !loading {
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

            ForEach(posts) { p in
                PostCard(post: p, showAuthor: false,
                         onDelete: isMe ? { Task { await remove(p) } } : nil)
            }
        }
    }

    // MARK: 資料

    private func reload() async {
        await MainActor.run { loading = true }
        if isMe {
            await store.refreshSocial()
            let uid = store.authUserID ?? ""
            let token = store.authToken
            await syncTitleLayout()
            let list = await SocialAPI.loadUserPosts(userID: uid, token: token)
            await MainActor.run {
                posts = list
                loading = false
            }
        } else {
            let token = store.authToken
            let u = await SocialAPI.loadPublicUser(profileID: pid, token: token)
            let list = await SocialAPI.loadUserPosts(userID: u?.userID ?? guestProfile, token: token)
            await MainActor.run {
                other = u
                posts = list
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
        await MainActor.run { posts.removeAll { $0.id == p.id } }
    }
}
