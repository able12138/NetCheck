import Foundation

/// 本机网络信息与国内场景诊断（接口/网关/DNS/代理/VPN/公网出口/延迟矩阵）
@MainActor
final class NetInfoCenter: ObservableObject {

    @Published var profile = NetProfile()
    @Published var probes: [LatencyProbe] = []
    @Published var busy = false
    @Published var status = "就绪"
    @Published var exitChecking = false

    // MARK: 基础信息

    func refreshProfile() async {
        busy = true
        status = "读取本机网络配置…"
        var p = NetProfile()
        p.interfaces = await loadInterfaces()
        p.gateway = await gateway()
        p.dns = await dnsServers()
        p.proxyInfo = await proxyDescription()
        p.vpnInterfaces = p.interfaces.filter { $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") || $0.name.hasPrefix("tap") || $0.name.hasPrefix("tun") }.map { $0.name }
        profile = p
        busy = false
        status = "就绪"
    }

    private func loadInterfaces() async -> [NetInterface] {
        let r = await Shell.run("/sbin/ifconfig", ["-a"], timeout: 15)
        var list: [NetInterface] = []
        var cur: NetInterface?
        for raw in r.out.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if !line.hasPrefix("\t") && !line.hasPrefix(" ") && line.contains(": flags=") {
                if let c = cur { list.append(c) }
                let name = String(line.split(separator: ":").first ?? "")
                let up = line.contains("UP")
                cur = NetInterface(name: name, kind: kindOf(name), isUp: up)
            } else if var c = cur {
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("inet ") {
                    let parts = s.split(separator: " ")
                    if parts.count >= 2 { c.ipv4 = String(parts[1]) }
                } else if s.hasPrefix("inet6 ") {
                    let parts = s.split(separator: " ")
                    if parts.count >= 2, !c.ipv6.contains("%") { c.ipv6 = String(parts[1]) }
                } else if s.hasPrefix("ether ") {
                    let parts = s.split(separator: " ")
                    if parts.count >= 2 { c.mac = String(parts[1]) }
                }
                cur = c
            }
        }
        if let c = cur { list.append(c) }
        // 只保留有实际意义的接口：有 IPv4 的物理/桥接口 + 有 IPv4 的隧道口
        let keepPrefixes = ["en", "bridge", "ppp", "ipsec", "tun", "tap", "utun"]
        return list.filter { i in
            guard i.isUp, keepPrefixes.contains(where: { i.name.hasPrefix($0) }) else { return false }
            return !i.ipv4.isEmpty
        }
    }

    private func kindOf(_ name: String) -> String {
        if name.hasPrefix("en") { return name == "en0" ? "Wi-Fi / 以太网" : "网络接口" }
        if name.hasPrefix("utun") { return "VPN / 隧道" }
        if name.hasPrefix("bridge") { return "桥接" }
        if name.hasPrefix("lo") { return "回环" }
        return "其他"
    }

    func gateway() async -> String {
        let r = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 10)
        for line in r.out.split(separator: "\n") where line.contains("gateway:") {
            return line.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    func dnsServers() async -> [String] {
        let r = await Shell.run("/usr/sbin/scutil", ["--dns"], timeout: 10)
        var out: [String] = []
        for line in r.out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("nameserver["), let c = s.firstIndex(of: ":") {
                let v = s[s.index(after: c)...].trimmingCharacters(in: .whitespaces)
                if !out.contains(v) { out.append(v) }
            }
        }
        return out
    }

