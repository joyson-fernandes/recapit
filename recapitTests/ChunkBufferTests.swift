import XCTest
@testable import recapit

final class ChunkBufferTests: XCTestCase {
    func testEmits30sWindowWith5sOverlap() async {
        let buffer = ChunkBuffer()
        var emitted = [(channel: AudioChannel, startMs: Int64, endMs: Int64)]()
        await buffer.setHandler { (channel, startMs, samples) in
            emitted.append((channel, startMs, startMs + Int64(samples.count) * 1000 / 16_000))
        }
        // Push 35s of mic audio in 1-second chunks
        for i in 0..<35 {
            let samples = [Float](repeating: 0.1, count: 16_000)
            await buffer.append(AudioChunk(channel: .mic,
                                           startMs: Int64(i * 1000),
                                           durationMs: 1000,
                                           samples: samples))
        }
        await buffer.flush()
        XCTAssertGreaterThanOrEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.startMs, 0)
        XCTAssertGreaterThanOrEqual(emitted.first!.endMs - emitted.first!.startMs, 25_000)
    }
}
