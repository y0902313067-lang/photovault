import SwiftUI
import UIKit

// MARK: - 遠端圖片快取
//
// 列表（聊天室、動態）每次重繪都會重新建立圖片視圖。
// 走系統的 AsyncImage 時，視圖一重建就重新抓、重新解碼，
// 訊息一多就會明顯卡。這裡改成記憶體快取 + 一次下載，
// 同一張圖不管重繪幾次都只解碼一次。

final class PVImageCache {
    static let shared = PVImageCache()

    private let mem = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        mem.countLimit = 500
        mem.totalCostLimit = 120 * 1024 * 1024

        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                diskCapacity: 256 * 1024 * 1024,
                                diskPath: "pv_images")
        session = URLSession(configuration: cfg)
    }

    func cached(_ url: URL) -> UIImage? {
        mem.object(forKey: url as NSURL)
    }

    func store(_ img: UIImage, for url: URL) {
        let cost = Int(img.size.width * img.size.height * 4)
        mem.setObject(img, forKey: url as NSURL, cost: cost)
    }

    /// 已有快取就立刻回，沒有才下載（同一張只下載一次）
    func load(_ url: URL) async -> UIImage? {
        if let c = cached(url) { return c }
        guard let (data, _) = try? await session.data(from: url),
              let img = UIImage(data: data) else { return nil }
        store(img, for: url)
        return img
    }
}

// MARK: - 快取圖片視圖

struct CachedImage: View {
    let url: URL?
    var placeholder: AnyView = AnyView(Color.white.opacity(0.05))

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) { await reload() }
    }

    private func reload() async {
        guard let url else {
            await apply(nil)
            return
        }
        if let fast = PVImageCache.shared.cached(url) {
            await apply(fast)
            return
        }
        let img = await PVImageCache.shared.load(url)
        await apply(img)
    }

    @MainActor
    private func apply(_ img: UIImage?) {
        if image !== img { image = img }
    }
}