    func proxyDescription() async -> String {
        let r = await Shell.run("/usr/sbin/scutil", ["--proxy"], timeout: 10)
        var parts: [String] = []
        var enabled = false
        for line in r.out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("Enabled") && s.contains("1") { enabled = true }
            if s.contains("ProxyAutoConfigEnable : 1") { parts.append("自动代理(PAC)") }
            if s.contains("SOCKSEnable : 1") { parts.append("SOCKS") }
            if s.contains("HTTPEnable : 1") { parts.append("HTTP") }
            if s.contains("HTTPSEnable : 1") { parts.append("HTTPS") }
        }
        if !enabled && parts.isEmpty { return "未启用系统代理" }
        return parts.isEmpty ? "已配置（详见系统网络设置）" : "已启用：" + parts.joined(separator: " / ")
    }

    // MARK: 公网出口（国内接口优先，并检测多出口）

    func checkExits(rounds: Int = 3) async {
        exitChecking = true
        status = "正在查询公网出口…"
        var samples: [ExitSample] = []
        for _ in 0 ..< rounds {
            if let s = await queryExit(plain: true) { samples.append(s) }
        }
        if let s = await queryExit(plain: false) { samples.append(s) }
        profile.exitSamples = samples
        profile.exitIPList = Array(Set(samples.map { $0.ip })).sorted()
        exitChecking = false
        status = "就绪"
    }

    private func queryExit(plain: Bool) async -> ExitSample? {
        if plain {
            guard let ip = await plainText(url: "http://ip.3322.net") else { return nil }
            return ExitSample(ip: ip, region: "", isp: "", source: "ip.3322.net")
        }
        // cip.cc：IP / 地址（同一行还带运营商、数据二）
        if let txt = await HTTP.fetch(URL(string: "https://cip.cc")!, timeout: 10) {
            var ip = "", addr = "", isp = ""
            for line in txt.split(separator: "\n") {
                let s = line.replacingOccurrences(of: "\t", with: " ")
                if s.contains("IP"), s.contains(":"), ip.isEmpty,
                   s.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil {
                    ip = afterColon(s).split(separator: " ").first.map(String.init) ?? ""
                } else if s.contains("地址") {
                    let rest = afterColon(s)                       // 中国 广东 运营商 : 电信 数据二 : ...
                    if let r = rest.range(of: "运营商") {
                        addr = String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                        isp = NetInfoCenter.firstNonEmpty(String(rest[r.upperBound...]).split(separator: ":"))
                    } else {
                        addr = rest
                    }
                } else if s.contains("运营商"), isp.isEmpty {
                    isp = NetInfoCenter.firstNonEmpty(afterColon(s).split(separator: ":"))
                }
            }
            if !ip.isEmpty { return ExitSample(ip: ip, region: addr, isp: isp, source: "cip.cc") }
        }
        if let txt = await HTTP.fetch(URL(string: "https://myip.ipip.net")!, timeout: 10) {
            // 当前 IP：1.2.3.4  来自于：中国 广东 深圳 电信
            let ip = firstMatch(txt, #"IP[：:]\s*([0-9a-fA-F:.]+)"#) ?? ""
            let from = firstMatch(txt, #"来自于[：:]\s*(.+)"#) ?? ""
            if !ip.isEmpty { return ExitSample(ip: ip, region: from, isp: from.split(separator: " ").last.map(String.init) ?? "", source: "myip.ipip.net") }
        }
        return nil
    }

    private func afterColon(_ s: String) -> String {
        guard let c = s.firstIndex(of: ":") else { return "" }
        return s[s.index(after: c)...].trimmingCharacters(in: .whitespaces)
    }

    /// 取第一个非空分段（用于「运营商 : 电信」这类带前导空格的解析）
    nonisolated static func firstNonEmpty(_ parts: [Substring]) -> String {
        for p in parts {
            let t = p.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return ""
    }

    private func plainText(url: String) async -> String? {
        guard let u = URL(string: url) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 8
        do {
            let (d, _) = try await URLSession.shared.data(for: r)
            let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if s.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil { return s }
            return nil
        } catch { return nil }
    }

    private func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: 延迟矩阵

    static func defaultTargets() -> [(target: String, label: String, group: String)] {
        let t: [(String, String, String)] = [
            ("223.5.5.5", "阿里公共 DNS", "国内公共 DNS"),
            ("119.29.29.29", "腾讯 DNSPod", "国内公共 DNS"),
            ("114.114.114.114", "114 DNS", "国内公共 DNS"),
            ("180.76.76.76", "百度 DNS", "国内公共 DNS"),
            ("1.2.4.8", "CNNIC DNS", "国内公共 DNS"),
            ("www.baidu.com", "百度", "国内常用网站"),
            ("www.taobao.com", "淘宝", "国内常用网站"),
            ("www.qq.com", "腾讯网", "国内常用网站"),
            ("www.163.com", "网易", "国内常用网站"),
            ("www.jd.com", "京东", "国内常用网站"),
        ]
        return t
    }

    func runLatencyMatrix(quick: Bool = false) async {
        busy = true
        var targets = NetInfoCenter.defaultTargets()
        if quick {
            targets = Array(targets.filter { ["223.5.5.5", "119.29.29.29", "www.baidu.com"].contains($0.target) })
        }
        if !profile.gateway.isEmpty { targets.insert((profile.gateway, "本机网关（局域网）", "第一跳"), at: 0) }
        probes = []
        var results: [LatencyProbe] = []
        let count = quick ? "3" : "5"
        for (i, t) in targets.enumerated() {
            status = "延迟测试 \(i + 1)/\(targets.count)：\(t.label)"
            var p = LatencyProbe(target: t.target, label: t.label, group: t.group)
            let r = await Shell.run("/sbin/ping", ["-c", count, "-i", "0.3", "-W", "800", "-t", "5", t.target], timeout: 20)
            let text = r.out
            if let loss = firstMatch(text, #"([\d.]+)% packet loss"#) { p.lossPct = Double(loss) ?? 100 }
            if let m = firstMatch(text, #"round-trip min/avg/max/stddev = ([\d./]+)"#) {
                let parts = m.split(separator: "/").compactMap { Double($0) }
                if parts.count >= 4 {
                    p.minMs = parts[0]; p.avgMs = parts[1]; p.maxMs = parts[2]; p.stddevMs = parts[3]
                }
            }
            results.append(p)
            probes = results
        }
        busy = false
        status = "延迟测试完成"
    }
}
