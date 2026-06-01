import Foundation

final class OpenAIProvider: LLMProvider {
    let apiKey: String
    let baseURL: URL
    private let session: URLSession

    init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]]
        ]
        if json {
            body["response_format"] = ["type": "json_object"]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        struct R: Decodable {
            struct Choice: Decodable { struct M: Decodable { let content: String }; let message: M }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(R.self, from: data).choices.first?.message.content ?? ""
    }

    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        let url = baseURL.appendingPathComponent("embeddings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "input": texts]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try check(resp, data)
        struct R: Decodable { struct D: Decodable { let embedding: [Float] }; let data: [D] }
        return try JSONDecoder().decode(R.self, from: data).data.map(\.embedding)
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let h = resp as? HTTPURLResponse else { return }
        if h.statusCode >= 400 {
            throw LLMError.http(h.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
