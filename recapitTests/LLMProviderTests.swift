import XCTest
@testable import recapit

final class LLMProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.responses = [:]
        super.tearDown()
    }

    func testOllamaCompleteRoundtrip() async throws {
        MockURLProtocol.responses = [
            "/api/generate": ("{\"response\":\"Summary here\",\"done\":true}", 200)
        ]
        let provider = OllamaProvider(baseURL: URL(string: "http://localhost:11434")!,
                                      session: makeMockSession())
        let r = try await provider.complete("Test prompt", json: false, model: "llama3.1:8b")
        XCTAssertEqual(r, "Summary here")
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol {
    static var responses: [String: (String, Int)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let (body, code) = Self.responses[path] ?? ("", 404)
        let resp = HTTPURLResponse(url: request.url!, statusCode: code,
                                   httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
