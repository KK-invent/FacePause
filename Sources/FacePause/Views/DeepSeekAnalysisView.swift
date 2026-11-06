import SwiftUI
import FaceCore

struct DeepSeekAnalysisView: View {
    @ObservedObject var store: DeepSeekStore
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DeepSeek 解读").font(.title3.weight(.semibold))
                    Text("deepseek-flash · 单次测量的参考解读").font(.caption)
                }
                Spacer()
                if store.report != nil {
                    Button("复制解读") { copyReport() }
                        .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                }
            }
            Text("点击生成会把本次筛选后的数值指标发送给 DeepSeek，消耗其账户的文本额度。视频、身份属性、账号信息和 FacePhys 计费信息不发送；不会自动调用。")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            if let reason = store.unavailableReason {
                Label(reason, systemImage: "info.circle").font(.callout)
            } else {
                HStack(spacing: 12) {
                    if store.canAnalyze {
                        Button(store.report == nil ? "生成本次解读" : "重新生成 · 再次计费") { store.generate() }
                            .buttonStyle(PillButtonStyle(compact: true)).disabled(store.isAnalyzing)
                    } else {
                        Button("连接 DeepSeek", action: openSettings).buttonStyle(PillButtonStyle(compact: true))
                    }
                    if store.isAnalyzing {
                        ProgressView().controlSize(.small)
                        Text("正在解读，通常需数十秒…").font(.caption)
                    }
                }
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            }
            if let report = store.report {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.content.summary).font(.system(size: 19, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Theme.ink)
                    Text("数据质量").font(.caption.weight(.semibold))
                    Text(report.content.quality).font(.callout).lineSpacing(4)
                }.padding(20).outlined(RoundedRectangle(cornerRadius: 18))
                ForEach(Array(report.content.findings.enumerated()), id: \.offset) { index, finding in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", index + 1)).font(.caption.monospaced()).foregroundStyle(Theme.red)
                            Text(finding.title).font(.headline)
                        }
                        Text(finding.evidence).font(.caption).lineSpacing(3)
                        Text(finding.interpretation).font(.callout).lineSpacing(4)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
                bulletSection("解读局限", items: report.content.limitations)
                bulletSection("下一步建议", items: report.content.suggestions)
                Text(metadata(report)).font(.caption2)
                Text("来源：DeepSeek 生成，可能有误；与 FacePhys 原始报告、本地规则提示分别展示，不作诊断。")
                    .font(.caption2).fixedSize(horizontal: false, vertical: true)
            } else if store.unavailableReason == nil && !store.isAnalyzing {
                Text("生成后，这里会显示总体结论、关键指标依据、局限和具体建议，并随本次记录保存在本机。")
                    .font(.callout).padding(.vertical, 10)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("·").foregroundStyle(Theme.red)
                    Text(item).font(.callout).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(.top, 8)
    }
    private func metadata(_ report: DeepSeekReport) -> String {
        var text = "生成于 " + report.createdAt.formatted(date: .abbreviated, time: .shortened)
        if let total = report.usage?.total_tokens { text += " · DeepSeek 文本用量 \(total) tokens" }
        return text
    }
    private func copyReport() {
        guard let report = store.report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("DeepSeek 解读 · \(report.requestedModel)\n\n" + report.content.plainText
                                      + "\n\n仅供参考，不作诊断。", forType: .string)
    }
}
