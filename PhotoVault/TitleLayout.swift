import SwiftUI

// MARK: - 稱號編排（自己決定順序、自己決定放哪些）

final class TitleLayoutStore: ObservableObject {
    private let orderKey = "pv.titles.order.v1"
    private let hiddenKey = "pv.titles.hidden.v1"

    @Published var order: [String] {
        didSet { UserDefaults.standard.set(order, forKey: orderKey) }
    }
    @Published var hidden: [String] {
        didSet { UserDefaults.standard.set(hidden, forKey: hiddenKey) }
    }

    init() {
        order = UserDefaults.standard.stringArray(forKey: "pv.titles.order.v1") ?? []
        hidden = UserDefaults.standard.stringArray(forKey: "pv.titles.hidden.v1") ?? []
    }

    func isHidden(_ key: String) -> Bool { hidden.contains(key) }

    /// 全部稱號（含被藏起來的），照自己的順序排
    func arranged(_ owned: [String]) -> [String] {
        let set = Set(owned)
        var out = order.filter { set.contains($0) }
        let known = Set(out)
        for k in owned where !known.contains(k) { out.append(k) }
        return out
    }

    /// 主頁上真正要顯示的
    func visible(_ owned: [String]) -> [String] {
        arranged(owned).filter { !hidden.contains($0) }
    }

    func toggle(_ key: String) {
        if let i = hidden.firstIndex(of: key) {
            hidden.remove(at: i)
        } else {
            hidden.append(key)
        }
    }

    func move(owned: [String], from: IndexSet, to: Int) {
        var list = arranged(owned)
        list.move(fromOffsets: from, toOffset: to)
        order = list
    }

    func reset() {
        order = []
        hidden = []
    }

    /// 套用雲端存下來的編排（換手機、或本機還沒有任何設定時）
    func apply(order newOrder: [String], hidden newHidden: [String]) {
        if order != newOrder { order = newOrder }
        if hidden != newHidden { hidden = newHidden }
    }

    /// 本機是否還沒有任何編排（首次使用）
    var isEmpty: Bool { order.isEmpty && hidden.isEmpty }

    /// 別人的主頁：照對方存下來的順序排，並濾掉他選擇不顯示的
    static func arrange(owned: [String], order: [String], hidden: [String]) -> [String] {
        let hiddenSet = Set(hidden)
        var out = order.filter { owned.contains($0) && !hiddenSet.contains($0) }
        let picked = Set(out)
        for k in owned where !picked.contains(k) && !hiddenSet.contains(k) { out.append(k) }
        return out
    }
}

// MARK: - 編排介面

struct TitleLayoutEditor: View {
    let owned: [String]
    @ObservedObject var layout: TitleLayoutStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.arranged(owned), id: \.self) { key in
                        if let t = Titles.find(key) {
                            HStack(spacing: 10) {
                                TitleChip(title: t, size: 0.86, animated: false)
                                    .opacity(layout.isHidden(key) ? 0.35 : 1)
                                Spacer(minLength: 6)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        layout.toggle(key)
                                    }
                                } label: {
                                    Image(systemName: layout.isHidden(key) ? "eye.slash" : "eye")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(layout.isHidden(key)
                                                         ? Color.white.opacity(0.3) : TT.mint)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.white.opacity(0.04))
                            .padding(.vertical, 2)
                        }
                    }
                    .onMove { from, to in
                        layout.move(owned: owned, from: from, to: to)
                    }
                } header: {
                    Text("按住右邊把手拖動排序，點眼睛決定要不要顯示")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.34))
                } footer: {
                    Button {
                        withAnimation { layout.reset() }
                    } label: {
                        Text("恢復預設順序")
                            .font(.system(size: 12.5))
                            .foregroundStyle(TT.rose.opacity(0.85))
                    }
                    .padding(.top, 6)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.06, blue: 0.085).ignoresSafeArea())
            .navigationTitle("稱號編排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(TT.mint)
                }
            }
        }
    }
}
