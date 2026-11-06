# FacePause 片刻 接手与优化说明

更新日期：2026-10-31。当前版本：0.5.0，构建号 9，新增用户明确授权的 DeepSeek 数据解读。v0.4 已修复计费字段、重做界面，并修正后台钥匙串读取会弹窗的问题，详见 `VALIDATION.md`。

## v0.5 新增授权与实现

用户明确要求把返回数据交给 `deepseek-flash` 分析并在 app 展示，提供了 Key。沿用原生架构，Key 存独立钥匙串条目，未放入源码或 App 包。默认手动生成，未增加定时自动 DeepSeek 调用。

`FaceCore/DeepSeekAnalysis.swift` 负责最小化数值输入、提示词、报告结构与原始响应绑定；`FaceCore/DeepSeekClient.swift` 负责官方接口、固定模型、安全错误和完整性检查；`Stores/DeepSeekStore.swift` 负责防重复点击、取消、结果切换与缓存；`Views/DeepSeekAnalysisView.swift` 为结果页默认页签。报告随记录保存为 `deepseek-analysis.json`，重新生成会额外计费，失败不自动重试。

官方模型列表已使用用户 Key 验证，HTTP 200 且包含 `deepseek-flash`。新增8项离线测试，总计36项。真实调用与正式安装状态以 `VALIDATION.md` 新记录为准。

本地凭据部署可显式启动应用并带 `--import-deepseek-key-stdin`，从标准输入内存管道读取 Key，由正式签名 app 写钥匙串；不得把值放入命令行参数、日志或项目文件。`--deepseek-analyze-latest-once` 仅用于明确授权的单次真实验收，已有缓存则跳过；两者在 UI 测试模式均禁用。不得把这些标志加入普通启动脚本。

最终验收注意：同一构建重启可读取DeepSeek Key；再次改代码构建后仍出现待授权，与已有FacePhys问题一致。当前报告已生成、可恢复阅读，但新调用需用户在设置里完成对应钥匙串授权。不要宣称跨构建授权已解决，也不要修改系统信任或扩大钥匙串访问范围绕过。

这是一个已经安装、可以运行并完成真实 FacePhys 检测的 macOS 原生 App。请在现有项目上继续优化，优先修正已知问题，保持轻量，不从头重写。当前最明确的缺陷是计费字段适配遗漏；授权持久化、程序坞入口和完整数据保存已经修好，不要回退。

## 从哪里开始

- 项目根目录：本文件所在目录；当前机器为 `~/Desktop/Design/FacePause`。
- 正式安装：`/Applications/FacePause.app`。`dist/FacePause.app` 是项目构建产物。
- 通用协作规则：先读取 `~/.codex/AGENTS.md`，以用户最新指令为准。本次不要使用子 agent。
- 先读 `README.md`、本文件，再看对应源文件。`VALIDATION.md` 按版本保留历史记录，其中早期“尚未接通”等状态已经被后续实际结果取代。
- Git 已初始化，但交接时源码仍主要处于未跟踪状态，没有可依赖的提交基线。先保护现有源码，不要执行会清掉当前文件的 reset/clean，也不要把运行数据和钥匙串材料纳入版本库。

这份说明不含 API Key、Secret、签名私钥、账号标识、真实视频或个人测量值。开发与测试优先使用合成数据；不要为了了解项目去导出用户凭据或上传其录像。

## 已确定的产品要求

1. 菜单栏和程序坞同时显示，正式应用能在“应用程序”中找到。启动或点击程序坞图标打开主窗口；关闭主窗口仍继续常驻，退出才停止运行。
2. 支持手动检测和定时主动检测。录制时不显示摄像头画面，只在屏幕顶部用类似灵动岛的胶囊浮层显示提醒、倒计时、进度和结果；系统绿色摄像头指示灯正常保留。
3. 采集约 30 秒无声视频。开始前倒计时 5 秒，可取消；本地检查单人面部入镜，采集结束关闭摄像头。
4. 用户已允许既定计划自动上传 FacePhys 并扣费，并选择每 60 分钟。当前默认每日最多 6 次、09:00–22:00；实际运行值以当前设置为准，不要用文档默认值覆盖用户后续修改。
5. 必须展示服务实际返回的全部数据，不能只保留四个概览指标。未知字段、数组每个元素、0、false、null 和空容器都要保留。
6. 服务返回的诊断、分析、总结或建议原文要单独显示，与 App 本地规则提示分开。没有服务商报告时不要冒充服务商生成报告。
7. 用户不希望每次启动或检测都重新输钥匙串密码、重新批准摄像头。已经建立固定签名身份，并实测更新后授权延续。

