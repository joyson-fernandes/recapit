import Foundation

actor ChunkBuffer {
    private let windowSeconds: Int = 30
    private let overlapSeconds: Int = 5
    private let sampleRate: Int = 16_000

    private var micBuffer: [Float] = []
    private var micStartMs: Int64 = 0
    private var systemBuffer: [Float] = []
    private var systemStartMs: Int64 = 0

    private var handler: ((AudioChannel, Int64, [Float]) -> Void)?

    func setHandler(_ h: @escaping (AudioChannel, Int64, [Float]) -> Void) {
        handler = h
    }

    func append(_ chunk: AudioChunk) {
        switch chunk.channel {
        case .mic:
            if micBuffer.isEmpty { micStartMs = chunk.startMs }
            micBuffer.append(contentsOf: chunk.samples)
            maybeEmit(channel: .mic)
        case .system:
            if systemBuffer.isEmpty { systemStartMs = chunk.startMs }
            systemBuffer.append(contentsOf: chunk.samples)
            maybeEmit(channel: .system)
        }
    }

    func flush() {
        if !micBuffer.isEmpty { handler?(.mic, micStartMs, micBuffer); micBuffer = [] }
        if !systemBuffer.isEmpty { handler?(.system, systemStartMs, systemBuffer); systemBuffer = [] }
    }

    private func maybeEmit(channel: AudioChannel) {
        let buf: [Float]
        let start: Int64
        switch channel {
        case .mic: buf = micBuffer; start = micStartMs
        case .system: buf = systemBuffer; start = systemStartMs
        }
        let needed = windowSeconds * sampleRate
        guard buf.count >= needed else { return }
        let window = Array(buf.prefix(needed))
        handler?(channel, start, window)
        let keep = overlapSeconds * sampleRate
        let kept = Array(buf.suffix(buf.count - (needed - keep)))
        let advance = (needed - keep) * 1000 / sampleRate
        switch channel {
        case .mic:    micBuffer = kept;    micStartMs = start + Int64(advance)
        case .system: systemBuffer = kept; systemStartMs = start + Int64(advance)
        }
    }
}
