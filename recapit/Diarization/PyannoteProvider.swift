import Foundation
import OnnxRuntimeBindings

final class PyannoteProvider: DiarizationProvider {
    private var session: ORTSession?
    private let modelURL: URL
    private let env: ORTEnv

    init() throws {
        env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recapit/models")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        modelURL = modelsDir.appendingPathComponent("pyannote-segmentation-3.0.onnx")
    }

    func ensureModelDownloaded() async throws {
        if FileManager.default.fileExists(atPath: modelURL.path) { return }
        let url = URL(string: "https://huggingface.co/pyannote/segmentation-3.0/resolve/main/pytorch_model.onnx")!
        let (tmpURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tmpURL, to: modelURL)
    }

    func diarize(samples: [Float], startMs: Int64) async throws -> [DiarizationSegment] {
        // v1 ships a single-speaker heuristic. Real inference + CAM++ clustering is v1.1.
        let durationMs = Int64(Double(samples.count) / 16.0)
        return [DiarizationSegment(startMs: startMs, endMs: startMs + durationMs, speakerId: "Speaker_1")]
    }
}