改变检测频率、次数上限、Key 字段集、上传对象或新增其他 AI 服务，可能改变成本或数据流向，不属于普通界面优化。不要扩大已授权范围，也不要对同一既有授权反复确认。开发验证优先离线；不要把普通测试变成重复的真实收费调用。

## 当前实现

技术栈为 SwiftUI、AppKit、AVFoundation、Vision、CryptoKit 和 Security；没有第三方运行时依赖，不使用 Electron、WebView 外壳或 FacePhys CLI/MCP。

目标平台写为 macOS 14+；目前实际验证环境为 Apple Silicon、macOS 27.0.1、Swift 6.4 Command Line Tools。尚未完成 Intel、其他系统版本或 Apple Developer ID 公证验证，不能直接宣称可公开分发。

核心流程：

```text
手动 / 定时触发
→ 5 秒可取消提醒
→ 检查已有摄像头授权，仅首次未决定时请求
→ 本地单人面部预检
→ 约 30 秒静音采集
→ 检查采集中入镜比例、转换 MP4、关闭摄像头
→ 自动授权或本次明确确认
→ 预留每日分析次数
→ 验证 Key → 获取上传地址 → PUT 视频 → V3 分析
→ 先保存完整响应，再解析摘要与报告
→ 浮层反馈 / 主窗口完整结果
```

默认视频为约 720p、30 fps、H.264。预检无清晰单人面部时跳过；采集中有效面部采样不足 60% 时不上传。这个检查不验证身份，也不保证生理估计准确。

锁屏、睡眠、会话切换、正在检测或有待处理视频时跳过。唤醒后重新计时，不补跑错过的任务。每日次数是提交预留/尝试上限，失败或超时也占一次；它不是金额上限。云端处理失败或状态不明时暂停定时任务，不自动重试。

## 代码入口

下表路径相对于项目根目录。

| 入口 | 责任 |
|---|---|
| `Sources/FacePause/App/FacePauseApp.swift` | 程序坞、菜单栏、启动与重新打开行为 |
| `Sources/FacePause/Stores/AppModel.swift` | 检测状态流转、定时触发、取消、额度预留、上传和结果恢复 |
| `Sources/FacePause/Stores/Preferences.swift` | 持久化设置、每日次数；测试使用独立偏好域 |
| `Sources/FaceCore/SchedulePolicy.swift` | 工作时段、下一次时间、每日次数规则 |
| `Sources/FacePause/Services/SessionMonitor.swift` | 锁屏、睡眠与会话状态 |
| `Sources/FacePause/Services/CameraService.swift` | 摄像头权限、Vision 入镜检查、录像与转换 |
| `Sources/FaceCore/FacePhysClient.swift` | HMAC、认证、上传、分析、防重复提交和完整响应回调 |
| `Sources/FaceCore/Measurement.swift` | 概览解析、质量门槛、本地提示、原始响应保存模型 |
| `Sources/FaceCore/FullResponse.swift` | 无遗漏字段展开、搜索所需数据、原始 JSON 文本 |
| `Sources/FaceCore/ProviderReports.swift` | 服务商报告字段识别，目前是键名启发式匹配 |
| `Sources/FacePause/Views/` | ResultsView、AllFieldsView、ProviderReportsView 分别负责摘要、全部字段与服务商报告界面 |
| `Sources/FacePause/Services/AppWindows.swift`、`Sources/FacePause/Views/IslandView.swift` | 主窗口、设置窗口和不抢键盘焦点的顶部浮层 |
| `Sources/FacePause/Services/KeychainStore.swift` | 静默钥匙串读取、内存缓存、用户主动授权 |
| `Sources/FacePause/Services/LocalFiles.swift` | 视频、完整响应、解析结果和最近记录恢复 |
| `Support/Assets/`、`Sources/FacePause/Views/BrandIcon.swift` | Logo、ICNS 和单色菜单栏图标 |

## 签名与授权 不要破坏

应用标识符保持 `local.facepause.mac`。当前 `LSUIElement=false`，激活策略是 `.regular`；不要改回纯菜单栏 `.accessory` 模式，否则程序坞入口会再次消失。

