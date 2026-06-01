import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

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
    private var scStream: SCStream?

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
        Task { try? await scStream?.stopCapture() }
        scStream = nil
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

extension AudioCaptureEngine: SCStreamDelegate, SCStreamOutput {
    func startSystem() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(domain: "AudioCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No display"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Minimal video (required by SCStream even if you only want audio)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)

        if startDate == nil {
            startDate = Date()
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio,
                                    sampleHandlerQueue: DispatchQueue(label: "recapit.scstream"))
        try await stream.startCapture()
        self.scStream = stream
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        processSystemAudio(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegate?.audioCaptureDidFail(self, error: error)
    }

    private func processSystemAudio(_ buffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(buffer),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                          lengthAtOffsetOut: &lengthAtOffset,
                                          totalLengthOut: &totalLength,
                                          dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let pointer = dataPointer else { return }

        // ScreenCaptureKit gives us 48 kHz / 2ch / Float32 interleaved
        let frameCount = totalLength / (MemoryLayout<Float>.size * 2)
        var monoSamples = [Float](repeating: 0, count: frameCount)
        let floats = pointer.withMemoryRebound(to: Float.self, capacity: frameCount * 2) { $0 }
        for i in 0..<frameCount {
            monoSamples[i] = (floats[i * 2] + floats[i * 2 + 1]) * 0.5
        }

        // Decimate 48k → 16k (take every 3rd sample)
        var resampled = [Float]()
        resampled.reserveCapacity(frameCount / 3)
        var idx = 0
        while idx < frameCount {
            resampled.append(monoSamples[idx])
            idx += 3
        }

        guard let start = startDate else { return }
        let durationMs = Int64(Double(resampled.count) / 16_000 * 1000)
        let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
        let startMs = max(0, elapsed - durationMs)

        let chunk = AudioChunk(channel: .system, startMs: startMs,
                               durationMs: durationMs, samples: resampled)
        delegate?.audioCapture(self, chunk: chunk)
    }
}
