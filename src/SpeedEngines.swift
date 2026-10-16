import Foundation

/// Ookla speedtest-go 引擎（本机已装 /usr/local/bin/speedtest）
enum OoklaEngine {

    static var binaryPath: String? { Shell.locate("speedtest") }
    static var available: Bool { binaryPath != nil }

    /// 列出可用节点（按国家码过滤）
    static func listServers(cnOnly: Bool) async -> [OoklaServer] {
        guard let bin = binaryPath else { return [] }
        var args = ["--list"]
        if cnOnly { args += ["--filter-cc=CN"] }
        let r = await Shell.run(bin, args, timeout: 90)
        return parseList(r.combined)
    }

    static func parseList(_ text: String) -> [OoklaServer] {
        var out: [OoklaServer] = []
        // [ 3633]    890.24km 31ms \tShanghai (China) by China Telecom
        let pattern = #"\[\s*(\d+)\]\s+([\d.]+)km\s+(\S+)\s+(.+?)\s+\(([^)]*)\)\s+by\s+(.+?)\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return out }
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges >= 7 else { continue }
            func g(_ i: Int) -> String {
                guard let r = Range(m.range(at: i), in: s) else { return "" }
                return String(s[r])
            }
            let latStr = g(3)
            let lat = latStr.lowercased().contains("timeout") ? -1 :
                (Double(latStr.replacingOccurrences(of: "ms", with: "")) ?? -1)
            out.append(OoklaServer(id: g(1), name: g(4), sponsor: g(6), cc: g(5),
                                   distanceKm: Double(g(2)) ?? 0, latencyMs: lat))
        }
        return out
    }

    /// 运行一次完整测速；serverID 为空则自动选点
    static func run(serverID: String?, download: Bool = true, upload: Bool = true,
                    progress: @escaping (String) -> Void,
                    token: ProcessToken? = nil) async -> SpeedRun? {
        guard let bin = binaryPath else { return nil }
        var args: [String] = []
        if let s = serverID, !s.isEmpty { args += ["-s", s] }
        if !download { args.append("--no-download") }
        if !upload { args.append("--no-upload") }
        args.append("--json")
        progress("正在与 Ookla 节点通信…（约 20–40 秒）")
        let r = await Shell.run(bin, args, timeout: 180, token: token)
        guard let data = r.combined.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var run = SpeedRun()
        run.engine = "Ookla (speedtest-go)"
        if let ui = obj["user_info"] as? [String: Any] {
            run.exitIP = ui["IP"] as? String ?? ""
            run.isp = ui["Isp"] as? String ?? ""
        }
        guard let servers = obj["servers"] as? [[String: Any]], let s = servers.first else { return nil }
        run.node = "\(s["sponsor"] as? String ?? "?") · \(s["name"] as? String ?? "?")"
        if let lat = s["latency"] as? Double, lat > 0 { run.pingMs = lat / 1_000_000 }
        if let j = s["jitter"] as? Double { run.jitterMs = j / 1_000_000 }
        if let dl = s["dl_speed"] as? Double { run.downMbps = dl * 8 / 1_000_000 }
        if let ul = s["ul_speed"] as? Double { run.upMbps = ul * 8 / 1_000_000 }
        if let pl = s["packet_loss"] as? [String: Any] {
            let sent = (pl["sent"] as? Double) ?? 0
            let maxv = (pl["max"] as? Double) ?? 0
            _ = sent
            _ = maxv
        }
        return run
    }
}

/// Apple 官方 networkQuality 引擎（零安装，测 Apple 边缘节点，含响应性）
enum NetworkQualityEngine {

    static var available: Bool { Shell.locate("networkQuality") != nil }

    static func run(progress: @escaping (String) -> Void, token: ProcessToken? = nil) async -> SpeedRun? {
        guard let bin = Shell.locate("networkQuality") else { return nil }
        progress("正在调用 Apple 官方网络质量测试…（约 20 秒）")
        let r = await Shell.run(bin, ["-v"], timeout: 120, token: token)
        let t = r.combined
        guard !t.isEmpty else { return nil }
        var run = SpeedRun()
        run.engine = "Apple networkQuality"
        run.note = "测 Apple 边缘节点（境外），响应性为官方特有指标"
        if let v = capture(t, #"Uplink capacity:\s*([\d.]+)"#) { run.upMbps = Double(v) ?? 0 }
        if let v = capture(t, #"Downlink capacity:\s*([\d.]+)"#) { run.downMbps = Double(v) ?? 0 }
        if let v = capture(t, #"Idle Latency:\s*([\d.]+)"#) { run.pingMs = Double(v) ?? 0 }
        if let v = capture(t, #"Responsiveness:\s*(\w+)\s*\(([\d.]+)"#) {
            run.note += "；响应性：\(v)"
        }
        if let v = capture(t, #"Responsiveness:\s*\w+\s*\(([\d.]+) milliseconds"#) {
            run.jitterMs = Double(v) ?? 0
        }
        run.node = "Apple 边缘节点"
        return run
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