之前反复请求权限的主要根因是 ad-hoc 签名把身份绑定到每次变化的程序哈希。现在使用个人登录钥匙串中的固定本机证书，designated requirement 同时绑定应用标识符和叶证书指纹。已实测：程序文件哈希改变，但身份要求不变；重新构建和启动后，钥匙串和摄像头授权保留。

- 必须通过 `script/sign_app.sh` 和现有构建脚本签名，禁止退回 `codesign --sign -`。
- 本机公开签名配置在 `~/Library/Application Support/FacePause/Signing/identity.json`。签名私钥留在登录钥匙串；不得导出或放进项目。
- 当前机器已经建立身份，不要重新生成证书、随意改 bundle ID、重置 TCC、关闭 Gatekeeper、修改系统根信任或扩大钥匙串访问范围来“修权限”。
- 正常启动和后台读取禁止弹认证 UI；同一次运行复用内存缓存，锁屏/睡眠清除缓存，恢复后静默重读。交互式授权只由用户在设置中主动触发。
- 摄像头先读 `authorizationStatus`；只有 `.notDetermined` 才请求，`.authorized` 直接复用，拒绝或限制状态提供清晰提示。

本机签名用于本机开发使用，不等于 Apple Developer ID 公证。跨设备发布是独立任务，不要混为一谈。

## 数据与接口边界

正式记录目录为 `~/Library/Application Support/FacePause/Sessions/`。每次有独立子目录，包含原片、转换后视频、`response.json` 和 `result.json`。这个目录含个人视频与健康相关数据，不应复制到源码、日志、说明、外部 AI 或分享包。项目 `work/` 中也可能有本地检查材料，不要整目录打包。

`response.json` 按字节保存完整成功响应；`result.json` 含解析结果及可选原始响应。旧版记录没有原始响应，必须继续兼容并明确提示不能补回。复制和导出完整 JSON 不受搜索条件影响，也不应通过重新序列化损失数字精度。

没有自动删除录像。任何存储清理或保留期功能应先遵循用户的文件处理规则，不能顺手永久删除既有记录。

当前接口为 HTTPS 的认证、presign、存储 PUT、`/api/v3/video/process` 流程。签名使用时间戳的 HMAC-SHA256。分析请求包含 `confirmCharge`、稳定的 `idempotencyKey` 和视频 SHA-256；自动重试没有开启。幂等机制不等于可以任意反复调用付费接口。

认证头不发给视频存储域名，临时上传 URL 不写日志，重定向被拒绝。原始视频仅传 FacePhys。v0.5 用户授权将筛选后的数值结果发送 DeepSeek；该授权不包括其他大模型、视频转发或云同步。

## 优先优化顺序

### 第一优先 修正计费展示

这是已经确认的问题，尚未修复。

真实接口使用 `data.tokens_deducted` 和 `data.remaining_tokens`；`Measurement.swift` 目前主要读取旧名称 `points_deducted` / `remaining_points`，因此界面可能显示“未读取到标准计费字段”，但实际已经扣费。

建议优先兼容新字段，保留旧字段作为回退，并检查 `FullResponse.swift` 的中文标签。不要靠推算视频时长或字段数量冒充真实扣费回执，也不要改动已有原始响应。

使用合成数据即可验收，例如：

```json
{
  "data": {
    "cardiac": {"hr": 70, "sqi": 0.8},
    "tokens_deducted": 1234,
    "remaining_tokens": 5678
  }
}
```

预期：概览正确显示 1234 Token 与余额 5678；数值 0 不能当成缺失；旧字段仍兼容；完整原始响应不变。补充相应测试，不需要为此做真实收费检测。

### 第二优先 改善解读与信息层级

- 当前 SQI 达到 0.65 且有心率时，文案为“信号较清晰”。这是产品显示门槛，不是临床准确率；“67% 信号质量”不能被理解为 67% 正确率或健康分。建议明确指标含义，减少过度肯定的文案。
- 不要仅凭整体 SQI，给血压、血氧、心理评分等所有模块一起背书。模块自己的置信度也不能直接换算成正确概率。
- 约 30 秒片段的 HRV，尤其低频指标，不适合直接套用长记录参考标准。0 值要保留，但不应被写成“神经活动为零”或“完全放松”。
- 情绪、压力、睡眠、面部属性等必须保留“服务商模型输出”的来源，不包装成真实心理状态、人格或疾病诊断。
- 保留简洁概览，同时让完整数据易查、单位与中文解释易懂。不要为了简洁重新删掉原始字段或截断报告。
- `ProviderReports` 目前靠字段名识别报告，未命中不必然等于服务器绝对没有文字。可根据官方文档和脱敏结构完善识别；所有未知字段仍必须在完整数据中可见。

