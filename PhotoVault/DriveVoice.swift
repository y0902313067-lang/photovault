import Foundation
import AVFoundation

/* ============================================================
   源隼測速 · 語音播報
   用系統語音，行車時壓低音樂後播報，講完自動恢復
   ============================================================ */

final class DriveVoice {
    static let shared = DriveVoice()

    private let synth = AVSpeechSynthesizer()
    private var lastName = ""
    private var lastAt = Date.distantPast
    private var sessionReady = false

    private static let enabledKey = "pv_drive_voice_on"

    var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: DriveVoice.enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: DriveVoice.enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DriveVoice.enabledKey)
            if !newValue { stop() }
        }
    }

    /// 有沒有可用的中文語音
    var hasChineseVoice: Bool {
        if AVSpeechSynthesisVoice(language: "zh-TW") != nil { return true }
        if AVSpeechSynthesisVoice(language: "zh-CN") != nil { return true }
        return false
    }

    func activateSession() {
        guard !sessionReady else { return }
        let s = AVAudioSession.sharedInstance()
        // .duckOthers：講話時把音樂壓小，講完自己回來
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? s.setActive(true)
        sessionReady = true
    }

    func speak(_ text: String) {
        guard enabled, !text.isEmpty else { return }
        let now = Date()
        // 同一句短時間內不重複；新訊息打斷舊的，免得排隊積壓
        if text == lastName, now.timeIntervalSince(lastAt) < 6 { return }
        lastName = text
        lastAt = now

        activateSession()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-TW")
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.5
        u.pitchMultiplier = 1.0
        u.volume = 1.0
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        sessionReady = false
    }
}

// MARK: - 播報文字

enum DriveSpeech {
    /// 公里數念得順一點：1.2 公里 / 850 公尺
    static func dist(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f 公里", m / 1000) }
        return "\(Int((m / 10).rounded()) * 10) 公尺"
    }

    static func limit(_ kmh: Int) -> String {
        "前方路段限速 \(kmh) 公里"
    }

    static func camera(_ meters: Double, _ kmh: Int) -> String {
        if meters >= 120 {
            return "前方 \(dist(meters)) 有測速照相，限速 \(kmh) 公里"
        }
        return "測速照相，限速 \(kmh) 公里"
    }

    static func cameraNear(_ kmh: Int) -> String {
        "通過測速照相，限速 \(kmh) 公里"
    }

    static func intervalStart(_ meters: Double, _ kmh: Int, _ span: Double) -> String {
        var s = "前方 \(dist(meters)) 進入區間測速，限速 \(kmh) 公里"
        if span > 0 { s += "，全長 \(String(format: "%.1f", span / 1000)) 公里" }
        return s
    }

    static func intervalEnd(_ avg: Double, _ kmh: Int, _ over: Bool) -> String {
        let a = Int(avg.rounded())
        if over {
            return "區間測速結束，平均 \(a) 公里，超過限速 \(kmh) 公里"
        }
        return "區間測速結束，平均 \(a) 公里，未超速"
    }

    static func overSpeed(_ now: Double, _ kmh: Int) -> String {
        "目前 \(Int(now.rounded())) 公里，超過限速 \(kmh) 公里"
    }
}
