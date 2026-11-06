import Foundation
#if !FACEPAUSE_STANDALONE_TEST
import XCTest
#endif
import FaceCore

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class NetworkTests: XCTestCase {
    private func client() -> FacePhysClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return FacePhysClient(credentials: Credentials(keyID: "fixture-key", secret: "fixture-secret"), session: URLSession(configuration: config))
    }
    func testFullFlowAndStableSubmissionBody() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FacePauseTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("fixture.mp4")
        try Data("synthetic video fixture, not a person".utf8).write(to: video)
        var paths: [String] = []
        var submissions: [String] = []
        var fullResponses: [Data] = []
        MockProtocol.handler = { request in
            let path = request.url!.path
            paths.append(path)
            if path == "/object.mp4" {
                XCTAssertNil(request.value(forHTTPHeaderField: "x-key-id"))
                XCTAssertNil(request.value(forHTTPHeaderField: "x-signature"))
                XCTAssertEqual(request.httpMethod, "PUT")
                return (200, Data())
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-key-id"), "fixture-key")
            XCTAssertNotEqual(request.value(forHTTPHeaderField: "x-signature"), "fixture-secret")
            switch path {
            case "/api/agent/auth/test": return (200, Data(#"{"ok":true,"apiVersion":3}"#.utf8))
            case "/api/v2/video/upload/presign": return (200, Data(#"{"uploadUrl":"https://bucket.oss-cn-beijing.aliyuncs.com/object.mp4","objectKey":"object.mp4"}"#.utf8))
            case "/api/v3/video/process":
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        body.append(buffer, count: count)
                    }
                }
                let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
                XCTAssertEqual(json["confirmCharge"] as? Bool, true)
                XCTAssertEqual(json["videoSha256"] as? String, FacePhysClient.digest(try Data(contentsOf: video)))
                submissions.append(json["idempotencyKey"] as! String)
                return (200, Data(#"{"data":{"cardiac":{"hr":75,"sqi":0.8}}}"#.utf8))
            default: XCTFail("Unexpected request"); return (500, Data())
            }
        }
        for _ in 0..<2 {
            let result = try await client().process(video: video, confirmed: true, responseReceived: { fullResponses.append($0) }) { _ in }
            XCTAssertEqual(result.heartRate, 75)
        }
        XCTAssertEqual(paths.count, 8)
        XCTAssertEqual(submissions[0], submissions[1])
        XCTAssertEqual(fullResponses.count, 2)
        XCTAssertEqual(fullResponses[0], Data(#"{"data":{"cardiac":{"hr":75,"sqi":0.8}}}"#.utf8))
    }
    func testWrongAPIVersionAndAuthFailure() async {
        for response in [(200, #"{"ok":true,"apiVersion":2}"#), (401, #"{"error":"secret must not be shown"}"#)] {
            MockProtocol.handler = { _ in (response.0, Data(response.1.utf8)) }
            do { try await client().authenticate(); XCTFail("Must reject") }
            catch { XCTAssertFalse(error.localizedDescription.contains("secret must not be shown")) }
        }
    }
}
