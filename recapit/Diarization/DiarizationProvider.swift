import Foundation

struct DiarizationSegment {
    let startMs: Int64
    let endMs: Int64
    let speakerId: String
}

protocol DiarizationProvider {
    func diarize(samples: [Float], startMs: Int64) async throws -> [DiarizationSegment]
}

enum DiarizationError: Error {
    case modelNotAvailable
    case inferenceFailure(String)
}
