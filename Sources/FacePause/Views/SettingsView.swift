import SwiftUI
import FaceCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @LocalViewState<String> private var keyID = ""
    @LocalViewState<String> private var secret = ""
    @LocalViewState<String> private var status = ""
    @LocalViewState<Bool> private var testing = false
    var body: some View {
        Form {
            Section("定时与主动检测") {
                Toggle("启用定时检测", isOn: $preferences.enabled)
                Picker("检测间隔", selection: $preferences.interval) {
                    ForEach([15, 30, 60, 120, 180], id: \.self) { value in Text("每 \(value) 分钟").tag(value) }
                }
                Stepper("每日最多 \(preferences.dailyLimit) 次分析", value: $preferences.dailyLimit, in: 1...24)
                HStack {
                    Picker("开始时间", selection: $preferences.startHour) {
                        ForEach(0..<preferences.endHour, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Picker("结束时间", selection: $preferences.endHour) {
                        ForEach((preferences.startHour + 1)...24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                }
                Toggle("录完自动上传并扣费", isOn: $preferences.automaticUpload)
                Text("开启表示允许按以上频率将面部视频上传 FacePhys，并消耗账户额度。每日次数包含失败或超时的提交；次数上限不是金额上限，单次费用取决于 Key 的字段集。")
                    .font(.caption)
                Text("\(model.scheduleSummary) · 今日已使用 \(preferences.usedToday) / \(preferences.dailyLimit) 次")
                    .font(.caption).foregroundStyle(Theme.red)
                Text("以这台 Mac 的时区为准。锁屏、睡眠、面部未入镜时跳过；唤醒后重新计时，不补跑。录制前有 5 秒倒计时，可以取消。")
                    .font(.caption)
                Button("预览顶部灵动岛效果") { model.previewIsland() }
            }
            Section("连接 FacePhys") {
                Text("Secret 只保存在这台 Mac 的钥匙串中。无需发到聊天里，也不会写入项目文件。")
                    .font(.callout)
                Button("授权钥匙串访问") {
                    do {
                        guard try KeychainStore.authorize() != nil else { status = "尚未保存 Key，请先填写并保存。"; return }
                        model.refreshCredentials()
                        status = "钥匙串访问已恢复。如果系统询问，请选择“始终允许”，以后启动和检测无需反复输入密码。"
                    } catch { status = error.localizedDescription }
                }.disabled(testing || model.busy)
                Text("正常启动和后台检测只尝试静默读取，不弹密码窗口。切换到固定签名后的首次授权，请在系统窗口选择“始终允许”。")
                    .font(.caption)
                TextField("Key ID", text: $keyID)
                SecureField("Secret", text: $secret)
                HStack {
                    Button("保存到钥匙串") {
                        do {
                            try KeychainStore.save(Credentials(keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines), secret: secret.trimmingCharacters(in: .whitespacesAndNewlines)))
                            secret = ""; model.refreshCredentials(); status = "已保存。可测试连接，测试不提交视频。"
                        } catch { status = error.localizedDescription }
                    }.disabled(keyID.isEmpty || secret.isEmpty || testing || model.busy)
                    Button("测试已保存的连接") {
                        testing = true
                        Task {
                            defer { testing = false }
                            do {
                                guard let credentials = try KeychainStore.load() else { throw FaceError.message("请先保存 Key。") }
                                try await FacePhysClient(credentials: credentials).authenticate()
                                status = "认证成功；未上传视频，未提交计费分析。"
                                model.credentialState = "认证通过"
                            } catch { status = error is URLError ? "网络连接失败，请稍后再试。" : error.localizedDescription }
                        }
                    }.disabled(testing || model.busy)
                    if testing { ProgressView().controlSize(.small) }
                }
                Text(status).font(.caption).textSelection(.enabled)
                Link("打开 FacePhys Key 控制台", destination: URL(string: "https://www.facephys.com/console/skills")!)
            }
            DeepSeekSettingsSection(store: model.deepSeek, disabled: model.active || model.uiTest)
            Section("数据与采集") {
                CameraPermissionView(camera: model.camera)
                Text("关闭主窗口后仍在菜单栏运行。每次只采集约 30 秒，不显示摄像头画面、不录声音；结束即关闭摄像头。Mac 的绿色摄像头指示灯正常显示。")
                Text("本地记录包括原始视频、转换后的 MP4、完整原始响应和解析结果。文件不会自动删除，可从主窗口“打开本地记录”自行管理。")
                Text("FacePhys 按 Key 配置的字段集收费。App 展示实际返回的全部字段和分析文字；这不会自动修改 Key 的字段集或收费标准。")
            }.font(.callout)
        }.formStyle(.grouped).scrollContentBackground(.hidden).padding(10).frame(minWidth: 580, minHeight: 650)
            .background(Theme.paper).foregroundStyle(Theme.ink).tint(Theme.red)
    }
}

private struct DeepSeekSettingsSection: View {
    @ObservedObject var store: DeepSeekStore
    let disabled: Bool
    @LocalViewState<String> private var apiKey = ""
    @LocalViewState<String> private var status = ""
    @LocalViewState<Bool> private var testing = false
    var body: some View {
        Section("DeepSeek 数据解读") {
            Text("模型固定为 deepseek-flash · \(store.credentialState)").font(.callout)
            Text("API Key 仅存本机钥匙串。结果页手动点击生成后，将筛选的数值指标发给 DeepSeek，按文本用量计费；不发送视频、身份属性、凭据或 FacePhys 计费信息。")
                .font(.caption)
            SecureField("DeepSeek API Key", text: $apiKey)
            HStack {
                Button("保存 DeepSeek Key") {
                    do {
                        try KeychainStore.saveDeepSeek(apiKey)
                        apiKey = ""; store.refreshCredentials(); status = "已保存。可到结果页生成解读。"
                    } catch { status = error.localizedDescription }
                }.disabled(apiKey.isEmpty || testing || disabled)
                Button("测试 DeepSeek 连接") {
                    testing = true
                    Task {
                        defer { testing = false }
                        do {
                            guard let key = try KeychainStore.loadDeepSeek() else {
                                throw FaceError.message("请先保存 DeepSeek Key。")
                            }
                            try await DeepSeekClient(apiKey: key).authenticate()
                            store.refreshCredentials(); status = "连接成功，deepseek-flash 可用；未生成内容，也未发送测量数据。"
                        } catch { status = error is URLError ? "DeepSeek 网络连接失败。" : error.localizedDescription }
                    }
                }.disabled(testing || disabled)
                if testing { ProgressView().controlSize(.small) }
            }
            Button("授权 DeepSeek 钥匙串访问") {
                do {
                    let saved = try KeychainStore.loadDeepSeek(interactive: true)
                    store.refreshCredentials()
                    status = saved == nil ? "尚未保存 DeepSeek Key。" : "已授权，之后会静默读取。"
                } catch { status = error.localizedDescription }
            }.disabled(testing || disabled)
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
            Link("DeepSeek 官方用量与余额", destination: URL(string: "https://platform.deepseek.com/usage")!)
        }
    }
}

private struct CameraPermissionView: View {
    @ObservedObject var camera: CameraService
    @LocalViewState<String> private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(permissionDescription)
            Button("检查 / 授权摄像头") {
                Task {
                    let allowed = await camera.authorizeCamera()
                    message = allowed ? "授权已保存；这一步没有打开摄像头或录制视频。" : "请到系统设置 → 隐私与安全性 → 摄像头中允许片刻。"
                }
            }
            if !message.isEmpty { Text(message).font(.caption) }
        }
    }
    private var permissionDescription: String {
        switch camera.permissionState {
        case .authorized: return "摄像头：已授权，正常启动和检测会复用"
        case .notDetermined: return "摄像头：首次使用需要允许一次"
        case .denied: return "摄像头：系统已拒绝，请到系统设置中修改"
        case .restricted: return "摄像头：此 Mac 限制了摄像头访问"
        @unknown default: return "摄像头：授权状态未知"
        }
    }
}
