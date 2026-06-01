import Foundation

final class AnthropicProvider: LLMProvider {
    let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        struct R: Decodable {
            struct C: Decodable { let text: String? }
            let content: [C]
        }
        return try JSONDecoder().decode(R.self, from: data).content.compactMap(\.text).joined()
    }

    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        throw LLMError.http(501, "Anthropic does not provide embeddings — switch embedding provider to OpenAI or Ollama in Settings.")
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let h = resp as? HTTPURLResponse else { return }
        if h.statusCode >= 400 {
            throw LLMError.http(h.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
