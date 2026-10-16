import Foundation

/// 局域网设备扫描（fping 存活探测 + ARP 取 MAC + 反向 DNS + 端口指纹 + mDNS 服务）
@MainActor
final class LANScanner: ObservableObject {

    @Published var hosts: [LANHost] = []
    @Published var running = false
    @Published var status = "就绪"
    @Published var progress: Double = 0
    @Published var subnet: String = ""
    @Published var mdnsServices: [String] = []
    @Published var deepProbe = true

    nonisolated static let portList: [Int] = [21, 22, 23, 53, 80, 139, 443, 445, 548, 631, 1883, 3306,
                                  3389, 5000, 5432, 5900, 7000, 8008, 8009, 8080, 8081, 8123, 8443,
                                  9000, 9090, 9100, 32400, 62078]

    // MARK: 网段推断（全部走异步 Shell，避免阻塞主线程）

    func detectSubnet() async -> String {
        if let r = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 8).out as String?,
           !r.isEmpty {
            var iface = ""
            for line in r.split(separator: "\n") where line.contains("interface:") {
                iface = line.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if !iface.isEmpty, let cidr = await cidrFor(iface) { return cidr }
        }
        return "192.168.1.0/24"
    }

    private func cidrFor(_ iface: String) async -> String? {
        let out = await Shell.run("/sbin/ifconfig", [iface], timeout: 8).out
        var ip = "", mask = ""
        for line in out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("inet ") {
                let parts = s.split(separator: " ")
                if parts.count >= 2 { ip = String(parts[1]) }
                if let mi = parts.firstIndex(of: "netmask"), mi + 1 < parts.count {
                    mask = String(parts[mi + 1])
                }
            }
        }
        guard !ip.isEmpty, let ipN = ipv4ToInt(ip) else { return nil }
        // macOS 的 ifconfig 通常输出十六进制掩码（0xffffff00），也兼容点分十进制
        let maskN: UInt32
        if mask.hasPrefix("0x") {
            maskN = UInt32(mask.dropFirst(2), radix: 16) ?? 0xffffff00
        } else {
            maskN = mask.isEmpty ? 0xffffff00 : (ipv4ToInt(mask) ?? 0xffffff00)
        }
        let net = ipN & maskN
        return intToIPv4(net) + "/" + String(maskN.nonzeroBitCount)
    }

    private func ipv4ToInt(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func intToIPv4(_ v: UInt32) -> String {
        "\((v >> 24) & 0xff).\((v >> 16) & 0xff).\((v >> 8) & 0xff).\(v & 0xff)"
    }

    func selfIPv4() async -> String {
        let out = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 8).out
        var iface = ""
        for line in out.split(separator: "\n") where line.contains("interface:") {
            iface = line.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
        }
        guard !iface.isEmpty else { return "" }
        let o2 = await Shell.run("/sbin/ifconfig", [iface], timeout: 8).out
        for line in o2.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("inet ") { return String(s.split(separator: " ")[1]) }
        }
        return ""
    }

    func defaultGateway() async -> String {
        let r = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 8).out
        for line in r.split(separator: "\n") where line.contains("gateway:") {
            return line.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // MARK: 扫描主流程

    func scan(custom: String? = nil) async {
        guard !running else { return }
        running = true
        status = "准备扫描…"
        progress = 0
        hosts.removeAll()
        mdnsServices.removeAll()
        defer { running = false }

        let cidr = custom?.isEmpty == false ? custom! : await detectSubnet()
        subnet = cidr
        let selfIP = await selfIPv4()
        let gw = await defaultGateway()

        // 1) 先读一次 ARP 表（拿到常规在线设备）
        var arpMap = await parseARP()

        // 2) 存活探测
        status = "正在探测 \(cidr) 内存活主机…"
        var alive = await probeAlive(cidr: cidr)
        progress = 0.35
        if alive.isEmpty {
            status = "ICMP 无响应，改用 ARP 表被动发现…"
            alive = Array(arpMap.keys)
        }
        // 合并 ARP 表中已存在的地址
        for ip in arpMap.keys where !alive.contains(ip) { alive.append(ip) }

        // 3) 刷新 ARP（探测后表才完整）
        arpMap = await parseARP()

        // 4) 逐台补充信息
        status = "正在识别设备（\(alive.count) 台）…"
        let list = alive.filter { $0 != "224.0.0.251" && $0 != "239.255.255.250" }
        var result: [LANHost] = []
        var done = 0
        for ip in list {
            var h = LANHost(ip: ip)
            h.mac = arpMap[ip] ?? ""
            if let v = OUIDB.shared.vendor(for: h.mac) {
                h.vendor = OUIDB.friendlyVendor(v)
            } else if !h.mac.isEmpty && OUIDB.isRandomMAC(h.mac) {
                h.vendor = "随机 MAC（隐私保护）"
            } else {
                h.vendor = "未知厂商"
            }
            h.isSelf = (ip == selfIP)
            h.isGateway = (ip == gw)
            if h.isGateway { h.kind = "路由器 / 网关" }
            else if h.isSelf { h.kind = "本机" }
            result.append(h)
            done += 1
            progress = 0.35 + 0.65 * Double(done) / Double(max(list.count, 1))
        }

        // 5) 反向 DNS + 端口指纹（并发）；大网段只对前 40 台做指纹，避免耗时过长
        let probeLimit = 40
        await withTaskGroup(of: (Int, String, [Int]).self) { group in
            var idx = 0
            let maxConc = 6
            let deep = deepProbe
            func add(_ g: inout TaskGroup<(Int, String, [Int])>, _ i: Int) {
                let ip = result[i].ip
                let doPorts = deep && i < probeLimit
                g.addTask {
                    async let nameTask: String = LANScanner.reverseDNS(ip)
                    async let portTask: [Int] = doPorts ? LANScanner.probePorts(ip) : []
                    return (i, await nameTask, await portTask)
                }
            }
            for i in result.indices where idx < maxConc { add(&group, i); idx += 1 }
            var completed = 0
            for await (i, name, ports) in group {
                result[i].hostname = name
                result[i].openPorts = ports
                result[i].kind = result[i].kind.isEmpty ? LANScanner.inferKind(result[i]) : result[i].kind
                completed += 1
                status = "正在识别设备（\(completed)/\(result.count)）…"
                if idx < result.count { add(&group, idx); idx += 1 }
            }
        }

        // 6) mDNS 服务类型
        status = "发现 mDNS 服务…"
        let mdns = await Shell.runAndStop("/usr/bin/dns-sd", ["-B", "_services._dns-sd._udp.", "local."], seconds: 4)
        mdnsServices = LANScanner.parseMDNSTypes(mdns)

        result.sort { a, b in
            if a.isGateway != b.isGateway { return a.isGateway }
            if a.isSelf != b.isSelf { return a.isSelf }
            return LANScanner.ipSort(a.ip, b.ip)
        }
        hosts = result
        status = "扫描完成：发现 \(result.count) 台设备" + (mdnsServices.isEmpty ? "" : "，\(mdnsServices.count) 类 mDNS 服务")
        progress = 1
    }

    // MARK: 探测实现

    private func probeAlive(cidr: String) async -> [String] {
        if let bin = Shell.locate("fping") {
            // -p 25 关键：默认每主机间隔 1 秒，/24 会拖到 4 分钟；25ms 间隔约 3 秒扫完
            let r = await Shell.run(bin, ["-a", "-g", cidr, "-t", "400", "-r", "0", "-p", "25", "-q"], timeout: 90)
            var ips: [String] = []
            for line in r.combined.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil { ips.append(s) }
            }
            if !ips.isEmpty { return ips }
        }
        // 回退：系统 ping 并发
        return await pingSweep(cidr: cidr)
    }

    private func pingSweep(cidr: String) async -> [String] {
        guard let slash = cidr.firstIndex(of: "/"), let prefix = Int(cidr[cidr.index(after: slash)...]) else { return [] }
        guard prefix >= 24 else { return [] }   // 大网段只用 fping
        let base = String(cidr[..<slash])
        guard let baseInt = ipv4ToInt(base) else { return [] }
        let count = prefix == 24 ? 254 : (1 << (32 - prefix)) - 2
        var alive: [String] = []
        await withTaskGroup(of: String?.self) { group in
            var launched = 0
            let conc = 48
            func add(_ g: inout TaskGroup<String?>, _ host: UInt32) {
                g.addTask {
                    let ip = LANScanner.intToIPv4Static(baseInt + host)
                    var ok = await LANScanner.tcpReachable(ip: ip, port: 80)
                    if !ok { ok = await LANScanner.icmpReachable(ip) }
                    return ok ? ip : nil
                }
            }
            for h in 1...UInt32(count) where launched < conc { add(&group, h); launched += 1 }
            var next: UInt32 = UInt32(launched) + 1
            for await res in group {
                if let ip = res { alive.append(ip) }
                if next <= UInt32(count) { add(&group, next); next += 1 }
            }
        }
        return alive
    }

    nonisolated static func intToIPv4Static(_ v: UInt32) -> String {
        "\((v >> 24) & 0xff).\((v >> 16) & 0xff).\((v >> 8) & 0xff).\(v & 0xff)"
    }

    nonisolated static func icmpReachable(_ ip: String) async -> Bool {
        let r = await Shell.run("/sbin/ping", ["-c", "1", "-W", "400", "-t", "1", ip], timeout: 3)
        return r.code == 0
    }

    nonisolated static func tcpReachable(ip: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: tcpConnectSync(ip: ip, port: port, timeoutMs: 250))
            }
        }
    }

    nonisolated static func probePorts(_ ip: String) async -> [Int] {
        var open: [Int] = []
        await withTaskGroup(of: (Int, Bool).self) { group in
            var launched = 0
            let conc = 16
            func add(_ g: inout TaskGroup<(Int, Bool)>, _ p: Int) {
                g.addTask {
                    await withCheckedContinuation { (c: CheckedContinuation<(Int, Bool), Never>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            c.resume(returning: (p, tcpConnectSync(ip: ip, port: UInt16(p), timeoutMs: 350)))
                        }
                    }
                }
            }
            for p in portList where launched < conc { add(&group, p); launched += 1 }
            var next = launched
            for await (p, ok) in group {
                if ok { open.append(p) }
                if next < portList.count { add(&group, portList[next]); next += 1 }
            }
        }
        return open.sorted()
    }

    nonisolated static func reverseDNS(_ ip: String) async -> String {
        let r = await Shell.run("/usr/bin/dig", ["-x", ip, "+short", "+time=1", "+tries=1"], timeout: 4)
        for line in r.out.split(separator: "\n") {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasSuffix(".") { s.removeLast() }
            if !s.isEmpty && !s.hasPrefix(";") && s.contains(".") { return s }
        }
        // mDNS 反解：取整行最后一个 token，且必须是真实主机名（过滤 No Such Record 等噪音）
        let r2 = await Shell.runAndStop("/usr/bin/dns-sd", ["-Q", ip], seconds: 2)
        for line in r2.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("DATE:"), !s.contains("No Such Record"),
                  !s.contains("STARTING"), !s.hasPrefix("Timestamp") else { continue }
            guard let last = s.split(separator: " ").last.map(String.init) else { continue }
            var name = last
            guard name.hasSuffix("."), name.count > 3 else { continue }
            name.removeLast()
            guard name.rangeOfCharacter(from: .letters) != nil,
                  !name.contains("arpa"), !name.contains(":"),
                  !name.hasPrefix("0.0.0.0"), name.lowercased() != "local" else { continue }
            return name
        }
        return ""
    }

    // MARK: 解析

    private func parseARP() async -> [String: String] {
        var map: [String: String] = [:]
        let r = await Shell.run("/usr/sbin/arp", ["-an"], timeout: 8).out
        let re = try? NSRegularExpression(pattern: #"\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-fA-F:]+)"#)
        guard let re else { return map }
        for line in r.split(separator: "\n") {
            let s = String(line)
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let ipR = Range(m.range(at: 1), in: s), let macR = Range(m.range(at: 2), in: s) else { continue }
            let mac = String(s[macR])
            if mac.contains("incomplete") { continue }
            map[String(s[ipR])] = mac
        }
        return map
    }

    nonisolated static func parseMDNSTypes(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 6, parts.contains("Add") else { continue }
            let svc = String(parts[parts.count - 1])
            guard svc.hasPrefix("_") else { continue }
            let cn = LANScanner.mdnsChinese(svc)
            if !out.contains(cn) { out.append(cn) }
        }
        return out.sorted()
    }

    nonisolated static func mdnsChinese(_ svc: String) -> String {
        let rules: [(String, String)] = [
            ("_airplay", "AirPlay 投屏"), ("_raop", "AirPlay 音频"), ("_googlecast", "Chromecast/投屏"),
            ("_ipp", "网络打印机"), ("_printer", "网络打印机"), ("_pdl-datastream", "打印机"),
            ("_smb", "文件共享(SMB)"), ("_afpovertcp", "文件共享(AFP)"), ("_nfs", "文件共享(NFS)"),
            ("_device-info", "Apple 设备"), ("_companion-link", "Apple 设备"),
            ("_home-assistant", "Home Assistant"), ("_hap", "HomeKit 智能家居"),
            ("_miio", "米家智能设备"), ("_mijia", "米家智能设备"),
            ("_http", "Web 服务"), ("_https", "Web 服务"), ("_ssh", "SSH"),
            ("_workstation", "工作站"), ("_rfb", "屏幕共享(VNC)"),
            ("_spotify-connect", "Spotify 音箱"), ("_sonos", "Sonos 音箱"),
            ("_sleep-proxy", "Apple 睡眠代理"), ("_rdlink", "Apple 远程桌面"),
            ("_net-assistant", "Apple 网络助理"), ("_sftp-ssh", "SFTP"), ("_ftp", "FTP"),
        ]
        for (k, v) in rules where svc.contains(k) { return v }
        return svc
    }

    nonisolated static func inferKind(_ h: LANHost) -> String {
        let ports = Set(h.openPorts)
        let v = h.vendor
        if h.isGateway { return "路由器 / 网关" }
        if h.isSelf { return "本机" }
        if ports.contains(62078) { return "iPhone / iPad" }
        if ports.contains(9100) || ports.contains(631) { return "网络打印机" }
        if ports.contains(5900) && v.contains("Apple") { return "Mac（屏幕共享）" }
        if ports.contains(5900) { return "开启屏幕共享的设备" }
        if v.contains("群晖") || v.contains("威联通") || v.contains("飞牛") || (ports.contains(445) && ports.contains(5000)) { return "NAS 存储" }
        if ports.contains(8123) { return "Home Assistant 智能家居" }
        if ports.contains(32400) { return "Plex 媒体服务器" }
        if ports.contains(8008) || ports.contains(8009) { return "投屏设备（Chromecast）" }
        if ports.contains(3389) { return "Windows 电脑" }
        if ports.contains(22) && (ports.contains(80) || ports.contains(443)) { return "Linux / 智能网关" }
        if ports.contains(80) || ports.contains(443) || ports.contains(8080) || ports.contains(8081) { return "带 Web 界面的设备" }
        if ports.contains(22) { return "Linux / 网络设备" }
        if v.contains("Apple") { return "Apple 设备" }
        if v.contains("小米") || v.contains("华为") || v.contains("涂鸦") || v.contains("乐鑫") { return "智能家居设备" }
        if v.contains("TP-LINK") || v.contains("水星") || v.contains("腾达") || v.contains("新华三") || v.contains("锐捷") { return "网络设备" }
        if ports.isEmpty { return "在线设备（未开放常用端口）" }
        return "在线设备"
    }

    nonisolated static func ipSort(_ a: String, _ b: String) -> Bool {
        func n(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let x = n(a), y = n(b)
        for i in 0 ..< min(x.count, y.count) where x[i] != y[i] { return x[i] < y[i] }
        return x.count < y.count
    }
}

/// 非阻塞 TCP 连接探测
func tcpConnectSync(ip: String, port: UInt16, timeoutMs: Int32) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return false }
    let r = withUnsafePointer(to: &addr) { p -> Int32 in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if r == 0 { return true }
    if errno != EINPROGRESS { return false }
    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    let pr = poll(&pfd, 1, timeoutMs)
    guard pr > 0 else { return false }
    var soErr: Int32 = 0
    var len = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
    return soErr == 0
}
