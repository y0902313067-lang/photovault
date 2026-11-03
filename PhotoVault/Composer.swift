import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

// MARK: - 發佈動態

struct ComposerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var onDone: (() async -> Void)? = nil

    @State private var text = ""
    @State private var picked: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var busy = false
    @State private var tip: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextEditor(text: $text)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("想說點什麼…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white.opacity(0.25))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }

                    if let videoURL {
                        HStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .foregroundStyle(TT.mint)
                            Text(videoURL.lastPathComponent)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                self.videoURL = nil
                                self.videoItem = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $picked, maxSelectionCount: 9, matching: .images) {
                            toolChip(icon: "photo", label: "照片")
                        }
                        PhotosPicker(selection: $videoItem, matching: .videos) {
                            toolChip(icon: "video", label: "影片")
                        }
                        Spacer()
                    }

                    if let tip {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundStyle(TT.rose)
                    }

                    Text("發佈後所有人都能在你的主頁看到。最多 9 張照片，或一支影片。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.28))

                    Button {
                        submit()
                    } label: {
                        ZStack {
                            Capsule().fill(TT.mint)
                            if busy {
                                ProgressView().tint(Color(red: 0.03, green: 0.09, blue: 0.08))
                            } else {
                                Text("發佈")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.03, green: 0.09, blue: 0.08))
                            }
                        }
                        .frame(height: 48)
                    }
                    .disabled(busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                       && images.isEmpty && videoURL == nil))

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .background(Color(red: 0.045, green: 0.06, blue: 0.085).ignoresSafeArea())
            .navigationTitle("發佈動態")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .onChange(of: picked) { list in
                Task {
                    var out: [UIImage] = []
                    for item in list.prefix(9) {
                        if let d = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: d) {
                            out.append(img)
                        }
                    }
                    await MainActor.run { images = out }
                }
            }
            .onChange(of: videoItem) { item in
                guard let item else { return }
                Task {
                    if let movie = try? await item.loadTransferable(type: VideoTransfer.self) {
                        await MainActor.run { videoURL = movie.url }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func toolChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
    }

    private func submit() {
        guard !busy, let uid = store.authUserID else { return }
        busy = true
        tip = nil
        Task {
            do {
                try await SocialAPI.postFeed(userID: uid,
                                             text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                             images: images, video: videoURL,
                                             token: store.authToken)
                store.bumpTask("nicejob", add: 1)
                await onDone?()
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    busy = false
                    tip = error.localizedDescription
                }
            }
        }
    }
}

/// 把相簿裡的影片抓成暫存檔
struct VideoTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("pv-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: received.file, to: tmp)
            return Self(url: tmp)
        }
    }
}
