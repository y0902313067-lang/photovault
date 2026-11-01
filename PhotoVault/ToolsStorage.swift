import SwiftUI

// MARK: - 資料模型

struct StorageBigFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let folder: String
    let size: Int64
    let modified: Date?
    let canDelete: Bool
}

struct StorageSnapshot: Equatable {
    var total: Int64 = 0
    var free: Int64 = 0
    var documents: Int64 = 0
    var caches: Int64 = 0
    var temp: Int64 = 0
    var library: Int64 = 0
    var bigFiles: [StorageBigFile] = []

    var usedBySystem: Int64 { max(0, total - free) }
    var usedRatio: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }
    var appTotal: Int64 { documents + caches + temp + library }
}

// MARK: - 主頁

struct StorageAnalyzerView: View {
    @State private var snapshot: StorageSnapshot?
    @State private var scanning = true
    @State private var cleaning = false
    @State private var message: String?
    @State private var showDeleteConfirm = false
    @State private var selected: Set<String> = []

    var body: some View {
        TTScreen(title: "儲存空間",
                 subtitle: "STORAGE ANALYZER",
                 accent: TT.teal) {
            if scanning && snapshot == nil {
                scanningCard
            } else if let snapshot {
                capacityCard(snapshot)
                breakdownCard(snapshot)
                cleanCard
                bigFileCard(snapshot)
                if let message {
                    noteCard(message)
                }
                limitsCard
            } else {
                scanningCard
            }
        }
        .task {
            await refresh()
        }
        .confirmationDialog("確定刪除選取的檔案？",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("刪除 \(selected.count) 個檔案", role: .destructive) {
                deleteSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("刪除後無法復原。")
        }
    }

    // MARK: 掃描中

    private var scanningCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(TT.mint)
                .scaleEffect(1.1)
            Text("正在統計本機資料…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    // MARK: 容量

    private func capacityCard(_ snap: StorageSnapshot) -> some View {
        VStack(spacing: 16) {
            ZStack {
                TTRing(progress: snap.usedRatio,
                       accent: snap.usedRatio > 0.9 ? TT.rose : TT.mint,
                       lineWidth: 12)
                    .frame(width: 150, height: 150)

                VStack(spacing: 3) {
                    Text(percentText(snap.usedRatio))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("已使用")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .padding(.top, 6)

            HStack(spacing: 0) {
                statCell("剩餘", bytes(snap.free), TT.mint)
                divider
                statCell("已用", bytes(snap.usedBySystem), TT.amber)
                divider
                statCell("總容量", bytes(snap.total), TT.blue)
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )

            HStack(spacing: 6) {
                Image(systemName: snap.free < 2_000_000_000
                      ? "exclamationmark.triangle" : "checkmark.seal")
                    .font(.system(size: 10))
                Text(snap.free < 2_000_000_000
                     ? "剩餘空間不到 2GB，建議清一下快取"
                     : "空間充足，暫時不需要清理")
                    .font(.system(size: 10.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(snap.free < 2_000_000_000
                             ? TT.amber.opacity(0.85) : TT.mint.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(colors: [TT.teal.opacity(0.09),
                                            Color.white.opacity(0.03)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [TT.teal.opacity(0.3),
                                            Color.white.opacity(0.05)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 26)
    }

    private func statCell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 本 App 佔用

    private func breakdownCard(_ snap: StorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("本 App 資料")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 0)
                Text(bytes(snap.appTotal))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(TT.mint)
            }

            usageBar(snap)

            VStack(spacing: 9) {
                legendRow("檔案與文件", bytes(snap.documents), TT.blue, snap.documents)
                legendRow("快取", bytes(snap.caches), TT.mint, snap.caches)
                legendRow("暫存", bytes(snap.temp), TT.violet, snap.temp)
                legendRow("其他資料", bytes(snap.library), TT.amber, snap.library)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func usageBar(_ snap: StorageSnapshot) -> some View {
        GeometryReader { geo in
            let total = max(snap.appTotal, 1)
            HStack(spacing: 2) {
                segment(Double(snap.documents) / Double(total), TT.blue, geo.size.width)
                segment(Double(snap.caches) / Double(total), TT.mint, geo.size.width)
                segment(Double(snap.temp) / Double(total), TT.violet, geo.size.width)
                segment(Double(snap.library) / Double(total), TT.amber, geo.size.width)
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }

    private func segment(_ ratio: Double, _ color: Color, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(color.opacity(0.85))
            .frame(width: max(0, width * CGFloat(ratio)))
    }

    private func legendRow(_ title: String, _ value: String, _ color: Color, _ raw: Int64) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
            Text(raw > 0 ? value : "—")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: 清理

    private var cleanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("一鍵清理")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Button {
                cleanAll()
            } label: {
                HStack(spacing: 8) {
                    if cleaning {
                        ProgressView()
                            .tint(TT.ink)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(cleaning ? "清理中…" : "清除快取與暫存")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(TT.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [TT.mint, TT.teal],
                                             startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: TT.mint.opacity(0.22), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(cleaning)

            Text("只會清除縮圖、下載暫存與網路快取，帳號、設定與相簿備份紀錄都不會動到。")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.24))
                .lineSpacing(2)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TT.mint.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: 大檔

    private func bigFileCard(_ snap: StorageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("大檔案")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("\(snap.bigFiles.count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(TT.mint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TT.mint.opacity(0.14)))
                Spacer(minLength: 0)
                if !selected.isEmpty {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Text("刪除 \(selected.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TT.rose)
                    }
                    .buttonStyle(.plain)
                }
            }

            if snap.bigFiles.isEmpty {
                TTEmptyHint(icon: "externaldrive", text: "沒有超過 1MB 的檔案")
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snap.bigFiles.enumerated()), id: \.element.id) { index, file in
                        bigFileRow(file)
                        if index < snap.bigFiles.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 1)
                                .padding(.leading, 34)
                        }
                    }
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func bigFileRow(_ file: StorageBigFile) -> some View {
        Button {
            guard file.canDelete else { return }
            if selected.contains(file.id) {
                selected.remove(file.id)
            } else {
                selected.insert(file.id)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TT.blue.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: iconFor(file.name))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(file.canDelete ? TT.blue : Color.white.opacity(0.25))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(file.canDelete ? 0.86 : 0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.canDelete ? file.folder : "\(file.folder) · 系統資料，保留")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.22))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(bytes(file.size))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))

                if file.canDelete {
                    ZStack {
                        Circle()
                            .fill(selected.contains(file.id) ? TT.mint : Color.white.opacity(0.05))
                            .frame(width: 19, height: 19)
                        if selected.contains(file.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(TT.ink)
                        }
                    }
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!file.canDelete)
    }

    private func iconFor(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp": return "photo"
        case "mp4", "mov", "m4v": return "film"
        case "mp3", "m4a", "wav", "caf": return "waveform"
        case "zip", "tar", "gz": return "archivebox"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    // MARK: 說明

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("這個頁面看得到什麼")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.42))

            Text("容量數字來自系統回報的整機空間；檔案明細只涵蓋本 App 自己的資料夾。iOS 不允許任何 App 掃描其他 App 的檔案，所以你看不到、也清不到別人的空間——市面上說能「一鍵清理手機」的 App 其實都做不到這件事。")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.24))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    private func noteCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(TT.mint)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(TT.mint.opacity(0.07))
        )
    }

    // MARK: 掃描

    private func refresh() async {
        let snap = await Task.detached(priority: .userInitiated) {
            StorageScanner.scan()
        }.value
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.3)) {
                snapshot = snap
                scanning = false
            }
        }
    }

    private func cleanAll() {
        cleaning = true
        Task {
            let freed = await Task.detached(priority: .userInitiated) {
                StorageScanner.clean()
            }.value
            await refresh()
            await MainActor.run {
                cleaning = false
                message = "已清出 \(bytes(freed))\(freed == 0 ? "（本來就很乾淨）" : "")"
            }
        }
    }

    private func deleteSelected() {
        let targets = (snapshot?.bigFiles ?? []).filter { selected.contains($0.id) }
        Task {
            var freed: Int64 = 0
            for file in targets {
                try? FileManager.default.removeItem(at: file.url)
                freed += file.size
            }
            await refresh()
            await MainActor.run {
                selected.removeAll()
                message = "已刪除 \(targets.count) 個檔案，釋放 \(bytes(freed))"
            }
        }
    }

    // MARK: 格式化

    private func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, value))
    }

    private func percentText(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100)
    }
}

