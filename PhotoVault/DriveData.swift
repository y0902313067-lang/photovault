import Foundation
import CoreLocation

/* ============================================================
   源隼測速 · 離線圖資
   固定式測速照相 / 區間測速 / 路網速限
   ============================================================ */

// MARK: - 模型

struct SpeedCamera {
    let lat: Double
    let lon: Double
    let limit: Int
    let dir: String
    let addr: String
}

struct IntervalZone {
    let startLat: Double
    let startLon: Double
    let endLat: Double
    let endLon: Double
    let limit: Int
    let span: Double          // 官方公告全長（公尺）
    let name: String
}

struct LimitSeg {
    let limit: Int
    let level: Int
    let pts: [Float]          // lat, lon, lat, lon …（絕對座標）
}

// MARK: - 幾何

enum Geo {
    static let rad = Double.pi / 180
    static let R = 6371000.0

    static func hav(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * rad
        let dLon = (lon2 - lon1) * rad
        let s1 = sin(dLat / 2), s2 = sin(dLon / 2)
        let a = s1 * s1 + cos(lat1 * rad) * cos(lat2 * rad) * s2 * s2
        return 2 * R * asin(min(1, sqrt(a)))
    }

    static func brg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dLon = (lon2 - lon1) * rad
        let y = sin(dLon) * cos(lat2 * rad)
        let x = cos(lat1 * rad) * sin(lat2 * rad) -
                sin(lat1 * rad) * cos(lat2 * rad) * cos(dLon)
        return norm360(atan2(y, x) / rad)
    }

    static func norm360(_ a: Double) -> Double {
        let m = a.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    static func angDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// 點到線段距離（公尺，平面近似）
    static func pointSegDist(_ pLat: Double, _ pLon: Double,
                             _ aLat: Double, _ aLon: Double,
                             _ bLat: Double, _ bLon: Double) -> Double {
        let mlat = (aLat + bLat) / 2 * rad
        let kx = 111320 * cos(mlat)
        let ky = 110540.0
        let px = (pLon - aLon) * kx, py = (pLat - aLat) * ky
        let vx = (bLon - aLon) * kx, vy = (bLat - aLat) * ky
        let len2 = vx * vx + vy * vy
        var t = len2 > 0 ? (px * vx + py * vy) / len2 : 0
        t = max(0, min(1, t))
        let dx = px - vx * t, dy = py - vy * t
        return sqrt(dx * dx + dy * dy)
    }

    /// 方向文字 → 目前航向是否符合
    static func dirAllowed(_ text: String, travel: Double?) -> Bool {
        guard let travel = travel else { return true }
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        if t.contains("雙向") || t.contains("双向") { return true }
        if t.contains("南北雙") || t.contains("東西雙") { return true }
        if t.contains("往南北") || t.contains("往東西") { return true }
        let map: [(String, Double)] = [
            ("南向北", 0), ("北向南", 180), ("西向東", 90), ("東向西", 270),
            ("北往南", 180), ("南往北", 0), ("東往西", 270), ("西往東", 90),
            ("往北", 0), ("往南", 180), ("往東", 90), ("往西", 270)
        ]
        for (k, deg) in map where t.contains(k) {
            return angDiff(travel, deg) < 78
        }
        return true
    }

    /// 依車速決定預警提前量
    static func warnDist(_ kmh: Double) -> Double {
        if kmh < 45 { return 300 }
        if kmh < 70 { return 450 }
        if kmh < 95 { return 650 }
        return 850
    }
}

// MARK: - 圖資

final class DriveData {
    static let shared = DriveData()

    private(set) var cameras: [SpeedCamera] = []
    private(set) var intervals: [IntervalZone] = []
    private(set) var tiles: [String: [LimitSeg]] = [:]

