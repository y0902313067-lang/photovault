import SwiftUI

// MARK: - 任務定義

struct TaskDef: Identifiable, Equatable {
    let key: String
    let titleKey: String
    let name: String
    let goal: Double
    let unit: String
    let icon: String
    let how: String

    var id: String { key }

    static let all: [TaskDef] = [
        TaskDef(key: "speed", titleKey: "speed", name: "測速達人", goal: 10, unit: "個路段",
                icon: "speedometer", how: "累積經過 10 個限速路段"),
        TaskDef(key: "diag", titleKey: "diag", name: "診斷專家", goal: 1, unit: "次",
                icon: "waveform.path.ecg", how: "完成一次網路診斷"),
        TaskDef(key: "pw", titleKey: "pw", name: "安全密碼", goal: 81, unit: "分",
                icon: "lock.shield", how: "輸入一組 81 分的密碼"),
        TaskDef(key: "walk", titleKey: "walk", name: "健走達人", goal: 10, unit: "公里",
                icon: "figure.walk", how: "累積步行 10 公里"),
        TaskDef(key: "db", titleKey: "db", name: "獅吼功", goal: 100, unit: "分貝",
                icon: "speaker.wave.3", how: "使用分貝計測到 100 分貝以上"),
        TaskDef(key: "fx", titleKey: "fx", name: "外交官", goal: 3, unit: "次",
                icon: "dollarsign.circle", how: "查看即時匯率 3 次"),

        TaskDef(key: "netdoc", titleKey: "netdoc", name: "資訊老師", goal: 1, unit: "次",
                icon: "globe", how: "打開網域資訊工具一次"),
        TaskDef(key: "north", titleKey: "north", name: "漂向北方", goal: 1, unit: "次",
                icon: "location.north.line", how: "用指南針指著北方一次"),
        TaskDef(key: "gearhead", titleKey: "gearhead", name: "裝備組的", goal: 1, unit: "次",
                icon: "cpu", how: "點開裝置資訊一次"),
        TaskDef(key: "shake67", titleKey: "shake67", name: "6767", goal: 67, unit: "次",
                icon: "gyroscope", how: "用重力感測晃動 67 次"),
        TaskDef(key: "mathprof", titleKey: "mathprof", name: "數學老師", goal: 1, unit: "次",
                icon: "function", how: "點開單位換算一次"),
        TaskDef(key: "qrartist", titleKey: "qrartist", name: "QR藝術家", goal: 1, unit: "個",
                icon: "qrcode", how: "用 QR 工作室做出一個二維碼"),
        TaskDef(key: "diceluck", titleKey: "diceluck", name: "愛拼才會贏", goal: 1, unit: "次",
                icon: "die.face.5", how: "用隨機決策的骰子擲一次"),
        TaskDef(key: "tophat", titleKey: "tophat", name: "高利戴帽子", goal: 1, unit: "次",
                icon: "percent", how: "用貸款試算算一次"),
        TaskDef(key: "nicejob", titleKey: "nicejob", name: "好棒棒餒", goal: 1, unit: "篇",
                icon: "hand.thumbsup", how: "發一篇動態"),
        TaskDef(key: "socialking", titleKey: "socialking", name: "超級社牛", goal: 1, unit: "次",
                icon: "bubble.left.and.bubble.right", how: "在聊天室發一次言")
    ]
}

// MARK: - 任務清單

