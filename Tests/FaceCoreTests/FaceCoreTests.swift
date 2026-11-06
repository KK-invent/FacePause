#if !FACEPAUSE_STANDALONE_TEST
import XCTest
#endif
import Foundation
import FaceCore

final class FaceCoreTests: XCTestCase {
    func testV3Parsing() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":72,"sqi":0.8,"hrv":{"rmssd":36,"sdnn":40,"breathing_rate":15}},"points_deducted":70000}}"#.utf8))
        XCTAssertEqual(result.heartRate, 72)
        XCTAssertEqual(result.rmssd, 36)
        XCTAssertEqual(result.tokens, 70000)
        XCTAssertTrue(result.suitableForAdvice)
    }
    func testCurrentBillingFieldsWithLegacyFallback() throws {
        let current = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":70,"sqi":0.8},"tokens_deducted":1234,"remaining_tokens":5678}}"#.utf8))
        XCTAssertEqual(current.tokens, 1234)
        XCTAssertEqual(current.remainingTokens, 5678)
        let zero = try PhysMeasurement(data: Data(#"{"data":{"tokens_deducted":0,"remaining_tokens":0}}"#.utf8))
        XCTAssertEqual(zero.tokens, 0)
        XCTAssertEqual(zero.remainingTokens, 0)
        let legacy = try PhysMeasurement(data: Data(#"{"data":{"points_deducted":9,"remaining_points":10}}"#.utf8))
        XCTAssertEqual(legacy.tokens, 9)
        XCTAssertEqual(legacy.remainingTokens, 10)
    }
    func testHeartSeriesKeepsOrderAndSkipsInvalidPoints() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr_list":[{"hr":70,"ts":0},{"hr":true},{"hr":"x"},{"hr":0},{"hr":72.5,"ts":2}]}}}"#.utf8))
        XCTAssertEqual(result.heartSeries, [70, 72.5])
        XCTAssertEqual(try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":70}}}"#.utf8)).heartSeries, [])
    }
    func testMissingQualityNeverEnablesAdvice() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":72}}}"#.utf8))
        XCTAssertNil(result.sqi)
        XCTAssertFalse(result.suitableForAdvice)
        XCTAssertTrue(result.advice[0].contains("不解读"))
    }
    func testWeakQualitySuppressesHealthInterpretation() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":140,"sqi":0.2}}}"#.utf8))
        XCTAssertFalse(result.suitableForAdvice)
        XCTAssertFalse(result.advice.joined().contains("静息范围"))
    }
    func testMissingAndInvalidValuesStayMissing() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":72,"sqi":2,"hrv":{"rmssd":true,"sdnn":-5,"breathing_rate":0}}}}"#.utf8))
        XCTAssertNil(result.sqi); XCTAssertNil(result.rmssd); XCTAssertNil(result.sdnn); XCTAssertNil(result.breathingRate)
    }
    func testErrorAndPendingResponsesAreNotResults() {
        for json in [#"{"error":"failed"}"#, #"{"status":"processing"}"#, #"{"data":{"status":"processing"}}"#, #"{"success":false,"data":{"cardiac":{"hr":72}}}"#] {
            XCTAssertThrowsError(try PhysMeasurement(data: Data(json.utf8)))
        }
    }
    func testSignatureMatchesKnownVector() {
        // Independently calculated HMAC-SHA256('secret', '1700000000').
        XCTAssertEqual(FacePhysClient.signature(secret: "secret", timestamp: "1700000000"), "SyJ/iDGzdj0GaQF1GtTFg+0IgyvxkkpOxQwuhxsehYY=")
    }
    func testRetryIdentityIsStableAndScopesKeys() {
        let digest = FacePhysClient.digest(Data("video".utf8))
        let a = FacePhysClient.submissionKey(digest: digest, keyID: "a")
        XCTAssertEqual(a, FacePhysClient.submissionKey(digest: digest, keyID: "a"))
        XCTAssertNotEqual(a, FacePhysClient.submissionKey(digest: digest, keyID: "b"))
        XCTAssertNotEqual(a, FacePhysClient.submissionKey(digest: FacePhysClient.digest(Data("other".utf8)), keyID: "a"))
    }
    func testNoConsentStopsBeforeFileOrNetworkAccess() async {
        let client = FacePhysClient(credentials: Credentials(keyID: "test", secret: "test"))
        do {
            _ = try await client.process(video: URL(fileURLWithPath: "/does-not-exist"), confirmed: false) { _ in XCTFail("Must not start") }
            XCTFail("Must reject")
        } catch { XCTAssertEqual(error.localizedDescription, "上传和扣费尚未确认。") }
    }
}