    private var started = false
    private var finished = false
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "yuansun.drive.data", qos: .userInitiated)

    private static let TILE = 0.05

    var tileCount: Int { tiles.count }

    /// 背景載入；重複呼叫只載一次，載完立刻回呼
    func prepare(_ completion: @escaping () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            DispatchQueue.main.async { completion() }
            return
        }
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        queue.async { [weak self] in
            guard let self = self else { return }
            self.loadCameras()
            self.loadIntervals()
            self.loadLimits()
            self.lock.lock()
            self.finished = true
            self.lock.unlock()
            DispatchQueue.main.async { completion() }
        }
    }

    private func json(_ name: String) -> Any? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj
    }

    private func loadCameras() {
        guard let arr = json("cameras") as? [[String: Any]] else { return }
        var out: [SpeedCamera] = []
        out.reserveCapacity(arr.count)
        for d in arr {
            guard let lat = d["a"] as? Double, let lon = d["o"] as? Double else { continue }
            out.append(SpeedCamera(lat: lat,
                                   lon: lon,
                                   limit: d["l"] as? Int ?? 0,
                                   dir: d["d"] as? String ?? "",
                                   addr: d["r"] as? String ?? ""))
        }
        cameras = out
    }

    private func loadIntervals() {
        guard let arr = json("intervals") as? [[String: Any]] else { return }
        var out: [IntervalZone] = []
        for d in arr {
            guard let a = d["a"] as? [Double], a.count >= 2,
                  let b = d["b"] as? [Double], b.count >= 2 else { continue }
            out.append(IntervalZone(startLat: a[0], startLon: a[1],
                                    endLat: b[0], endLon: b[1],
                                    limit: d["l"] as? Int ?? 0,
                                    span: Double(d["s"] as? Int ?? 0),
                                    name: d["n"] as? String ?? ""))
        }
        intervals = out
    }

    private func loadLimits() {
        guard let dict = json("limits") as? [String: Any] else { return }
        var out: [String: [LimitSeg]] = [:]
        out.reserveCapacity(dict.count)
        let tile = DriveData.TILE

        for (key, value) in dict {
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let ti = Int(parts[0]), let tj = Int(parts[1]),
                  let segs = value as? [[Any]] else { continue }
            let lat0 = Double(ti) * tile
            let lon0 = Double(tj) * tile
            var list: [LimitSeg] = []
            list.reserveCapacity(segs.count)
            for seg in segs {
                guard seg.count >= 4 else { continue }
                let limit = (seg[0] as? NSNumber)?.intValue ?? (seg[0] as? Int ?? 0)
                let level = (seg[1] as? NSNumber)?.intValue ?? 1
                var pts: [Float] = []
                pts.reserveCapacity((seg.count - 2) / 2 * 2)
                var k = 2
                while k + 1 < seg.count {
                    let x = (seg[k] as? NSNumber)?.doubleValue ?? 0
                    let y = (seg[k + 1] as? NSNumber)?.doubleValue ?? 0
                    pts.append(Float(lat0 + y * 1e-5))
                    pts.append(Float(lon0 + x * 1e-5))
                    k += 2
                }
                if pts.count >= 4 {
                    list.append(LimitSeg(limit: limit, level: level, pts: pts))
                }
            }
            if !list.isEmpty { out[key] = list }
        }
        tiles = out
    }

    // MARK: 查詢

    /// 精確命中判定：車子離路段這麼近，才算真的走在這條路上
    private static let EXACT_DIST = 26.0
    /// 高架／平面重疊時，兩層距離差在這以內才算「腳下兩條路」
    private static let OVERLAP_SLACK = 25.0

    /// 該座標的路段速限；查不到回 nil
    func limitAt(_ lat: Double, _ lon: Double) -> Int? { limitHit(lat, lon) }

    /// 只回報該座標路段「確實收錄」的速限，查不到就是 nil——不做任何推定
    /// - Parameter speedKmh: 當前車速，用於高架／平面重疊時判斷走哪一層
    func limitHit(_ lat: Double, _ lon: Double, speedKmh: Double = 0) -> Int? {
        if tiles.isEmpty { return nil }
        let ti = Int(floor(lat / DriveData.TILE))
        let tj = Int(floor(lon / DriveData.TILE))

        // 最近的一般路段
        var bestLimit: Int?
        var bestLevel = 0
        var bestDist = Double.greatestFiniteMagnitude
        // 最近的高等級道路（快速道路／國道），用來判斷高架重疊
        var highLimit: Int?
        var highLevel = 0
        var highDist = Double.greatestFiniteMagnitude

        for di in -1...1 {
            for dj in -1...1 {
                let key = "\(ti + di),\(tj + dj)"
                guard let segs = tiles[key] else { continue }
                for seg in segs {
                    var d = Double.greatestFiniteMagnitude
                    var i = 0
                    while i + 3 < seg.pts.count {
                        let dd = Geo.pointSegDist(lat, lon,
                                                  Double(seg.pts[i]), Double(seg.pts[i + 1]),
                                                  Double(seg.pts[i + 2]), Double(seg.pts[i + 3]))
                        if dd < d { d = dd }
                        i += 2
                    }
                    if d < bestDist {
                        bestDist = d
                        bestLimit = seg.limit
                        bestLevel = seg.level
                    }
                    if seg.level >= 8, d < highDist {
                        highDist = d
                        highLimit = seg.limit
                        highLevel = seg.level
                    }
                }
            }
        }

        // 只採用腳下這段路「確實收錄」的速限
        guard let b = bestLimit, bestDist <= DriveData.EXACT_DIST else {
            // 查不到就回 nil：畫面不顯示數字，語音也不會報——絕不推測
            return nil
        }
        // 高架／平面上下重疊：車速快就當作走上面那層
        if let h = highLimit, highLevel > bestLevel,
           highDist <= max(DriveData.EXACT_DIST, bestDist + DriveData.OVERLAP_SLACK),
           speedKmh >= 70 {
            return h
        }
        // 明明是平面路段，但旁邊 25 公尺內的高速速限被拉進來 → 不採用
        return b
    }
}
