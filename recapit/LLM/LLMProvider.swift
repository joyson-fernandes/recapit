import Foundation

protocol LLMProvider {
    func complete(_ prompt: String, json: Bool, model: String) async throws -> String
    func embed(_ texts: [String], model: String) async throws -> [[Float]]
}

enum LLMError: Error, LocalizedError {
    case http(Int, String)
    case decode(String)
    case noKey

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decode(let msg): return "Decode error: \(msg)"
        case .noKey: return "API key not set"
        }
    }
}
