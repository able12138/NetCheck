import SwiftUI

/// 网络健康评分：把分散的检测项汇总成一个「体检分」，供首页展示
struct HealthItem: Identifiable {
    var id: String
    var title: String
    var score: Int          // 0-100
    var weight: Double
    var measured: Bool
    var detail: String
    var advice: String

    var ok: Bool { score >= 75 }
    var warn: Bool { score >= 55 && score < 75 }
}

struct HealthReport {
    var score: Int = 0
    var grade: String = "未体检"
    var gradeColor: Color = .secondary
    var summary: String = "点击「一键体检」，10 余秒内完成无线、延迟、出口与带宽四项检查。"
    var items: [HealthItem] = []
    var problems: [String] = []
    var hasData: Bool = false
}

enum HealthScore {

    static func grade(_ score: Int) -> (String, Color) {
        switch score {
        case 90...: return ("优秀", .green)
        case 75..<90: return ("良好", .green)
        case 60..<75: return ("一般", .yellow)
        default: return ("需优化", .red)
        }
    }

    /// 下行速度分档（按国内家庭宽带实际情况放宽：30–50 Mbps 已属可用）
    static func downloadScore(_ mbps: Double) -> Int {
        switch mbps {
        case 200...: return 100
        case 100..<200: return 96
        case 50..<100: return 92
        case 30..<50: return 85
        case 15..<30: return 72
        case 8..<15: return 56
        case 3..<8: return 40
        case 0.1..<3: return 26
        default: return 0
        }
    }

    static func uploadScore(_ mbps: Double) -> Int {
        switch mbps {
        case 50...: return 100
        case 20..<50: return 90
        case 10..<20: return 74
        case 5..<10: return 58
        case 0.1..<5: return 40
        default: return 0
        }
    }

    static func latencyScore(_ ms: Double) -> Int {
        switch ms {
        case 0: return 0
        case ..<20: return 100
        case 20..<40: return 90
        case 40..<70: return 75
        case 70..<120: return 55
        case 120..<200: return 35
        default: return 20
        }
    }