// MARK: - 掃描器

enum StorageScanner {
    static let bigThreshold: Int64 = 1_000_000

    static func scan() -> StorageSnapshot {
        var snap = StorageSnapshot()
        let fm = FileManager.default

        if let home = URL(string: "file://\(NSHomeDirectory())") {
            let values = try? home.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            if let total = values?.volumeTotalCapacity {
                snap.total = Int64(total)
            }
            if let available = values?.volumeAvailableCapacityForImportantUsage {
                snap.free = Int64(available)
            } else if let available = values?.volumeAvailableCapacity {
                snap.free = Int64(available)
            }
        }

        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let tmp = fm.temporaryDirectory

        snap.documents = folderSize(docs)
        snap.caches = folderSize(caches)
        snap.temp = folderSize(tmp)

        // Library 但要扣掉 Caches，避免重複計算
        let libTotal = folderSize(lib)
        snap.library = max(0, libTotal - snap.caches)

        var files: [StorageBigFile] = []
        let roots: [(URL?, String)] = [(docs, "文件"), (caches, "快取"), (tmp, "暫存")]
        for (root, label) in roots {
            guard let root else { continue }
            files.append(contentsOf: collect(root: root, label: label))
        }

        // 同一個檔案可能重複掃到，用路徑去重
        var seen = Set<String>()
        snap.bigFiles = files
            .filter { seen.insert($0.url.path).inserted }
            .sorted { $0.size > $1.size }

        return snap
    }

