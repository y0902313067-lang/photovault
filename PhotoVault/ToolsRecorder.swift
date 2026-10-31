import SwiftUI
import AVFoundation
import Speech

// MARK: - 錄音項目

struct RecordingItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let date: Date
    let duration: TimeInterval
    let size: Int64

    var title: String { id }
    var durationText: String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    var sizeText: String {
        if size > 1_048_576 { return String(format: "%.1f MB", Double(size) / 1_048_576) }
        return String(format: "%d KB", max(1, size / 1024))
    }
    var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 模型

final class RecorderModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recordings: [RecordingItem] = []
    @Published var recording = false
    @Published var elapsed: TimeInterval = 0
    @Published var playingID: String? = nil
    @Published var message: String? = nil
    @Published var transcribing = false
    @Published var transcript: String? = nil

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func load() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder,
                                                 includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? []

        var items: [RecordingItem] = []
        for url in files where url.pathExtension.lowercased() == "m4a" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.creationDate ?? Date()
            let dur = RecorderModel.duration(of: url)
            var name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix("錄音-") { name.removeFirst(3) }
            items.append(RecordingItem(id: name, url: url, date: date,
                                       duration: dur, size: size))
        }
        recordings = items.sorted { $0.date > $1.date }
    }

    static func duration(of url: URL) -> TimeInterval {
        if let p = try? AVAudioPlayer(contentsOf: url) { return p.duration }
        return 0
    }

    func askAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            Task { @MainActor in
                if ok {
                    self.start()
                } else {
                    self.message = "沒有麥克風權限，請到「設定 → 薄荷龍科技」開啟"
                }
            }
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let url = folder.appendingPathComponent("錄音-\(f.string(from: Date())).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()

            recording = true
            elapsed = 0
            message = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let rec = self.recorder else { return }
                    self.elapsed = rec.currentTime
                }
            }
        } catch {
            message = "錄音開不起來，檢查一下麥克風權限"
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        recording = false
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: [.notifyOthersOnDeactivation])
        load()
    }

    func togglePlay(_ item: RecordingItem) {
        if playingID == item.id {
            player?.stop()
            player = nil
            playingID = nil
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: item.url)
            player?.play()
            playingID = item.id
        } catch {
            message = "這個檔案播不出來"
        }
    }

    func delete(_ item: RecordingItem) {
        if playingID == item.id {
            player?.stop()
            player = nil
            playingID = nil
        }
        try? FileManager.default.removeItem(at: item.url)
        load()
    }

    // MARK: 轉文字

    func transcribe(_ item: RecordingItem) {
        transcribing = true
        transcript = nil
        message = nil

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.transcribing = false
                    self.message = "沒有語音辨識權限，請到設定裡開啟"
                    return
                }
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
                    ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
                self.recognizer = recognizer

                guard let rec = recognizer, rec.isAvailable else {
                    self.transcribing = false
                    self.message = "這台裝置的語音辨識暫時不可用"
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: item.url)
                request.shouldReportPartialResults = true

                self.task = rec.recognitionTask(with: request) { result, error in
                    Task { @MainActor in
                        if let result = result {
                            self.transcript = result.bestTranscription.formattedString
                            if result.isFinal { self.transcribing = false }
                        }
                        if error != nil && self.transcript == nil {
                            self.transcribing = false
                            self.message = "這段音檔辨識不出來，換一段試試"
                        }
                    }
                }
            }
        }
    }

    func clearTranscript() {
        task?.cancel()
        task = nil
        transcript = nil
        transcribing = false
    }
}

// MARK: - 頁面

struct RecorderView: View {
    @StateObject private var model = RecorderModel()
    @State private var pendingDelete: RecordingItem? = nil

