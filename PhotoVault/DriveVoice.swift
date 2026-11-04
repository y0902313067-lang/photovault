import Foundation
import AVFoundation

/* ============================================================
   源隼測速 · 語音播報
   用系統語音，行車時壓低音樂後播報，講完自動恢復
   系統語音本身偏小聲，這裡把聲音再放大後才送出去
   ============================================================ */

final class DriveVoice {
    static let shared = DriveVoice()

    /// 額外增益：約 2.5 倍音量，搭配下面的軟性限幅，不會爆音
    private static let GAIN: Float = 2.5
    /// 限幅的起點（0~1）
    private static let KNEE: Float = 0.62

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var playerAttached = false
    private var engineFormat: AVAudioFormat?
    private var engineReady = false

    private var lastName = ""
    private var lastAt = Date.distantPast
    private var sessionReady = false
    /// 每次播報或停止都 +1，舊的緩衝回來就丟掉
    private var generation = 0
    /// 這一輪有沒有拿到可播放的音訊緩衝
    private var hasBuffered = false

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

    // MARK: 音訊環境

    func activateSession() {
        guard !sessionReady else { return }
        let s = AVAudioSession.sharedInstance()
        // .duckOthers：講話時把音樂壓小，講完自己回來；不混音，才不會被音樂蓋掉
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? s.setActive(true)
        sessionReady = true
    }

    // MARK: 發聲

    func speak(_ text: String) {
        guard enabled, !text.isEmpty else { return }
        let now = Date()
        // 同一句短時間內不重複
        if text == lastName, now.timeIntervalSince(lastAt) < 6 { return }
        lastName = text
        lastAt = now

        activateSession()
        stopPlayback()
        generation &+= 1
        let gen = generation

        let u = AVSpeechUtterance(string: text)
        u.voice = Self.preferredVoice()
        u.rate = 0.46
        u.pitchMultiplier = 1.0
        u.volume = 1.0

        // 先把語音寫成音訊緩衝，放大後再播；引擎若不可用就直接用系統播放（保險）
        hasBuffered = false
        synth.write(u) { [weak self] buffer in
            guard let self = self, gen == self.generation else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            guard let loud = self.boosted(pcm) else { return }
            self.hasBuffered = true
            self.player.scheduleBuffer(loud, completionHandler: nil)
            if !self.player.isPlaying { self.player.play() }
        }
        // 語音是背景執行緒慢慢吐出來的，等一小段時間還沒有任何緩衝才退回系統播放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self = self, gen == self.generation, !self.hasBuffered else { return }
            self.synth.speak(u)
        }
    }

    func stop() {
        generation &+= 1
        stopPlayback()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        sessionReady = false
    }

    private func stopPlayback() {
        if player.isPlaying { player.stop() }
    }

    // MARK: 音量放大

    /// 把語音緩衝轉成標準浮點格式並放大，帶軟性限幅（大聲但不破音）
    private func boosted(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let rate = src.format.sampleRate
        let chans = src.format.channelCount
        guard rate > 0, chans > 0,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: chans)
        else { return nil }

        if !engineReady || engineFormat?.sampleRate != rate || engineFormat?.channelCount != chans {
            guard prepareEngine(fmt) else { return nil }
        }

        guard let conv = AVAudioConverter(from: src.format, to: fmt),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: src.frameLength)
        else { return nil }

        var handed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if handed {
                status.pointee = .noDataNow
                return nil
            }
            handed = true
            status.pointee = .haveData
            return src
        }
        guard err == nil, out.frameLength > 0, let data = out.floatChannelData else { return nil }

        let n = Int(out.frameLength)
        for c in 0..<Int(chans) {
            let p = data[c]
            for i in 0..<n {
                let x = p[i] * Self.GAIN
                let a = abs(x)
                if a <= Self.KNEE {
                    p[i] = x
                } else {
                    // 超過起點就壓成平滑曲線，峰值收到 1.0 以內（大聲但不破音）
                    let room = 1 - Self.KNEE
                    let t = (a - Self.KNEE) / room
                    let y = Self.KNEE + room * (t / (1 + t))
                    p[i] = x < 0 ? -y : y
                }
            }
        }
        return out
    }

    private func prepareEngine(_ fmt: AVAudioFormat) -> Bool {
        if !playerAttached {
            engine.attach(player)
            playerAttached = true
        }
        if engine.isRunning { engine.stop() }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()
        do {
            try engine.start()
            engineFormat = fmt
            engineReady = true
            return true
        } catch {
            engineReady = false
            return false
        }
    }

    // MARK: 語音挑選

    /// 優先挑品質最好的中文語音（進階/增強版比較清楚也比較大聲）
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        var best: AVSpeechSynthesisVoice?
        var bestScore = -1
        for v in voices {
            guard v.language.hasPrefix("zh") else { continue }
            var score = 0
            if v.language == "zh-TW" { score += 100 } else if v.language == "zh-CN" { score += 60 }
            switch v.quality {
            case .premium: score += 30
            case .enhanced: score += 20
            default: score += 5
            }
            if score > bestScore {
                bestScore = score
                best = v
            }
        }
        if let b = best { return b }
        return AVSpeechSynthesisVoice(language: "zh-TW")
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
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