    /// 清理快取與暫存，回傳釋放的位元數
    static func clean() -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0

        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let tmp = fm.temporaryDirectory

        let dirs: [URL?] = [caches, tmp]
        for root in dirs.compactMap({ $0 }) {
            guard let items = try? fm.contentsOfDirectory(at: root,
                                                          includingPropertiesForKeys: [.fileSizeKey],
                                                          options: []) else { continue }
            for item in items {
                let size = folderSize(item)
                if (try? fm.removeItem(at: item)) != nil {
                    freed += size
                }
            }
        }

        URLCache.shared.removeAllCachedResponses()
        return freed
    }

    private static func collect(root: URL, label: String) -> [StorageBigFile] {
        let fm = FileManager.default
        var result: [StorageBigFile] = []
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.fileSizeKey,
                                                                          .isRegularFileKey,
                                                                          .contentModificationDateKey],
                                             options: [.skipsHiddenFiles]) else { return [] }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey,
                                                          .isRegularFileKey,
                                                          .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let size = values?.fileSize, Int64(size) >= bigThreshold else { continue }

            let name = url.lastPathComponent
            // 帳號頭像這類核心資料不列進可刪清單
            let protected = name.hasPrefix("pv_") || name == "pv_avatar.jpg"
            result.append(StorageBigFile(id: url.path,
                                         url: url,
                                         name: name,
                                         folder: label,
                                         size: Int64(size),
                                         modified: values?.contentModificationDate,
                                         canDelete: !protected))
        }
        return result
    }

    static func folderSize(_ url: URL?) -> Int64 {
        guard let url else { return 0 }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return Int64(size)
        }

        var total: Int64 = 0
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey,
                                                                          .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