    var body: some View {
        TTScreen(title: "錄音機",
                 subtitle: "VOICE RECORDER",
                 badge: model.recording ? "REC" : nil,
                 badgeOn: true,
                 accent: TT.violet) {

            recordCard

            if !model.recordings.isEmpty {
                listPanel
            } else {
                TTPanel(accent: TT.violet) {
                    TTEmptyHint(icon: "waveform",
                                text: "還沒有錄音。按上面的按鈕開始，錄完會存在這台手機裡")
                }
            }

            if let message = model.message {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(TT.rose.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.transcribing || model.transcript != nil {
                transcriptPanel
            }

            TTPanel(accent: TT.teal) {
                VStack(alignment: .leading, spacing: 9) {
                    TTSectionTitle(text: "關於通話錄音", accent: TT.teal)
                    Text("iOS 在通話時把麥克風交給系統電話，第三方 App 拿不到，所以沒辦法錄通話內容。這台機器能錄的是：會議、上課、訪談、備忘，以及開擴音時放在桌上的對話。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield").font(.system(size: 9))
                        Text("錄音檔只存在本機，不會上傳")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.26))
                }
            }
        }
        .onAppear { model.load() }
        .alert("刪掉這段錄音？", isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } })) {
            Button("刪除", role: .destructive) {
                if let item = pendingDelete { model.delete(item) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: 錄音控制

    private var recordCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(TT.violet.opacity(0.14))
                    .frame(width: 138, height: 138)
                Circle()
                    .strokeBorder(TT.violet.opacity(0.28), lineWidth: 1)
                    .frame(width: 138, height: 138)
                TTRing(progress: model.recording ? min(model.elapsed / 60, 1) : 0,
                       accent: TT.violet, lineWidth: 5)
                    .frame(width: 138, height: 138)

                VStack(spacing: 4) {
                    Text(timeText)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(model.recording ? "錄音中" : "待機")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(model.recording
                                         ? TT.rose.opacity(0.95)
                                         : Color.white.opacity(0.32))
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if model.recording { model.stop() } else { model.askAndStart() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.recording ? "stop.fill" : "record.circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.recording ? "停止並儲存" : "開始錄音")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(TT.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: model.recording
                                             ? [TT.rose, TT.amber]
                                             : [TT.violet, TT.blue],
                                             startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: (model.recording ? TT.rose : TT.violet).opacity(0.4),
                        radius: 16, y: 7)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var timeText: String {
        let t = Int(model.elapsed)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    // MARK: 清單

    private var listPanel: some View {
        TTPanel(accent: TT.violet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TTSectionTitle(text: "我的錄音", accent: TT.violet)
                    Spacer(minLength: 6)
                    Text("\(model.recordings.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(TT.violet)
                }

                ForEach(model.recordings) { item in
                    VStack(spacing: 0) {
                        HStack(spacing: 11) {
                            Button {
                                model.togglePlay(item)
                            } label: {
                                ZStack {
                                    Circle().fill(TT.violet.opacity(0.16))
                                    Image(systemName: model.playingID == item.id ? "stop.fill" : "play.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(TT.violet)
                                }
                                .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.dateText)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("\(item.durationText) · \(item.sizeText)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.white.opacity(0.35))
                            }

                            Spacer(minLength: 4)

                            Button {
                                model.transcribe(item)
                            } label: {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)

                            ShareLink(item: item.url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                pendingDelete = item
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(TT.rose.opacity(0.75))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 9)

                        if item.id != model.recordings.last?.id {
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
    }

    // MARK: 轉文字

    private var transcriptPanel: some View {
        TTPanel(accent: TT.blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TTSectionTitle(text: "辨識結果", accent: TT.blue)
                    Spacer(minLength: 4)
                    if model.transcribing {
                        ProgressView().tint(TT.blue).scaleEffect(0.7)
                    }
                }
                Text(model.transcript ?? "正在聽…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !model.transcribing, let text = model.transcript {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Text("複製文字")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TT.blue)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    model.clearTranscript()
                } label: {
                    Text("關閉")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
