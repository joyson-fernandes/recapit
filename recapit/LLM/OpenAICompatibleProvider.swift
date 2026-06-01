import Foundation

final class OpenAICompatibleProvider: LLMProvider {
    private let inner: OpenAIProvider
    init(apiKey: String, baseURL: URL, session: URLSession = .shared) {
        self.inner = OpenAIProvider(apiKey: apiKey, baseURL: baseURL, session: session)
    }
    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        try await inner.complete(prompt, json: json, model: model)
    }
    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        try await inner.embed(texts, model: model)
    }
}
