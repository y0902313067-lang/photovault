import SwiftUI
import UIKit

// MARK: - 常用工具儲存

final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    private let key = "md.favoriteTools"
    private let maxCount = 10

    @Published private(set) var tools: [ToolRoute] = []

    private init() {
        if let raw = UserDefaults.standard.stringArray(forKey: key) {
            tools = raw.compactMap { ToolRoute(rawValue: $0) }
        }
    }

    var isFull: Bool { tools.count >= maxCount }
    var limit: Int { maxCount }

    func contains(_ tool: ToolRoute) -> Bool { tools.contains(tool) }

    func toggle(_ tool: ToolRoute) {
        if let index = tools.firstIndex(of: tool) {
            tools.remove(at: index)
        } else {
            guard !isFull else { return }
            tools.append(tool)
        }
        persist()
    }

    func remove(_ tool: ToolRoute) {
        tools.removeAll { $0 == tool }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(tools.map { $0.rawValue }, forKey: key)
    }
}

// MARK: - 常用工具區塊（首頁頂部）

struct FavoriteSection: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var showPicker = false
    let onOpen: (ToolRoute) -> Void

    private let columns = [GridItem(.flexible(), spacing: 11),
                           GridItem(.flexible(), spacing: 11)]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(TT.mint)
                    .frame(width: 3, height: 13)
                    .shadow(color: TT.mint.opacity(0.7), radius: 5)
                Text("常用工具")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("FAVORITES")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.2))
                Rectangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.09),
                                                  Color.white.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            }

            LazyVGrid(columns: columns, spacing: 11) {
                ForEach(favorites.tools) { tool in
                    FavoriteCard(tool: tool,
                                 onOpen: { onOpen(tool) },
                                 onRemove: { favorites.remove(tool) })
                }

                AddFavoriteCard(isEmptyState: favorites.tools.isEmpty,
                                isFull: favorites.isFull,
                                count: favorites.tools.count,
                                limit: favorites.limit) {
                    showPicker = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

            if favorites.tools.isEmpty {
                Text("點「＋」把常用的功能放上來，之後一眼就能打開")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.26))
                    .padding(.leading, 3)
            }
        }
        .sheet(isPresented: $showPicker) {
            FavoritePickerView()
        }
    }
}

// MARK: - 常用工具卡片（可長按移除）

private struct FavoriteCard: View {
    let tool: ToolRoute
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var confirmRemove = false

    var body: some View {
        Button {
            onOpen()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("從常用工具移除", systemImage: "minus.circle")
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(colors: [tool.accent.opacity(0.9),
                                                    tool.accent.opacity(0.45)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: tool.accent.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: tool.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TT.ink)
                }
                Spacer(minLength: 0)
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(TT.mint.opacity(0.5))
                    .padding(.top, 3)
            }

            Spacer(minLength: 10)

            Text(tool.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tool.subtitle)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.22))
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(13)
        .frame(height: 112)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TT.mint.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [TT.mint.opacity(0.4),
                                            TT.teal.opacity(0.2)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
    }
}

// MARK: - 加號框

private struct AddFavoriteCard: View {
    let isEmptyState: Bool
    let isFull: Bool
    let count: Int
    let limit: Int
    let action: () -> Void

    private var tint: Color { isFull ? TT.amber : TT.mint }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.025))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                    )
                    .foregroundStyle(tint.opacity(0.32))

                VStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: isFull ? "slider.horizontal.3" : "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(isFull ? "已滿 \(count)/\(limit) · 調整" : "加入常用工具")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(isFull ? 0.5 : 0.4))
                }
            }
            .frame(height: 112)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 選擇器

struct FavoritePickerView: View {
    @ObservedObject private var favorites = FavoritesStore.shared
    @Environment(\.dismiss) private var dismiss

    /// 選擇器吃的是完整目錄，之後新增工具不必再回來補這份清單
    private let groups: [ToolGroup] = ToolCatalog.allGroups

    @State private var fullHint = false

    var body: some View {
        ZStack {
            Backdrop()
            TechGrid()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        hint
                        if !favorites.tools.isEmpty {
                            selectedStrip
                        }
                        ForEach(groups) { group in
                            groupBlock(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("加入常用工具")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("已選 \(favorites.tools.count) / \(favorites.limit)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TT.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(LinearGradient(colors: [TT.mint, TT.teal],
                                                     startPoint: .leading,
                                                     endPoint: .trailing))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var hint: some View {
        HStack(spacing: 7) {
            Image(systemName: fullHint ? "exclamationmark.circle" : "hand.tap")
                .font(.system(size: 10))
            Text(hintText)
                .font(.system(size: 10.5, weight: fullHint ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(fullHint ? TT.amber.opacity(0.95) : Color.white.opacity(0.28))
        .animation(.easeInOut(duration: 0.2), value: fullHint)
    }

    private var hintText: String {
        if fullHint || favorites.isFull {
            return "已選滿 \(favorites.limit) 個 —— 先在上方點掉一個，就能換新的"
        }
        return "點一下加入，再點一下移除；最多 \(favorites.limit) 個"
    }

    // MARK: 已選區（點一下直接移除，滿額時就是用來換的）

    private var selectedStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("已選 \(favorites.tools.count) / \(favorites.limit)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(favorites.isFull ? TT.amber : TT.mint)
                Spacer(minLength: 0)
                Text("點一下移除")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.24))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(favorites.tools) { tool in
                        Button {
                            favorites.remove(tool)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(tool.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .opacity(0.55)
                            }
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(tool.accent.opacity(0.16)))
                            .overlay(Capsule().strokeBorder(tool.accent.opacity(0.35),
                                                            lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func groupBlock(_ group: ToolGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(group.accent)
                    .frame(width: 3, height: 12)
                Text(group.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(group.en)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.18))
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(group.tools.enumerated()), id: \.element.id) { index, tool in
                    row(tool)
                    if index < group.tools.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                            .padding(.leading, 46)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func row(_ tool: ToolRoute) -> some View {
        let selected = favorites.contains(tool)
        let locked = !selected && favorites.isFull

        return Button {
            guard !locked else {
                // 以前這裡是靜默 disabled，按了完全沒反應，看起來像壞掉
                withAnimation(.easeInOut(duration: 0.18)) { fullHint = true }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                Task {
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) { fullHint = false }
                }
                return
            }
            favorites.toggle(tool)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tool.accent.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: tool.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tool.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white.opacity(locked ? 0.42 : 0.9))
                    Text(tool.subtitle)
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(locked ? 0.14 : 0.2))
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(selected ? TT.mint : Color.white.opacity(0.05))
                        .frame(width: 22, height: 22)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TT.ink)
                    } else if locked {
                        Image(systemName: "lock")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
