import Foundation
import AppKit

@MainActor
protocol RecordingCoordinatorDelegate: AnyObject {
    func coordinator(_ c: RecordingCoordinator, didChangeState: RecordingCoordinator.State)
    func coordinator(_ c: RecordingCoordinator, recordingMeeting: Meeting)
    func coordinator(_ c: RecordingCoordinator, finishedMeeting: Meeting)
}

@MainActor
final class RecordingCoordinator: AudioCaptureDelegate {
    enum State: String { case idle, countdown, recording, processing }

    weak var delegate: RecordingCoordinatorDelegate?
    private(set) var state: State = .idle { didSet { delegate?.coordinator(self, didChangeState: state) } }
    private(set) var currentMeeting: Meeting?

    let db: MeetingDB
    let markdown: MarkdownStore
    let settings: SettingsStore
    let captureEngine = AudioCaptureEngine()
    let chunkBuffer = ChunkBuffer()
    let asr: ASRProvider
    let summaryEngine: () -> SummaryEngine

    private var countdownTimer: Timer?

    init(db: MeetingDB, markdown: MarkdownStore, settings: SettingsStore,
         asr: ASRProvider, summaryEngineFactory: @escaping () -> SummaryEngine) {
        self.db = db
        self.markdown = markdown
        self.settings = settings
        self.asr = asr
        self.summaryEngine = summaryEngineFactory
        captureEngine.delegate = self
        Task { [weak self] in
            await self?.chunkBuffer.setHandler { [weak self] channel, startMs, samples in
                Task { await self?.transcribeWindow(channel: channel, startMs: startMs, samples: samples) }
            }
        }
    }

    func startCountdown(title: String, calendarEventId: String? = nil,
                        meetingURL: URL? = nil) {
        guard state == .idle else { return }
        state = .countdown
        let m = Meeting.draft(title: title, startedAt: Date().addingTimeInterval(TimeInterval(settings.countdownSeconds)))
        currentMeeting = m
        let seconds = settings.countdownSeconds
        var remaining = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                Task { @MainActor in await self?.beginRecording(meetingURL: meetingURL) }
            }
        }
    }

    func cancelCountdown() {
        guard state == .countdown else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        currentMeeting = nil
        state = .idle
    }

    func startAdhoc() {
        startCountdown(title: "Untitled meeting · \(DateFormatter.iso.string(from: Date()))")
    }

    private func beginRecording(meetingURL: URL?) async {
        guard var meeting = currentMeeting else { return }
        meeting.startedAt = Int64(Date().timeIntervalSince1970)
        meeting.state = .recording
        try? db.insertMeeting(meeting)
        currentMeeting = meeting
        state = .recording
        delegate?.coordinator(self, recordingMeeting: meeting)

        if let url = meetingURL, settings.autoJoinCalendarURLs {
            NSWorkspace.shared.open(url)
        }

        do {
            try captureEngine.startMic()
            if !settings.skipSystemAudio {
                try await captureEngine.startSystem()
            }
        } catch {
            NSLog("capture start failed: %@", String(describing: error))
            state = .idle
        }
    }

    func stop() async {
        guard state == .recording, var meeting = currentMeeting else { return }
        captureEngine.stop()
        await chunkBuffer.flush()
        meeting.endedAt = Int64(Date().timeIntervalSince1970)
        meeting.state = .processing
        try? db.updateMeeting(meeting)
        state = .processing
        delegate?.coordinator(self, finishedMeeting: meeting)

        do {
            try await summaryEngine().process(meetingId: meeting.id)
        } catch {
            NSLog("summary failed: %@", String(describing: error))
        }
        state = .idle
        currentMeeting = nil
    }

    // MARK: - AudioCaptureDelegate
    nonisolated func audioCapture(_ engine: AudioCaptureEngine, chunk: AudioChunk) {
        Task { await self.chunkBuffer.append(chunk) }
    }
    nonisolated func audioCaptureDidFail(_ engine: AudioCaptureEngine, error: Error) {
        NSLog("audio capture failure: %@", String(describing: error))
    }

    private func transcribeWindow(channel: AudioChannel, startMs: Int64, samples: [Float]) async {
        guard let meetingId = currentMeeting?.id else { return }
        do {
            let result = try await asr.transcribe(samples: samples, language: "en")
            for seg in result.segments {
                let segment = TranscriptSegment(
                    id: nil, meetingId: meetingId, channel: channel.rawValue,
                    startMs: startMs + seg.startMs, endMs: startMs + seg.endMs,
                    speaker: channel == .mic ? "You" : "Speaker_1",
                    text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try db.appendSegment(segment)
            }
        } catch {
            NSLog("ASR window failed: %@", String(describing: error))
        }
    }
}

private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
