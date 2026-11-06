import SwiftUI
import FaceCore

struct ProviderReportsView: View {
    let original: Data?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let original {
                let reports = ProviderReports.extract(from: original)
                if reports.isEmpty {
                    note("text.page.slash", "本次未返回可识别的分析报告文字。所有原始字段在“全部数据”中完整展示，App 不补写服务商报告。")
                } else {
                    note("quote.opening", "以下为服务商返回原文，包括其诊断或建议，不是 App 生成或核实的医疗结论。")
                    ForEach(reports) { report in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(report.title).font(.headline)
                                Spacer()
                                Text(report.id).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            }
                            ForEach(report.fields) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    if report.fields.count > 1 {
                                        Text(field.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.red)
                                    }
                                    Text(field.value).font(.callout).lineSpacing(3).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .outlined(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            } else {
                note("clock.arrow.circlepath", "这条旧记录未保存原始响应，无法确认服务当时是否返回了分析文字。升级后的检测会保留并显示。")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func note(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
