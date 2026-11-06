import Foundation
import FaceCore
#if !FACEPAUSE_STANDALONE_TEST
import XCTest
#endif

final class FullResponseTests: XCTestCase {
    private let fixture = #"{"data":{"cardiac":{"hr":71,"sqi":0.8,"hrv":{"rmssd":0,"LF/HF":0.17},"hr_list":[{"hr":70,"ts":0},{"hr":72,"ts":1}]},"bp":{"sbp":118,"dbp":76},"psych":{"ms":32},"emotion":{"surface":{"Neutral":0.8}},"face_au":{"mouth_smile":0},"behavior":{"perclos":0},"appearance":{"age":{"value":29}},"liveness":{"is_live":false},"new_module":{"empty":[],"object":{},"missing":null,"text":"中文完整文字","a/b~c":[0,false,""]}},"points_deducted":252000,"request_id":"fixture-request","extra_root":[1,2]}"#
    func testEveryLeafAppearsExactlyOnceIncludingUnknownData() throws {
        let data = Data(fixture.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        let expected = FullResponse.fields(object).map(\.id).sorted()
        let actual = FullResponse.groups(from: data).flatMap(\.fields).map(\.id).sorted()
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(Set(actual).count, actual.count)
        XCTAssertTrue(actual.contains("/data/new_module/a~1b~0c/1"))
    }
    func testRawResponseSurvivesPersistenceExactly() throws {
        let data = Data(("  \n" + fixture + "\n").utf8)
        let result = try PhysMeasurement(data: data)
        let restored = try JSONDecoder().decode(PhysMeasurement.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(restored.originalResponse, data)
        XCTAssertEqual(FullResponse.rawText(data), "  \n" + fixture + "\n")
        XCTAssertEqual(restored.tokens, 252000)
    }
    func testOnlyNonCardiacModulesAreStillVisible() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"new_model":{"score":17},"emotion":{"surface":{"Neutral":0.75}}}}"#.utf8))
        XCTAssertNil(result.heartRate)
        XCTAssertFalse(result.suitableForAdvice)
        XCTAssertEqual(result.fieldGroups.flatMap(\.fields).count, 2)
    }
    func testOldRecordsRemainReadableWithoutInventedRawResponse() throws {
        let data = Data(#"{"date":815000000,"heartRate":90,"sqi":0.74,"rmssd":56.6,"sdnn":56.4,"breathingRate":32.1}"#.utf8)
        let result = try JSONDecoder().decode(PhysMeasurement.self, from: data)
        XCTAssertEqual(result.heartRate, 90)
        XCTAssertNil(result.originalResponse)
        XCTAssertTrue(result.fieldGroups.isEmpty)
    }
    func testInvalidSummaryValuesArePreservedInCompleteData() throws {
        let result = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{"hr":400,"sqi":-1,"hrv":{"rmssd":-5}},"bp":null}}"#.utf8))
        XCTAssertNil(result.heartRate)
        XCTAssertNil(result.sqi)
        let fields = result.fieldGroups.flatMap(\.fields)
        XCTAssertTrue(fields.contains { $0.id == "/data/cardiac/hr" && $0.value == "400" })
        XCTAssertTrue(fields.contains { $0.id == "/data/bp" && $0.kind == "空值" })
    }
    func testEmptyAndFalseResponsesDoNotBecomeHealthClaims() throws {
        let empty = try PhysMeasurement(data: Data(#"{"data":{"cardiac":{},"liveness":{"is_live":false},"audio":null}}"#.utf8))
        XCTAssertFalse(empty.suitableForAdvice)
        XCTAssertEqual(empty.fieldGroups.flatMap(\.fields).count, 3)
        XCTAssertTrue(empty.fieldGroups.flatMap(\.fields).contains { $0.value == "false（否）" })
    }
}
