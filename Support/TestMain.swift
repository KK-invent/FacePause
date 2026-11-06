// A lightweight runner for CLT-only Macs, which do not ship XCTest.
// The same test methods still run under XCTest when Xcode is installed.
import Foundation
var failures = 0
class XCTestCase {}
func XCTFail(_ message: String = "Assertion failed", file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value() { XCTFail("Expected true", file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value() { XCTFail("Expected false", file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a != b { XCTFail("Values differ", file: file, line: line) }
}
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a == b { XCTFail("Values should differ", file: file, line: line) }
}
func XCTAssertNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) {
    if a != nil { XCTFail("Expected nil", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); XCTFail("Expected error", file: file, line: line) } catch {}
}
@main struct TestMain {
    static func main() async {
        do {
            let tests = FaceCoreTests()
            try tests.testV3Parsing()
            try tests.testCurrentBillingFieldsWithLegacyFallback()
            try tests.testHeartSeriesKeepsOrderAndSkipsInvalidPoints()
            try tests.testMissingQualityNeverEnablesAdvice()
            try tests.testWeakQualitySuppressesHealthInterpretation()
            try tests.testMissingAndInvalidValuesStayMissing()
            tests.testErrorAndPendingResponsesAreNotResults()
            tests.testSignatureMatchesKnownVector()
            tests.testRetryIdentityIsStableAndScopesKeys()
            await tests.testNoConsentStopsBeforeFileOrNetworkAccess()
            let network = NetworkTests()
            try await network.testFullFlowAndStableSubmissionBody()
            await network.testWrongAPIVersionAndAuthFailure()
            let scheduler = ScheduleTests()
            scheduler.testIntervalAndActiveHours()
            scheduler.testNightAndQuotaMoveToNextDay()
            scheduler.testBlockedStatesCannotStart()
            try scheduler.testReservationsSurviveRestartAndStopAtLimit()
            scheduler.testMidnightResetsQuota()
            scheduler.testLateWakeSchedulesFutureWithoutCatchUp()
            let full = FullResponseTests()
            try full.testEveryLeafAppearsExactlyOnceIncludingUnknownData()
            try full.testRawResponseSurvivesPersistenceExactly()
            try full.testOnlyNonCardiacModulesAreStillVisible()
            try full.testOldRecordsRemainReadableWithoutInventedRawResponse()
            try full.testInvalidSummaryValuesArePreservedInCompleteData()
            try full.testEmptyAndFalseResponsesDoNotBecomeHealthClaims()
            let reports = ProviderReportsTests()
            try reports.testNestedReportPreservesEveryPartWithoutDuplicateSections()
            reports.testNoReportIsNotReplacedByAppAdvice()
            try reports.testLongTextIsNeverTruncated()
            reports.testChineseAndRootReportsAreIncluded()
            let deepSeek = DeepSeekTests()
            try deepSeek.testOnlyMeasurementNumbersLeaveDevice()
            try deepSeek.testMissingAndExcessiveInputRejected()
            try await deepSeek.testExactModelPayloadAndCompleteResponse()
            try await deepSeek.testHTTPFailuresNeverRetryOrEchoSecrets()
            try await deepSeek.testIncompleteMalformedAndBlankReportsRejected()
            try await deepSeek.testAuthenticationOnlyReadsModels()
            try deepSeek.testReportRestoresOnlyForMatchingMeasurement()
            try await deepSeek.testEmptyKeyStopsBeforeNetwork()
        } catch { XCTFail("Unexpected error: \(error.localizedDescription)") }
        print("36 test methods finished; \(failures) failures. Synthetic inputs and mocked networking only.")
        exit(failures == 0 ? 0 : 1)
    }
}
