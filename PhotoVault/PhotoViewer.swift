import SwiftUI

// MARK: - 全螢幕看原圖（左右滑、下滑關閉）

struct PhotoViewer: View {
    let urls: [URL]
    let start: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var dragY: CGFloat = 0

    init(urls: [URL], start: Int = 0) {
        self.urls = urls
        self.start = start
        _index = State(initialValue: min(max(start, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - Double(min(dragY, 220)) / 520)
                .ignoresSafeArea()

            if urls.isEmpty {
                Text("圖片載入失敗")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                TabView(selection: $index) {
                    ForEach(urls.indices, id: \.self) { i in
                        AsyncImage(url: urls[i]) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFit()
                            case .failure:
                                VStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 26))
                                    Text("這張讀不出來")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.white.opacity(0.4))
                            default:
                                ProgressView().tint(.white.opacity(0.6))
                            }
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .offset(y: dragY)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 6)
                }
                Spacer()
                if urls.count > 1 {
                    Text("\(index + 1) / \(urls.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .padding(.bottom, 26)
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { v in
                    dragY = max(0, v.translation.height)
                }
                .onEnded { v in
                    if v.translation.height > 110 {
                        dismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) { dragY = 0 }
                    }
                }
        )
        .statusBarHidden(true)
    }
}
