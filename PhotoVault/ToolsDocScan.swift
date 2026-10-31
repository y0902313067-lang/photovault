import SwiftUI
import UIKit
import VisionKit

// MARK: - 系統文件掃描器

struct DocScannerPicker: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocScannerPicker
        init(_ parent: DocScannerPicker) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            for i in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: i))
            }
            parent.onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

// MARK: - PDF 產生

enum DocPDF {
    static func build(pages: [UIImage]) -> URL? {
        guard !pages.isEmpty else { return nil }
        let size = CGSize(width: 595, height: 842)   // A4 @72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        let data = renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage()
                let margin: CGFloat = 18
                let box = CGRect(x: margin, y: margin,
                                 width: size.width - margin * 2,
                                 height: size.height - margin * 2)
                let ratio = min(box.width / page.size.width, box.height / page.size.height)
                let drawW = page.size.width * ratio
                let drawH = page.size.height * ratio
                let rect = CGRect(x: box.midX - drawW / 2,
                                  y: box.midY - drawH / 2,
                                  width: drawW, height: drawH)
                page.draw(in: rect)
            }
        }
        let name = "掃描檔-\(stamp()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - 頁面

struct DocScanView: View {
    @State private var pages: [UIImage] = []
    @State private var showScanner = false
    @State private var pdfURL: URL?
    @State private var warning: String?

    var body: some View {
        TTScreen(title: "文件掃描",
                 subtitle: "DOC SCANNER",
                 badge: pages.isEmpty ? nil : "\(pages.count) 頁",
                 badgeOn: true,
                 accent: TT.blue) {

            ActionCard(accent: TT.blue,
                       icon: "doc.viewfinder",
                       title: pages.isEmpty ? "掃描第一份文件" : "再掃下一份／續掃",
                       note: pages.isEmpty
                            ? "相機會自動找紙張邊緣、壓平、去陰影，一次可連拍多頁"
                            : "按下後接著掃，新頁會加到目前的文件後面") {
                showScanner = true
            }

            if pages.isEmpty {
                TTPanel(accent: TT.blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        TTSectionTitle(text: "怎麼用", accent: TT.blue)
                        tip("1", "把紙放在光線均勻的地方，整張紙進到框裡")
                        tip("2", "自動辨識邊框，歪了會自己拉正、陰影會壓掉")
                        tip("3", "連續拍多頁，按儲存後合成一份 PDF")
                        tip("4", "產出的 PDF 可存到檔案、分享出去或列印")
                    }
                }
            } else {
                pagesPanel

                if let url = pdfURL {
                    ShareLink(item: url) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("匯出／分享 PDF")
                                .font(.system(size: 14.5, weight: .semibold))
                        }
                        .foregroundStyle(TT.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [TT.blue, TT.mint],
                                                     startPoint: .leading, endPoint: .trailing))
                        )
                    }
                    .buttonStyle(.plain)

                    Text("檔案：\(url.lastPathComponent)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                TTButton(title: "清空重來", icon: "trash", accent: TT.rose) {
                    pages = []
                    pdfURL = nil
                }
            }

            if let warning = warning {
                Text(warning)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TT.rose.opacity(0.9))
            }

            TTPanel(accent: TT.teal) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(TT.mint)
                    Text("掃描與轉檔全部在這台手機完成，檔案不會上傳到任何伺服器")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocScannerPicker(onFinish: { newPages in
                pages.append(contentsOf: newPages)
                showScanner = false
                rebuild()
            }, onCancel: {
                showScanner = false
            })
            .ignoresSafeArea()
        }
    }

    private var pagesPanel: some View {
        TTPanel(accent: TT.blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TTSectionTitle(text: "已掃描頁面", accent: TT.blue)
                    Spacer(minLength: 6)
                    Text("\(pages.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(TT.blue)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9),
                                    GridItem(.flexible(), spacing: 9),
                                    GridItem(.flexible(), spacing: 9)],
                          spacing: 9) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 108)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )

                            Button {
                                pages.remove(at: idx)
                                rebuild()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.black.opacity(0.65)))
                            }
                            .buttonStyle(.plain)
                            .padding(5)
                        }
                    }
                }
            }
        }
    }

    private func rebuild() {
        if pages.isEmpty {
            pdfURL = nil
            return
        }
        pdfURL = DocPDF.build(pages: pages)
        warning = pdfURL == nil ? "PDF 產生失敗，請再試一次" : nil
    }

    private func tip(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(n)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(TT.ink)
                .frame(width: 18, height: 18)
                .background(Circle().fill(TT.blue.opacity(0.85)))
            Text(t)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 通用操作卡

struct ActionCard: View {
    var accent: Color = TT.mint
    var icon: String
    var title: String
    var note: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.4)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                        .shadow(color: accent.opacity(0.35), radius: 12, y: 5)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(TT.ink)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
