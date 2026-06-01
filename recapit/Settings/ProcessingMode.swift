import Foundation

enum ProcessingMode: String, Codable, CaseIterable {
    case local
    case cloud
    case hybrid

    var displayName: String {
        switch self {
        case .local: return "Local — fully offline"
        case .cloud: return "Cloud — paste an API key"
        case .hybrid: return "Hybrid — local ASR + cloud LLM"
        }
    }
}

enum ASRProviderID: String, Codable, CaseIterable {
    case whisperKit
    case deepgram
    case openAIWhisper
}

enum LLMProviderID: String, Codable, CaseIterable {
    case ollama
    case openAI
    case anthropic
    case openAICompatible
}

enum DiarizationProviderID: String, Codable, CaseIterable {
    case pyannoteONNX
    case pyannoteCloud
}

enum KeepAudio: String, Codable, CaseIterable {
    case never
    case sevenDays
    case forever
}
