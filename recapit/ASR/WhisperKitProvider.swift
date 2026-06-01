import Foundation
import WhisperKit

final class WhisperKitProvider: ASRProvider {
    private var pipe: WhisperKit?
    private let modelName: String

    init(modelName: String) {
        self.modelName = modelName
    }

    func load() async throws {
        if pipe != nil { return }
        pipe = try await WhisperKit(model: modelName)
    }

    func transcribe(samples: [Float], language: String? = "en") async throws -> ASRResult {
        try await load()
        guard let pipe = pipe else { throw ASRError.modelNotLoaded }
        let options = DecodingOptions(language: language, withoutTimestamps: false)
        let results: [TranscriptionResult] = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let combinedText = results.map(\.text).joined(separator: " ")
        var segs: [(Int64, Int64, String)] = []
        for r in results {
            for s in r.segments {
                segs.append((Int64(s.start * 1000), Int64(s.end * 1000), s.text))
            }
        }
        return ASRResult(text: combinedText, segments: segs)
    }
}
