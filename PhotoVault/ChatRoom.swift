import SwiftUI
import PhotosUI

// MARK: - 聊天室（公開大廳）

struct ChatRoomView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var picked: PhotosPickerItem?
    @State private var attach: UIImage?
    @State private var sending = false
    @State private var tip: String?
    @State private var guest: String?
    @State private var loading = true
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(messages) { m in
                                messageRow(m)
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
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
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
                startPolling()
            }
            .onDisappear { timer?.invalidate(); timer = nil }
        }
    }

    struct GuestBox: Identifiable { let id: String }

    // MARK: 一則訊息

    private func messageRow(_ m: ChatMessage) -> some View {
        let mine = m.userID == (store.authUserID ?? "")
        return HStack(alignment: .top, spacing: 9) {
            if mine { Spacer(minLength: 40) }

            if !mine {
                Button { if !m.profileID.isEmpty { guest = m.profileID } } label: {
                    AvatarBubble(profileID: m.profileID, file: m.avatar, size: 38, ring: m.level)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(m.nickname)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    LevelTagInline(level: m.level)
                }
                .frame(maxWidth: mine ? .infinity : nil,
                       alignment: mine ? .trailing : .leading)

                if !m.text.isEmpty {
                    Text(m.text)
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
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let im):
                            im.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color.white.opacity(0.05)
                                ProgressView().tint(.white.opacity(0.35))
                            }
                        }
                    }
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text(shortTime(m.created))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.22))
            }

            if mine {
                AvatarBubble(profileID: store.profileID ?? "", file: nil,
                             size: 38, ring: store.level, localImage: store.avatarImage)
            }

            if !mine { Spacer(minLength: 40) }
        }
    }

    // MARK: 輸入區

    private var inputBar: some View {
        VStack(spacing: 8) {
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
                .disabled(sending || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attach == nil))
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

    private func load() async {
        let list = await SocialAPI.loadChat(token: store.authToken)
        await MainActor.run {
            messages = list
            loading = false
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
            Task { await load() }
        }
    }

    private func send() {
        guard !sending, let uid = store.authUserID else { return }
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        tip = nil
        Task {
            do {
                try await SocialAPI.sendChat(userID: uid, text: t, image: attach,
                                             token: store.authToken)
                await MainActor.run {
                    input = ""
                    attach = nil
                    sending = false
                }
                await load()
            } catch {
                await MainActor.run {
                    sending = false
                    tip = error.localizedDescription
                }
            }
        }
    }
}