### 后续可选优化

- 历史记录浏览和同条件趋势对比。目前只自动恢复最近一次结果，没有完整历史浏览界面。
- 浮层多屏定位。当前使用 `NSScreen.screens.first`，不同显示器、刘海和全屏组合尚未全部实测。
- 定时语义。目前多处 `reschedule()` 会从当前时刻重新计算下一次时间，未持久化下次触发时刻。改善前应明确是“完成后间隔”还是固定时刻，不悄悄增加调用频率。
- 大量记录/长数组的性能、磁盘占用，以及安装更新失败后的恢复流程。不要以永久删除用户数据作为默认解决办法。

以上后续项是建议方向，不是已经确认的全部缺陷，也不要求一次全部做完。

## 构建 验证 安装

在项目根目录执行：

```sh
./script/test.sh                         # 离线测试，不录制、不上传、不扣费
./script/build_and_run.sh --ui-test       # 独立偏好，禁用定时与云端上传
./script/build_and_run.sh --sample        # 明确标记的合成完整结果
./script/build_and_run.sh --overlay-test  # 浮层视图的普通布局验收窗口
# UI 测试模式下可加 --layout-phase countdown|recording|analyzing 查看对应布局，不开摄像头、不联网
./script/build_and_run.sh --build-only    # 构建与固定签名，不安装、不启动
./script/build_and_run.sh --install       # 安装到 /Applications 并正常启动
```

注意：构建脚本会先结束当前运行的 FacePause，`--build-only` 也一样。执行前确认没有正在录制或上传，避免打断用户操作。普通 `run` / `--verify` 等模式会在应用已经安装时更新正式包，并以正常定时策略启动；UI 测试模式不会覆盖正式安装。

安装脚本先复制到暂存位置并验签，再保留旧包到 `work/app-update-backups/` 并切换。不要只改 `dist/` 就声称用户正在运行的 `/Applications/FacePause.app` 已更新。实际运行路径、版本与签名都要核对。

当前只有 Command Line Tools，没有完整 XCTest 环境。`script/test.sh` 调用同一组测试方法的独立运行器。**新增测试方法需要同步注册到 `Support/TestMain.swift`，否则该脚本不会自动发现新测试。**

`script/swift.sh` 在项目 `.build/` 内绕开本机遗留的新旧 PackageDescription 接口冲突，不改系统工具链。`Sources/FacePause/Views/ViewState.swift` 的 `LocalViewState` 别名用于避开当前 SDK 同名 State 宏插件缺失，未经确认不要把它当作无用封装删掉。

## 验收与交付

最近一轮离线测试为 36 项、0 失败；DeepSeek真实生成、报告保存及重启恢复已通过。早期已有真实摄像头采集、云端结果、完整响应恢复、取消操作和正式安装入口的验证。旧FacePhys钥匙串在后续构建仍会要求重新授权；固定签名相同不代表已解决该问题，以最新 `VALIDATION.md` 为准。

没有医学准确性验证，没有跨设备发布公证，也没有覆盖所有多屏/全屏组合。程序坞运行图标和应用程序入口已确认；不要把“运行时可见”说成“已永久固定”。未配置开机登录启动。

首轮建议完成计费字段修复，再做明确、可验证的界面改进。交付时说明改了什么、如何使用、哪些检查通过、尚有哪些限制；更新 README 与本次验收记录。不要把示例数据说成真实检测，也不要把代码写好等同于真实付费链路已复验。

## 官方资料

- [FacePhys Agent 指引](https://www.facephys.com/docs/agent.md)
- [FacePhys OpenAPI](https://www.facephys.com/openapi.json)
- [FacePhys 结果字段](https://www.facephys.com/console/docs?s=results)
- [FacePhys 计费说明](https://www.facephys.com/console/docs?s=billing)
- [Apple 代码签名与身份要求](https://developer.apple.com/library/archive/technotes/tn2206/)
- [Apple 摄像头授权状态](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:))

改变接口或对外说明价格、能力之前，再核实官方当前资料；不要把早期接入记录当作当前服务状态。
