import Foundation

enum SpeakerLabeler {
    static func label(channel: AudioChannel, segments: [DiarizationSegment]) -> [DiarizationSegment] {
        if channel == .mic {
            return segments.map { DiarizationSegment(startMs: $0.startMs, endMs: $0.endMs, speakerId: "You") }
        }
        return segments
    }
}