    /// 汇总评分。未测项目不参与加权（如实标注，不虚高）
    @MainActor
    static func evaluate(wifi: WiFiEngine,
                         net: NetInfoCenter,
                         lastRun: SpeedRun?,
                         lanCount: Int) -> HealthReport {
        var r = HealthReport()
        let link = wifi.link
        var items: [HealthItem] = []

        // 1 无线信号（有线时不参与）
        if link.powerOn && link.channel > 0 {
            let s = WiFiLink.score(rssi: link.rssi)
            items.append(HealthItem(
                id: "wifi_signal", title: "无线信号", score: s, weight: 1.2, measured: true,
                detail: "\(link.rssi) dBm（\(WiFiLink.qualityLabel(rssi: link.rssi).0)）· 信噪比 \(link.snr) dB",
                advice: s >= 75 ? "信号良好，链路余量充足" : "建议靠近路由器，或把路由器移出弱电箱/金属遮挡"))
        }

        // 2 信道环境
        if !wifi.neighbors.isEmpty, link.powerOn {
            let sameBand = wifi.neighbors.filter { $0.band == link.band && $0.channel > 0 }
            let crowded = sameBand.filter { abs($0.channel - link.channel) <= 4 && $0.rssi > -75 }.count
            let s = max(20, 100 - crowded * 15)
            items.append(HealthItem(
                id: "wifi_channel", title: "信道环境", score: s, weight: 0.8, measured: true,
                detail: "\(link.band) 信道 \(link.channel)，同频拥挤 AP \(crowded) 个",
                advice: crowded >= 3 ? "信道偏挤，建议按 Wi-Fi 页的建议切换信道" : "信道环境可用"))
        }

        // 3 加密安全
        if link.powerOn && !link.security.isEmpty {
            let s = link.security.contains("开放") || link.security.contains("WEP") ? 20 : 100
            items.append(HealthItem(
                id: "wifi_security", title: "网络安全", score: s, weight: 0.6, measured: true,
                detail: "加密方式：\(link.security)",
                advice: s < 75 ? "存在明文/WEP 风险，建议改用 WPA2/WPA3 个人版" : "加密方式合规"))
        }

        // 4 延迟与丢包
        let dnsProbes = net.probes.filter { $0.group.contains("DNS") && $0.ok }
        if !dnsProbes.isEmpty {
            let avg = dnsProbes.map { $0.avgMs }.reduce(0, +) / Double(dnsProbes.count)
            let loss = dnsProbes.map { $0.lossPct }.max() ?? 0
            items.append(HealthItem(
                id: "latency", title: "网络延迟", score: latencyScore(avg), weight: 1.0, measured: true,
                detail: String(format: "国内公共 DNS 平均 %.1f ms", avg),
                advice: avg < 40 ? "出口延迟正常" : "延迟偏高，常见于出口拥塞或走了代理/隧道"))
            items.append(HealthItem(
                id: "loss", title: "丢包率", score: loss < 1 ? 100 : loss < 5 ? 70 : 35, weight: 0.6, measured: true,
                detail: String(format: "最大丢包 %.0f%%", loss),
                advice: loss < 1 ? "无丢包" : "存在丢包，建议检查网线与路由器负载"))
        }

        // 5 宽带速度（取最近一次测速结果）
        if let run = lastRun, run.downMbps > 0 {
            items.append(HealthItem(
                id: "down", title: "宽带下行", score: downloadScore(run.downMbps), weight: 1.4, measured: true,
                detail: "\(fmtMbps(run.downMbps)) Mbps · \(run.node)",
                advice: downloadScore(run.downMbps) >= 75
                    ? "下行满足日常使用（高清视频、视频会议、大文件外发）"
                    : "下行偏低：可换节点复核，并确认是否有其他程序占用带宽"))
            if run.upMbps > 0 {
                items.append(HealthItem(
                    id: "up", title: "宽带上行", score: uploadScore(run.upMbps), weight: 0.6, measured: true,
                    detail: "\(fmtMbps(run.upMbps)) Mbps",
                    advice: "上行影响视频通话与外发文件体验"))
            }
        }

        // 6 出口/代理
        let hasTunnel = !net.profile.vpnInterfaces.isEmpty
        let hasProxy = !net.profile.proxyInfo.contains("未启用")
        if !net.profile.exitIPList.isEmpty || hasTunnel || hasProxy {
            var notes: [String] = []
            if !net.profile.exitIPList.isEmpty { notes.append("出口 \(net.profile.exitIPList.joined(separator: "/"))") }
            if hasTunnel { notes.append("隧道 \(net.profile.vpnInterfaces.joined(separator: "/"))") }
            if hasProxy { notes.append(net.profile.proxyInfo) }
            let s = (hasTunnel || hasProxy) ? 80 : 100
            items.append(HealthItem(
                id: "exit", title: "出口与代理", score: s, weight: 0.4, measured: true,
                detail: notes.joined(separator: " · "),
                advice: (hasTunnel || hasProxy) ? "存在隧道/代理，测速结果可能受其影响" : "直连出口，无代理干扰"))
        }

        // 局域网（信息项，不计权重）
        if lanCount > 0 {
            items.append(HealthItem(
                id: "lan", title: "局域网设备", score: 100, weight: 0.0, measured: true,
                detail: "发现 \(lanCount) 台设备",
                advice: "可在「局域网设备」页查看明细与开放端口"))
        }

        let weighted = items.filter { $0.weight > 0 }
        let totalW = weighted.reduce(0) { $0 + $1.weight }
        let sum = weighted.reduce(0.0) { $0 + Double($1.score) * $1.weight }
        r.score = totalW > 0 ? Int((sum / totalW).rounded()) : 0
        r.items = items
        r.hasData = totalW > 0
        if r.hasData { r.grade = grade(r.score).0; r.gradeColor = grade(r.score).1 }

        r.problems = weighted.filter { !$0.ok }.sorted { $0.score < $1.score }.map { "\($0.title)：\($0.advice)" }
        if r.hasData {
            if r.problems.isEmpty {
                r.summary = "网络各项指标正常，日常使用无需处理。"
            } else {
                r.summary = "发现 \(r.problems.count) 项可优化：" + r.problems.prefix(2).joined(separator: "；")
            }
        }
        return r
    }
}
