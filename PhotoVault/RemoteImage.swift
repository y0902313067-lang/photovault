import SwiftUI
import UIKit
import ImageIO

// MARK: - 遠端圖片快取
//
// 列表（聊天室、動態）每次重繪都會重新建立圖片視圖。
// 走系統的 AsyncImage 時，視圖一重建就重新抓、重新解碼，
// 訊息一多就會明顯卡。這裡改成記憶體快取 + 一次下載，
// 同一張圖不管重繪幾次都只解碼一次。
//
// v38 追加：解碼時直接做成顯示尺寸的小圖（降採樣）。
// 聊天室的圖只有 180pt、頭像只有 38pt，原本卻是把整張原圖
// （常見 3000×4000）解碼後再縮小顯示，滑動時每一張都在燒 CPU 與記憶體，
// 這是「滑起來卡」最主要的原因之一。

final class PVImageCache {
    static let shared = PVImageCache()

    /// key 帶上目標像素，同一張原圖的不同尺寸分開快取
    private struct Key: Hashable {
        let url: URL
        let pixel: Int
    }

    private let mem = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        mem.countLimit = 700
        mem.totalCostLimit = 90 * 1024 * 1024

        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                diskCapacity: 256 * 1024 * 1024,
                                diskPath: "pv_images")
        session = URLSession(configuration: cfg)
    }

    private func cacheKey(_ url: URL, _ pixel: Int) -> NSString {
        "\(url.absoluteString)|\(pixel)" as NSString
    }

    func cached(_ url: URL, maxPixel: CGFloat? = nil) -> UIImage? {
        let px = pixelBucket(maxPixel)
        return mem.object(forKey: cacheKey(url, px))
    }

    func store(_ img: UIImage, for url: URL, maxPixel: CGFloat? = nil) {
        let px = pixelBucket(maxPixel)
        let cost = Int(img.size.width * img.size.height * 4)
        mem.setObject(img, forKey: cacheKey(url, px), cost: cost)
    }

    /// 已有快取就立刻回，沒有才下載（同一張只下載一次）
    ///
    /// v46：解碼搬到背景執行緒。
    /// 這裡原本在 await 之後直接解，呼叫端是 SwiftUI 的 .task（繼承主執行緒），
    /// 所以 ImageIO 的縮圖解碼其實全卡在主執行緒上。一張 3000×4000 的圖
    /// 幾十毫秒，列表一次進來六張就是幾百毫秒的主執行緒佔用——整台機器都會頓。
    func load(_ url: URL, maxPixel: CGFloat? = nil) async -> UIImage? {
        if let c = cached(url, maxPixel: maxPixel) { return c }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let px = maxPixel
        let img = await Task.detached(priority: .utility) {
            Self.decode(data, maxPixel: px)
        }.value
        if let img { store(img, for: url, maxPixel: maxPixel) }
        return img
    }

    /// 0 代表不限尺寸（看原圖用）
    private func pixelBucket(_ maxPixel: CGFloat?) -> Int {
        guard let maxPixel, maxPixel > 0 else { return 0 }
        // 取整到 40px 一檔，避免同一張圖因為零點幾的差異重複快取
        return Int((maxPixel / 40).rounded(.up)) * 40
    }

    /// 直接用 ImageIO 解成小圖：記憶體只花縮圖那份，不會先把整張原圖解開
    static func decode(_ data: Data, maxPixel: CGFloat?) -> UIImage? {
        guard let maxPixel, maxPixel > 0 else { return UIImage(data: data) }
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 快取圖片視圖

struct CachedImage: View {
    let url: URL?
    /// 顯示尺寸上限（像素）。傳 nil 表示要原圖。
    var maxPixel: CGFloat? = nil
    var placeholder: AnyView = AnyView(Color.white.opacity(0.05))

    @State private var image: UIImage?

    /// 建立時先同步查一次記憶體快取：列表滾動時視圖會被回收再重建，
    /// 有快取就直接出圖，不再重新跑一次非同步載入（也就沒有閃一下）
    init(url: URL?,
         maxPixel: CGFloat? = nil,
         placeholder: AnyView = AnyView(Color.white.opacity(0.05))) {
        self.url = url
        self.maxPixel = maxPixel
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap {
            PVImageCache.shared.cached($0, maxPixel: maxPixel)
        })
    }

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
        .task(id: taskID) { await reload() }
    }

    private var taskID: String {
        "\(url?.absoluteString ?? "")|\(maxPixel ?? -1)"
    }

    private func reload() async {
        guard let url else {
            await apply(nil)
            return
        }
        if let fast = PVImageCache.shared.cached(url, maxPixel: maxPixel) {
            await apply(fast)
            return
        }
        let img = await PVImageCache.shared.load(url, maxPixel: maxPixel)
        await apply(img)
    }

    @MainActor
    private func apply(_ img: UIImage?) {
        if image !== img { image = img }
    }
}
