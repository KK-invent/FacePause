import Foundation
import FaceCore
#if !FACEPAUSE_STANDALONE_TEST
import XCTest
#endif

final class ProviderReportsTests: XCTestCase {
    func testNestedReportPreservesEveryPartWithoutDuplicateSections() throws {
        let data = Data(#"{"data":{"llm_analysis":{"summary":"原文总结","diagnosis":"原文诊断","recommendations":["建议一","建议二"],"uncertainty":null}},"report_version":"v3"}"#.utf8)
        let reports = ProviderReports.extract(from: data)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].fields.count, 5)
        XCTAssertTrue(reports[0].fields.contains { $0.value == "原文诊断" })
        XCTAssertTrue(reports[0].fields.contains { $0.id == "/data/llm_analysis/recommendations/1" && $0.value == "建议二" })
    }
    func testNoReportIsNotReplacedByAppAdvice() {
        let data = Data(#"{"data":{"cardiac":{"hr":72},"analysis_version":"v3","analysis_time":30,"diagnosis":null}}"#.utf8)
        XCTAssertTrue(ProviderReports.extract(from: data).isEmpty)
    }
    func testLongTextIsNeverTruncated() throws {
        let text = String(repeating: "完整报告原文。\n", count: 2000)
        let data = try JSONSerialization.data(withJSONObject: ["data": ["diagnosis": text]])
        let reports = ProviderReports.extract(from: data)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].fields[0].value, text)
    }
    func testChineseAndRootReportsAreIncluded() {
        let data = Data(#"{"data":{"分析报告":"服务分析","建议":["甲","乙"]},"summary":"顶层总结"}"#.utf8)
        let reports = ProviderReports.extract(from: data)
        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(reports.flatMap(\.fields).count, 4)
    }
}
