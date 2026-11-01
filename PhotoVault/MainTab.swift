import SwiftUI

// MARK: - 主容器（底部三欄）

struct MainTabView: View {
    @State private var tab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeView()
                .opacity(tab == 0 ? 1 : 0)
                .allowsHitTesting(tab == 0)

            MoreToolsView()
                .opacity(tab == 1 ? 1 : 0)
                .allowsHitTesting(tab == 1)

            ProfileView(embedded: true)
                .opacity(tab == 2 ? 1 : 0)
                .allowsHitTesting(tab == 2)

            MintTabBar(selection: $tab)
        }
    }
}

// MARK: - 底部導覽列

struct MintTabBar: View {
    @Binding var selection: Int

    private let items: [(icon: String, title: String)] = [
        ("square.grid.2x2.fill", "源隼工具箱"),
        ("square.stack.fill", "更多工具"),
        ("person.fill", "我的")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<items.count, id: \.self) { i in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.22)) { selection = i }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selection == i {
                                Capsule()
                                    .fill(LinearGradient(colors: [TT.mint.opacity(0.22),
                                                                  TT.blue.opacity(0.16)],
                                                         startPoint: .topLeading,
                                                         endPoint: .bottomTrailing))
                                    .frame(width: 52, height: 26)
                            }
                            Image(systemName: items[i].icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selection == i
                                                 ? TT.mint
                                                 : Color.white.opacity(0.38))
                                .shadow(color: selection == i ? TT.mint.opacity(0.6) : .clear,
                                        radius: 8)
                        }
                        .frame(height: 26)

                        Text(items[i].title)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(selection == i
                                             ? Color.white.opacity(0.95)
                                             : Color.white.opacity(0.34))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.16),
                                                    TT.mint.opacity(0.18),
                                                    Color.white.opacity(0.05)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }
}

// MARK: - 更多工具

struct MoreToolsView: View {
    @EnvironmentObject var store: AppStore
    @State private var route: ToolRoute?
    @State private var appeared = false

    private let groups: [ToolGroup] = [
        ToolGroup(name: "影像與媒體", en: "IMAGING & MEDIA", accent: TT.blue,
                  tools: [.ocr, .qrscan, .docScan, .idPhoto]),
        ToolGroup(name: "產生與決策", en: "GENERATE & DECIDE", accent: TT.indigo,
                  tools: [.qrStudio, .qrgen, .decider])
    ]

    private var localToolCount: Int {
        groups.reduce(0) { $0 + $1.tools.count }
    }

    var body: some View {
        ZStack {
            Backdrop()
            TechGrid()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    ForEach(groups) { group in
                        groupSection(group)
                    }
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 132)
            }
        }
        .fullScreenCover(item: $route) { r in
            ToolDestinationView(route: r)
                .environmentObject(store)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: 標題

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    MintDragonMark(size: 40)
                    Text("更多工具")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 7) {
                    Text("MORE TOOLS")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(TT.mint.opacity(0.7))
                    Rectangle()
                        .fill(TT.mint.opacity(0.25))
                        .frame(width: 22, height: 1)
                    Text("\(localToolCount) 個工具")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text("影像處理與產生工具，掃描、辨識、生碼都在這裡")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
    }

    // MARK: 分組

    private func groupSection(_ group: ToolGroup) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(group.accent)
                    .frame(width: 3, height: 13)
                    .shadow(color: group.accent.opacity(0.7), radius: 5)
                Text(group.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(group.en)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.2))
                Rectangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.09),
                                                  Color.white.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11),
                                GridItem(.flexible(), spacing: 11)],
                      spacing: 11) {
                ForEach(group.tools) { tool in
                    ToolCard(tool: tool) {
                        route = tool
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
        }
    }

    // MARK: 底部

    private var footerNote: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9.5))
                Text("新功能陸續加入，這一頁會越來越長")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.22))
            Text("YUAN SUN TECHNOLOGY · v1.0")
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.13))
        }
        .padding(.top, 6)
    }
}
