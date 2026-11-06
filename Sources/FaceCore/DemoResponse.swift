import Foundation

enum DemoResponse {
    static let data = Data(#"""
    {
      "data": {
        "cardiac": {
          "hr":74.2,"sqi":0.82,
          "hr_list":[{"hr":74.9,"ts":0},{"hr":76.1,"ts":1},{"hr":76.6,"ts":2},{"hr":76.5,"ts":3},{"hr":76.0,"ts":4},{"hr":75.7,"ts":5},{"hr":75.7,"ts":6},{"hr":76.0,"ts":7},{"hr":76.2,"ts":8},{"hr":75.9,"ts":9},{"hr":74.9,"ts":10},{"hr":73.5,"ts":11},{"hr":71.9,"ts":12},{"hr":70.9,"ts":13},{"hr":70.7,"ts":14},{"hr":71.3,"ts":15},{"hr":72.3,"ts":16},{"hr":73.4,"ts":17},{"hr":74.0,"ts":18},{"hr":74.2,"ts":19},{"hr":74.2,"ts":20},{"hr":74.4,"ts":21},{"hr":75.1,"ts":22},{"hr":76.1,"ts":23},{"hr":77.1,"ts":24},{"hr":77.7,"ts":25},{"hr":77.5,"ts":26},{"hr":76.5,"ts":27},{"hr":74.9,"ts":28}],
          "hrv":{"ibi_mean":808.6,"rmssd":42.8,"sdnn":51.3,"breathing_rate":16.1,"pnn20":0.45,"pnn50":0.25,"LF":0.03,"HF":0.04,"LF/HF":0.75,"TP":0.08,"VLF":0.01,"sd1":30.3,"sd2":65.5}
        },
        "bp":{"sbp":118,"dbp":76,"confidence":0.42},
        "spo2":{"spo2":97.2,"confidence":0.35},
        "psych":{"ms":31,"mr":62,"mf":28,"sq":65,"mh":60,"mb":61,"con":67,"mab":65,"adp":61,"sra":60},
        "emotion":{"surface":{"Neutral":0.72,"Happy":0.2,"Surprise":0.08},"deep":{"Neutral":0.7},"dominant":"Neutral","dominant_confidence":0.72},
        "face_au":{"brow_furrow":0.01,"mouth_smile":0.13},
        "behavior":{"blink_rate":12.5,"perclos":0.03,"gaze_yaw":0.2,"gaze_pitch":-0.1},
        "appearance":{"age":{"value":29,"range":"25–35"},"gender":{"label":"演示分类","confidence":0.8}},
        "liveness":{"is_live":true,"liveness_score":0.81},
        "audio":null,
        "new_module":{"empty_values":[],"additional_text":"示例：新字段也会完整展示"},
        "llm_analysis":{"summary":"【演示报告】这里展示 FacePhys 实际返回的分析原文。当前文字只是界面示例，不是对使用者的诊断。","recommendations":["【演示建议一】服务商的多条建议逐条显示。","【演示建议二】长段文字不截断，原始响应同时保存在本机。"],"diagnosis":null},
        "tokens_deducted":252000,"remaining_tokens":1000000
      },
      "message":"Synthetic demonstration — no request was made",
      "video_duration":29.1,
      "request_id":"demo-only"
    }
    """#.utf8)
}
