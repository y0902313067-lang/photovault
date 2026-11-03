import Foundation
import CoreLocation
import Combine
import UIKit

/* ============================================================
   源隼測速 · 預警狀態機
   ① 路段速限：取自路網圖資，查不到就顯示未收錄（不回退）
   ② 測速照相：依航向判斷是否在前方，分遠近兩段播報
   ③ 區間測速：通過起點開始計時，即時算平均車速，通過終點結算
   ============================================================ */

// MARK: - 對外狀態

struct CameraAlert: Equatable {
    let distance: Double
    let limit: Int
    let addr: String
    let near: Bool
}

struct IntervalApproach: Equatable {
    let distance: Double
    let limit: Int
    let name: String
}

struct IntervalLive: Equatable {
    let name: String
    let limit: Int
    let total: Double
    let avg: Double
    let travelled: Double
    let remaining: Double
    let over: Bool
}

// MARK: - 引擎

final class DriveAlertEngine: ObservableObject {

    // 對外顯示
    @Published private(set) var limit: Int?
    @Published private(set) var limitFromInterval = false
    @Published private(set) var limitEstimated = false
    @Published private(set) var cameraAlert: CameraAlert?
    @Published private(set) var intervalApproach: IntervalApproach?
    @Published private(set) var intervalLive: IntervalLive?
    @Published private(set) var overSpeed = false
    @Published private(set) var dataReady = false
    @Published private(set) var cameraCount = 0
    @Published private(set) var intervalCount = 0
    @Published var voiceOn: Bool = DriveVoice.shared.enabled {
        didSet { DriveVoice.shared.enabled = voiceOn }
    }
    /// 沒有實測速限的路段，是否用同級道路鄰近路段推定（預設開）
    @Published var estimateOn: Bool = UserDefaults.standard.object(forKey: "driveEstimateOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(estimateOn, forKey: "driveEstimateOn")
            candidateAt = Date.distantPast
        }
    }

    private let data = DriveData.shared

    // 內部
    private struct CamFire { var at: Date; var stage: Int }
    private struct IntervalRun {
        let index: Int
        let zone: IntervalZone
        var distance: Double = 0
        var movingTime: Double = 0
        let startedAt: Date
        var lastCoord: CLLocationCoordinate2D?
        var lastAt: Date
        var saidEnd = false
        var avg: Double = 0
    }

    private var travel: Double?
    private var lastCoord: CLLocationCoordinate2D?
    private var speedKmh: Double = 0
    private var firedCam: [Int: CamFire] = [:]
    private var firedIv: [Int: Date] = [:]
    private var candidateLimit: Int?
    private var candidateAt: Date?
    private var candidateEst = false
    private var saidLimit: Int?
    private var overAt = Date.distantPast
    private var run: IntervalRun?

    // MARK: 初始化

    init() {
        data.prepare { [weak self] in
            guard let self = self else { return }
            self.dataReady = true
            self.cameraCount = self.data.cameras.count
            self.intervalCount = self.data.intervals.count
        }
    }

    // MARK: 每帧更新

    /// 由定位回呼呼叫；speedMPS 用 GPS 瞬時速度（公尺/秒）
    func update(location: CLLocation, speedMPS: Double) {
        guard dataReady else { return }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let now = Date()

        // 速度平滑
        let raw = max(speedMPS, 0) * 3.6
        speedKmh = speedKmh * 0.55 + raw * 0.45
        if speedKmh < 1.5 { speedKmh = 0 }

        updateTravel(lat: lat, lon: lon, course: location.course, speedMPS: speedMPS)

        handleIntervalApproachAndRun(lat: lat, lon: lon, now: now)
        handleCamera(lat: lat, lon: lon, now: now)
        refreshLimit(lat: lat, lon: lon, now: now)
        handleOverSpeed(now: now)

        lastCoord = location.coordinate
    }

    /// 停止測速時清掉暫時狀態
    func reset() {
        cameraAlert = nil
        intervalApproach = nil
        intervalLive = nil
        run = nil
        firedCam = [:]
        firedIv = [:]
        candidateLimit = nil
        candidateAt = nil
        saidLimit = nil
        limit = nil
        limitFromInterval = false
        overSpeed = false
        travel = nil
        lastCoord = nil
        speedKmh = 0
    }

    // MARK: 航向

    private func updateTravel(lat: Double, lon: Double, course: Double, speedMPS: Double) {
        if course >= 0, speedMPS > 1.5 {
            travel = Geo.norm360(course)
            return
        }
        guard let prev = lastCoord else { return }
        let step = Geo.hav(prev.latitude, prev.longitude, lat, lon)
        guard step > 8 else { return }
        let b = Geo.brg(prev.latitude, prev.longitude, lat, lon)
        if let t = travel {
            var d = (b - t + 540).truncatingRemainder(dividingBy: 360) - 180
            if d < -180 { d += 360 }
            travel = Geo.norm360(t + d * 0.35)
        } else {
            travel = b
        }
    }

    // MARK: ① 路段速限

    private func refreshLimit(lat: Double, lon: Double, now: Date) {
        // 區間路段自帶速限，優先且立即採用
        if let r = run {
            applyLimit(r.zone.limit, fromInterval: true, estimated: false, now: now)
            candidateLimit = r.zone.limit
            candidateEst = false
            candidateAt = now
            return
        }

        let hit = data.limitHit(lat, lon)
        var found = hit?.speed
        var est = hit?.estimated ?? false
        if est, !estimateOn { found = nil; est = false }
        if found != candidateLimit || est != candidateEst {
            candidateLimit = found
            candidateEst = est
            candidateAt = now
            if found == nil { applyLimit(nil, fromInterval: false, estimated: false, now: now) }
            return
        }
        guard let f = found, let at = candidateAt else { return }
        // 連續 2.5 秒都在同一速限才確認，避免路口跳動
        if now.timeIntervalSince(at) > 2.5 {
            applyLimit(f, fromInterval: false, estimated: est, now: now)
        }
    }

    private func applyLimit(_ v: Int?, fromInterval: Bool, estimated: Bool = false, now: Date) {
        if limit != v { limit = v }
        if limitFromInterval != fromInterval { limitFromInterval = fromInterval }
        if limitEstimated != estimated { limitEstimated = estimated }

        let over = (v != nil) && speedKmh > Double(v!) + 9 && speedKmh > 12
        if overSpeed != over { overSpeed = over }

        if let v = v {
            if !fromInterval, saidLimit != v {
                saidLimit = v
                DriveVoice.shared.speak(DriveSpeech.limit(v))
            }
        } else {
            saidLimit = nil
        }
    }

    // MARK: ② 測速照相

    private func scanCamera(lat: Double, lon: Double) -> (index: Int, distance: Double, cam: SpeedCamera)? {
        guard !data.cameras.isEmpty else { return nil }
        let warn = Geo.warnDist(speedKmh)
        var best: (Int, Double, SpeedCamera)?
        for (i, c) in data.cameras.enumerated() {
            if abs(c.lat - lat) > 0.02 { continue }        // 粗篩：約 2 公里
            let d = Geo.hav(lat, lon, c.lat, c.lon)
            if d > warn { continue }
            if !Geo.dirAllowed(c.dir, travel: travel) { continue }
            if let t = travel {
                // 必須在車頭前方
                if Geo.angDiff(Geo.brg(lat, lon, c.lat, c.lon), t) > 80 { continue }
            }
            if best == nil || d < best!.1 { best = (i, d, c) }
        }
        return best
    }

    private func handleCamera(lat: Double, lon: Double, now: Date) {
        guard let hit = scanCamera(lat: lat, lon: lon) else {
            if cameraAlert != nil { cameraAlert = nil }
            return
        }

        let rec = firedCam[hit.index]
        let passed = rec.map { now.timeIntervalSince($0.at) > 180 } ?? true

        if passed {
            firedCam[hit.index] = CamFire(at: now, stage: 1)
            setCamera(CameraAlert(distance: hit.distance,
                                  limit: hit.cam.limit,
                                  addr: hit.cam.addr,
                                  near: false))
            DriveVoice.shared.speak(DriveSpeech.camera(hit.distance, hit.cam.limit))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }

        if let r = rec {
            if r.stage == 1 && hit.distance < 160 {
                firedCam[hit.index] = CamFire(at: r.at, stage: 2)
                setCamera(CameraAlert(distance: hit.distance,
                                      limit: hit.cam.limit,
                                      addr: hit.cam.addr,
                                      near: true))
                DriveVoice.shared.speak(DriveSpeech.cameraNear(hit.cam.limit))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            // 距離持續遞減，畫面跟著更新
            setCamera(CameraAlert(distance: hit.distance,
                                  limit: hit.cam.limit,
                                  addr: hit.cam.addr,
                                  near: r.stage >= 2))
        }
    }

    private func setCamera(_ v: CameraAlert?) {
        // 距離取整到 10 公尺，減少無意義重繪
        if let old = cameraAlert, let new = v,
           Int(old.distance / 10) == Int(new.distance / 10),
           old.near == new.near, old.limit == new.limit, old.addr == new.addr {
            return
        }
        cameraAlert = v
    }

    // MARK: ③ 區間測速

    private func scanInterval(lat: Double, lon: Double) -> (index: Int, distance: Double, zone: IntervalZone)? {
        guard !data.intervals.isEmpty else { return nil }
        var best: (Int, Double, IntervalZone)?
        for (i, z) in data.intervals.enumerated() {
            let dA = Geo.hav(lat, lon, z.startLat, z.startLon)
            if dA > 420 { continue }
            let dirAB = Geo.brg(z.startLat, z.startLon, z.endLat, z.endLon)
            if let t = travel, Geo.angDiff(t, dirAB) >= 85 { continue }
            if best == nil || dA < best!.1 { best = (i, dA, z) }
        }
        return best
    }

    private func handleIntervalApproachAndRun(lat: Double, lon: Double, now: Date) {
        // 有進行中的就先算進行中的
        if var r = run {
            r = advance(r, lat: lat, lon: lon, now: now)
            run = r
            publishRun(r, lat: lat, lon: lon)
            return
        }

        guard let hit = scanInterval(lat: lat, lon: lon) else {
            if intervalApproach != nil { intervalApproach = nil }
            return
        }

        // 接近起點：播一次
        if hit.distance < 360 {
            if firedIv[hit.index] == nil {
                firedIv[hit.index] = now
                setApproach(IntervalApproach(distance: hit.distance,
                                             limit: hit.zone.limit,
                                             name: hit.zone.name))
                DriveVoice.shared.speak(DriveSpeech.intervalStart(hit.distance,
                                                                  hit.zone.limit,
                                                                  hit.zone.span))
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                setApproach(IntervalApproach(distance: hit.distance,
                                             limit: hit.zone.limit,
                                             name: hit.zone.name))
            }
        } else if intervalApproach != nil {
            intervalApproach = nil
        }

        // 通過起點：開始計時
        if hit.distance < 70 {
            run = IntervalRun(index: hit.index,
                              zone: hit.zone,
                              startedAt: now,
                              lastCoord: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                              lastAt: now)
            intervalApproach = nil
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    private func advance(_ r0: IntervalRun, lat: Double, lon: Double, now: Date) -> IntervalRun {
        var r = r0
        if let lp = r.lastCoord {
            let step = Geo.hav(lp.latitude, lp.longitude, lat, lon)
            // 只累計合理位移，GPS 飄移不算
            if step > 2, step < 600 { r.distance += step }
        }
        let dt = now.timeIntervalSince(r.lastAt)
        if dt > 0.08, dt < 5, speedKmh > 2 { r.movingTime += dt }

        r.lastCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        r.lastAt = now

        let span = r.movingTime > 1 ? r.movingTime : now.timeIntervalSince(r.startedAt)
        r.avg = span > 1 ? (r.distance / span) * 3.6 : 0
        return r
    }

    private func publishRun(_ r: IntervalRun, lat: Double, lon: Double) {
        let zone = r.zone
        let remaining = max(0, zone.span - r.distance)
        let over = r.avg > Double(zone.limit) && r.avg > 0

        let live = IntervalLive(name: zone.name,
                                limit: zone.limit,
                                total: zone.span,
                                avg: r.avg,
                                travelled: r.distance,
                                remaining: remaining,
                                over: over)
        if intervalLive != live { intervalLive = live }

        let dEnd = Geo.hav(lat, lon, zone.endLat, zone.endLon)

        // 接近終點先報一次結果
        if dEnd < 350, !r.saidEnd, r.avg > 0 {
            var rr = r
            rr.saidEnd = true
            run = rr
            DriveVoice.shared.speak(DriveSpeech.intervalEnd(rr.avg, zone.limit, over))
            return
        }

        // 通過終點：結算收尾
        if remaining < 100 || dEnd < 80 {
            if !r.saidEnd, r.avg > 0 {
                DriveVoice.shared.speak(DriveSpeech.intervalEnd(r.avg, zone.limit, over))
            }
            firedIv[r.index] = Date()          // 短期內不再重複進場
            run = nil
            intervalLive = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func setApproach(_ v: IntervalApproach?) {
        if let old = intervalApproach, let new = v,
           Int(old.distance / 10) == Int(new.distance / 10), old.name == new.name {
            return
        }
        intervalApproach = v
    }

    // MARK: 超速提醒

    private func handleOverSpeed(now: Date) {
        guard let lim = limit, speedKmh >= 12 else {
            if overSpeed { overSpeed = false }
            return
        }
        let over = speedKmh > Double(lim) + 9
        if overSpeed != over { overSpeed = over }
        if over, now.timeIntervalSince(overAt) > 25 {
            overAt = now
            DriveVoice.shared.speak(DriveSpeech.overSpeed(speedKmh, lim))
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}
