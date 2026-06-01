import AVFoundation
import Foundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCapture(_ engine: AudioCaptureEngine, chunk: AudioChunk)
    func audioCaptureDidFail(_ engine: AudioCaptureEngine, error: Error)
}

final class AudioCaptureEngine: NSObject {
    weak var delegate: AudioCaptureDelegate?
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    let outputFormat: AVAudioFormat
    var startDate: Date?
    private var isRunning = false

    override init() {
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        super.init()
    }

    func startMic() throws {
        guard !isRunning else { return }
        let input = engine.inputNode

        if input.isVoiceProcessingEnabled == false {
            do {
                try input.setVoiceProcessingEnabled(true)
            } catch {
                NSLog("voiceProcessing not available on this device: %@", String(describing: error))
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        startDate = Date()
        isRunning = true

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.process(buffer: buffer, time: time)
        }
        try engine.start()
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        startDate = nil
    }

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter = converter, let start = startDate else { return }
        let outBufCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        ) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outBufCapacity) else { return }

        var error: NSError?
        var inputProvided = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || outBuffer.frameLength == 0 { return }

        let frameCount = Int(outBuffer.frameLength)
        let ptr = outBuffer.floatChannelData![0]
        let samples = Array(UnsafeBufferPointer(start: ptr, count: frameCount))

        let elapsed = Date().timeIntervalSince(start)
        let durationMs = Int64(Double(frameCount) / outputFormat.sampleRate * 1000)
        let startMs = max(0, Int64(elapsed * 1000) - durationMs)

        let chunk = AudioChunk(channel: .mic, startMs: startMs, durationMs: durationMs, samples: samples)
        delegate?.audioCapture(self, chunk: chunk)
    }
}