struct TasksView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var progress: [String: (Double, Bool)] = [:]
    @State private var loading = true
    @State private var claiming: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    header

                    ForEach(TaskDef.all) { t in
                        taskRow(t)
                    }

                    Text("完成條件後按領取，稱號會直接掛到你的主頁。已經有的稱號不會重複發。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.28))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Backdrop())
            .navigationTitle("任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .task { await load() }
        }
    }

    private var ownedTaskTitles: Int {
        let keys = Set(TaskDef.all.map { $0.titleKey })
        return store.myTitles.filter { keys.contains($0) }.count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TT.mint)
                Text("完成任務拿稱號")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Text("已擁有 \(ownedTaskTitles) / \(TaskDef.all.count) 個任務稱號")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .padding(.top, 6)
    }

    private func taskRow(_ t: TaskDef) -> some View {
        let (value, claimed) = progress[t.key] ?? (0, false)
        let owned = store.myTitles.contains(t.titleKey) || store.isTaskClaimedLocally(t.key)
        let done = value >= t.goal
        let pct = min(1.0, t.goal <= 0 ? 1 : value / t.goal)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(done ? TT.mint.opacity(0.14) : Color.white.opacity(0.05))
                Image(systemName: t.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(done ? TT.mint : .white.opacity(0.4))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(t.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    if owned, let def = Titles.find(t.titleKey) {
                        TitleChip(title: def, size: 0.6, animated: false)
                    }
                }
                Text(t.how)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.32))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(done ? TT.mint : TT.blue.opacity(0.7))
                            .frame(width: max(4, geo.size.width * pct))
                    }
                }
                .frame(height: 4)

                Text("\(fmt(value)) / \(fmt(t.goal)) \(t.unit)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if owned {
                Text("已領取")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 56)
            } else if done {
                Button {
                    claim(t)
                } label: {
                    ZStack {
                        Capsule().fill(TT.mint)
                        if claiming == t.key {
                            ProgressView().tint(Color(red: 0.03, green: 0.09, blue: 0.08))
                                .scaleEffect(0.75)
                        } else {
                            Text("領取")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                        }
                    }
                    .frame(width: 56, height: 28)
                }
                .buttonStyle(.plain)
            } else {
                Text("未完成")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(width: 56)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(owned ? TT.mint.opacity(0.16) : Color.white.opacity(0.06),
                              lineWidth: 0.8)
        )
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func load() async {
        guard let uid = store.authUserID else { return }
        var out: [String: (Double, Bool)] = [:]
        for t in TaskDef.all {
            let r = await SocialAPI.taskValue(userID: uid, key: t.key, token: store.authToken)
            out[t.key] = (r.value, r.claimed)
        }
        await MainActor.run {
            progress = out
            loading = false
        }
    }

    private func claim(_ t: TaskDef) {
        guard claiming == nil else { return }
        claiming = t.key
        Task {
            await store.claimTask(t)
            await MainActor.run {
                claiming = nil
                progress[t.key] = ((progress[t.key]?.0 ?? t.goal), true)
            }
        }
    }
}

// MARK: - 會員分級說明

struct LevelInfoView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(MemberLevel.allCases.reversed()) { lv in
                        HStack(spacing: 13) {
                            MemberBadge(level: lv, size: 44, animated: false)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(lv.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.94))
                                    if lv == store.level {
                                        Text("目前")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(TT.mint))
                                    }
                                }
                                Text(lv.rule)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(lv == store.level ? TT.mint.opacity(0.07)
                                                        : Color.white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(lv == store.level ? TT.mint.opacity(0.25)
                                                                : Color.white.opacity(0.05),
                                              lineWidth: 0.8)
                        )
                    }

                    Text("等級由官方贈與，或透過兌換碼取得。兌換碼在「設定 → 兌換碼」輸入。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.28))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Backdrop())
            .navigationTitle("會員分級")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - 恭喜獲得

struct RewardPopup: View {
    let title: TitleDef?
    let level: MemberLevel?
    var frame: FrameDef? = nil
    var onClose: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 16) {
                Text("恭喜獲得")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 22)

                if let title {
                    TitleChip(title: title, size: 1.7)
                        .padding(.vertical, 10)
                    Text(title.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                } else if let frame {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.32),
                                                          Color(red: 0.09, green: 0.12, blue: 0.18)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 96, height: 96)
                        AvatarFrameLayer(raw: frame.storeKey, avatar: 96)
                    }
                    .padding(.vertical, 6)
                    Text(frame.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                } else if let level {
                    MemberBadge(level: level, size: 96)
                    Text(level.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                }

                Button { close() } label: {
                    Text("確定")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(TT.mint))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 26)
                .padding(.bottom, 22)
            }
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.09, blue: 0.125))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
            .scaleEffect(appear ? 1 : 0.88)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { appear = true }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { appear = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { onClose() }
    }
}
