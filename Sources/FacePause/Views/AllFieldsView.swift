import SwiftUI
import UniformTypeIdentifiers
import FaceCore

struct AllFieldsView: View {
    let result: PhysMeasurement
    @LocalViewState<String> private var search = ""
    @LocalViewState<String> private var notice = ""
    @LocalViewState<Bool> private var showJSON = false

    var body: some View {
        if let original = result.originalResponse {
            let groups = result.fieldGroups
            let total = groups.reduce(0) { $0 + $1.fields.count }
            let filtered = filteredGroups(groups)
            let count = filtered.reduce(0) { $0 + $1.fields.count }
            VStack(alignment: .leading, spacing: 14) {
                Text("所有已返回模块逐项展开，包括数组中的每个数据点；保留原始字段名与数值，未知新字段也会展示。null 表示服务返回空值，未出现的模块表示本次没有返回。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Label("血压、血氧、心理评分、情绪和面部属性等为 FacePhys 模型输出，未经确认；这里原样展示，不作为诊断或个人特征的认定。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        TextField("搜索名称、字段路径或数值", text: $search).textFieldStyle(.plain)
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).help("清除搜索")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .outlined(Capsule())
                    Text("\(count)/\(total)").font(.caption.monospacedDigit())
                    Button("复制 JSON") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(FullResponse.rawText(original), forType: .string)
                        notice = "已复制完整响应（不受搜索条件影响）"
                    }.buttonStyle(PillButtonStyle(prominent: false, compact: true)).help("复制完整原始响应")
                    Button("导出…") { export(original) }.buttonStyle(PillButtonStyle(prominent: false, compact: true)).help("导出完整原始 JSON")
                }
                if !notice.isEmpty { Text(notice).font(.caption) }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { group in
                        Section {
                            ForEach(group.fields) { field in
                                HStack(alignment: .top, spacing: 18) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(field.label).font(.callout.weight(.medium))
                                        Text(field.id).font(.system(size: 10, design: .monospaced))
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }.frame(width: 220, alignment: .leading)
                                    Text(field.value.isEmpty ? "\"\"（空文本）" : field.value)
                                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(field.kind).font(.caption2).frame(width: 36, alignment: .trailing)
                                }.padding(.vertical, 10)
                                Rectangle().fill(Theme.ink).frame(height: 0.5)
                            }
                        } header: {
                            HStack {
                                Text(group.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(group.fields.count) 项").font(.caption)
                            }.padding(.top, 22).padding(.bottom, 6)
                        }
                    }
                    if filtered.isEmpty { Text("没有匹配字段，清除搜索即可查看全部。").padding(.vertical) }
                }
                DisclosureGroup("完整原始 JSON", isExpanded: $showJSON) {
                    ScrollView([.horizontal, .vertical]) {
                        Text(FullResponse.rawText(original)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 260).outlined(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        } else {
            Label("这是一条旧版精简记录：原始完整响应当时未保存，无法从这份记录补回其他字段。升级后的新检测会保存并展示全部返回数据。", systemImage: "info.circle")
                .font(.callout).foregroundStyle(Theme.red).padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.red, lineWidth: 1))
        }
    }
    private func filteredGroups(_ groups: [ResultGroup]) -> [ResultGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let fields = group.title.localizedCaseInsensitiveContains(query) ? group.fields : group.fields.filter {
                $0.id.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
            }
            guard !fields.isEmpty else { return nil }
            return ResultGroup(id: group.id, title: group.title, fields: fields)
        }
    }
    private func export(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FacePause-完整结果.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            notice = "完整 JSON 已导出"
        } catch { notice = "导出失败：" + error.localizedDescription }
    }
}
