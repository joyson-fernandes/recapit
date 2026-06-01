import Foundation

enum AudioChannel: String {
    case mic
    case system
}

struct AudioChunk {
    let channel: AudioChannel
    let startMs: Int64
    let durationMs: Int64
    let samples: [Float]
}
