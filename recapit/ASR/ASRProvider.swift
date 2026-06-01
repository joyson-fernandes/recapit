import Foundation

struct ASRResult {
    let text: String
    let segments: [(startMs: Int64, endMs: Int64, text: String)]
}

protocol ASRProvider {
    func transcribe(samples: [Float], language: String?) async throws -> ASRResult
}

enum ASRError: Error {
    case modelNotLoaded
    case backendFailure(String)
}
