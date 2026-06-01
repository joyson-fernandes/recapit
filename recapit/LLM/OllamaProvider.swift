import Foundation

final class OllamaProvider: LLMProvider {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:11434")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        if json {
            body["format"] = "json"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response, data: data)
        struct Response: Decodable { let response: String }
        return try JSONDecoder().decode(Response.self, from: data).response
    }

    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        var out: [[Float]] = []
        for text in texts {
            let url = baseURL.appendingPathComponent("api/embeddings")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": text])
            let (data, resp) = try await session.data(for: req)
            try checkHTTP(resp, data: data)
            struct R: Decodable { let embedding: [Float] }
            out.append(try JSONDecoder().decode(R.self, from: data).embedding)
        }
        return out
    }

    private func checkHTTP(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
