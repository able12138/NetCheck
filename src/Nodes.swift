import Foundation

/// 极简 HTTP 辅助（目录列举解析 / HEAD 探测）
enum HTTP {
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"

    static func fetch(_ url: URL, timeout: Double = 20, maxBytes: Int = 2_000_000) async -> String? {
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: r)
            return String(data: data.prefix(maxBytes), encoding: .utf8)
        } catch { return nil }
    }

    static func head(_ url: URL, timeout: Double = 12) async -> (code: Int, length: Int64, ms: Double)? {
        var r = URLRequest(url: url)
        r.httpMethod = "HEAD"
        r.timeoutInterval = timeout
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        let t0 = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: r)
            let ms = Date().timeIntervalSince(t0) * 1000
            guard let h = resp as? HTTPURLResponse else { return nil }
            return (h.statusCode, h.expectedContentLength, ms)
        } catch { return nil }
    }

    /// 取一组 URL 的首字节答复时间（用于节点延迟）
    static func ping(_ url: URL, timeout: Double = 8) async -> Double? {
        var r = URLRequest(url: url)
        r.httpMethod = "HEAD"
        r.timeoutInterval = timeout
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        let t0 = Date()
        do {
            _ = try await URLSession.shared.data(for: r)
            return Date().timeIntervalSince(t0) * 1000
        } catch { return nil }
    }
}

/// 国内测速节点目录
///
/// 设计要点（2026-10-16 逐节点实测后修订）：
/// - 国内 Ookla 公共节点极少（全国仅 1 个：上海电信 3633），故主体走国内镜像/高校镜像骨干节点；
/// - 镜像站行为差异极大，因此**每个节点都要先探测再测速**，并把失败原因如实归类，
///   不把「节点不可达」「重定向异常」「文件极慢」混成一句「失败」；
/// - 用 curl 而非 URLSession 做探测：curl 能一次拿到「跟随重定向后的最终地址 + 状态码 + 实收字节」，
///   这正是区分上述几类原因所需的信息。
enum NodeCatalog {

    static let all: [SpeedNode] = [
        SpeedNode(name: "腾讯云", region: "深圳", isp: "多线 BGP", base: "https://mirrors.cloud.tencent.com/", kind: .cloud),
        SpeedNode(name: "齐鲁工大", region: "济南", isp: "教育网/联通", base: "https://mirrors.qlu.edu.cn/", kind: .edu),
        SpeedNode(name: "北京外国语", region: "北京", isp: "教育网", base: "https://mirrors.bfsu.edu.cn/", kind: .edu),
        SpeedNode(name: "清华 TUNA", region: "北京", isp: "教育网/联通", base: "https://mirrors.tuna.tsinghua.edu.cn/", kind: .edu),
        SpeedNode(name: "西安交大", region: "西安", isp: "教育网", base: "https://mirrors.xjtu.edu.cn/", kind: .edu),
        SpeedNode(name: "阿里云", region: "杭州", isp: "多线 BGP", base: "https://mirrors.aliyun.com/", kind: .cloud),
        SpeedNode(name: "华为云", region: "北京", isp: "BGP", base: "https://mirrors.huaweicloud.com/", kind: .cloud),
        SpeedNode(name: "网易", region: "杭州", isp: "电信", base: "https://mirrors.163.com/", kind: .cloud),
        SpeedNode(name: "搜狐", region: "北京", isp: "联通/电信", base: "https://mirrors.sohu.com/", kind: .cloud),
        SpeedNode(name: "首都在线", region: "北京", isp: "BGP", base: "https://mirrors.yun-idc.com/", kind: .cloud),
        SpeedNode(name: "中科大 USTC", region: "合肥", isp: "教育网/电信", base: "https://mirrors.ustc.edu.cn/", kind: .edu),
        SpeedNode(name: "华中科大", region: "武汉", isp: "教育网", base: "https://mirrors.hust.edu.cn/", kind: .edu),
        SpeedNode(name: "上海交大", region: "上海", isp: "教育网", base: "https://mirror.sjtu.edu.cn/", kind: .edu),
        SpeedNode(name: "南京大学", region: "南京", isp: "教育网", base: "https://mirrors.nju.edu.cn/", kind: .edu),
        SpeedNode(name: "重庆大学", region: "重庆", isp: "教育网", base: "https://mirrors.cqu.edu.cn/", kind: .edu),
        // 该节点是 Ookla 服务器，不是镜像站：不能用 ISO 解析，必须走 speedtest 二进制
        SpeedNode(name: "Ookla 上海电信", region: "上海", isp: "电信", base: "http://speedtest1.online.sh.cn:8080/",
                  kind: .isp, ooklaID: "3633"),
    ]

    // MARK: - 解析测速文件

    static func resolve(_ node: SpeedNode) async -> ResolvedNode {
        if let d = node.directURL {
            let r = await probe(d)
            if !r.url.isEmpty { return r }
        }
        let base = node.base.hasSuffix("/") ? node.base : node.base + "/"
        var reasons: [String] = []

        let r1 = await findISO(base: base, path: "debian-cd/current/amd64/iso-cd/",
                               pattern: #"debian-[\d.]+-amd64-netinst\.iso"#)
        if !r1.url.isEmpty { return r1 }
        reasons.append(r1.reason)
        // 站点整体不可达 / 重定向异常时，换路径也是白等，直接返回原因
        if r1.reason.contains("不可达") || r1.reason.contains("重定向") { return r1 }

        let r2 = await findUbuntu(base: base)
        if !r2.url.isEmpty { return r2 }
        reasons.append(r2.reason)

        let r3 = await findISO(base: base, path: "centos/8-stream/isos/x86_64/",
                               pattern: #"CentOS-Stream-8-x86_64-latest-boot\.iso"#)
        if !r3.url.isEmpty { return r3 }
        reasons.append(r3.reason)

        let reason = reasons.first(where: { $0.contains("不可达") || $0.contains("重定向") })
            ?? reasons.first(where: { !$0.isEmpty }) ?? "无可用测速文件"
        return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: reason)
    }

    /// 探测单个文件：一次 curl 同时拿到「最终地址 + 状态码 + 实收字节 + 响应头」
    /// - Range 请求被忽略（回 200 但仍吐数据）的镜像同样判为可用，并标注不支持断点
    static func probe(_ urlString: String, timeout: Double = 8) async -> ResolvedNode {
        let curl = Shell.locate("curl") ?? "/usr/bin/curl"
        let args = ["-sL", "-o", "/dev/null", "-m", "\(Int(timeout))",
                    "--range", "0-524287", "-D", "-", "-A", HTTP.ua,
                    "-w", "\n##CODE=%{http_code} BYTES=%{size_download} FINAL=%{url_effective}",
                    urlString]
        let r = await Shell.run(curl, args, timeout: timeout + 6)
        let text = r.combined
        guard let line = text.split(separator: "\n").last(where: { $0.contains("##CODE=") }) else {
            let why = r.code == 28 ? "请求超时" : (r.code == 7 ? "节点不可达" : "无响应")
            return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: why)
        }
        func field(_ k: String) -> String {
            guard let re = try? NSRegularExpression(pattern: "\(k)=([^\\s]+)") else { return "" }
            let s = String(line)
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let rr = Range(m.range(at: 1), in: s) else { return "" }
            return String(s[rr])
        }
        let code = Int(field("CODE")) ?? 0
        let bytes = Int64(field("BYTES")) ?? 0
        let final = field("FINAL")

        // 1) 206 + Content-Range → 支持断点，能拿到总大小
        if let re = try? NSRegularExpression(pattern: #"(?i)content-range:\s*bytes\s+\d+-\d+/(\d+)"#),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let rr = Range(m.range(at: 1), in: text),
           let total = Int64(text[rr]), total > 200 * 1_048_576 {
            return ResolvedNode(url: urlString, sizeMB: Double(total) / 1_048_576,
                                rangeOK: true, reason: "", finalURL: final)
        }
        // 2) 200 且真的吐了二进制数据 → 可用但忽略 Range（测速时走整段下载）
        let isHTML = headerValue(text, "content-type").lowercased().contains("text/html")
            || text.lowercased().contains("<html")
        if code == 200, !isHTML, bytes > 100_000 {
            let est = bytes > 1_000_000 ? Double(bytes) / 1_048_576 : 0
            return ResolvedNode(url: urlString, sizeMB: est, rangeOK: false, reason: "", finalURL: final)
        }
        // 3) 失败归因（越具体越有用）
        let low = text.lowercased()
        let reason: String
        if code == 418 || low.contains("hwwaf") || low.contains("attack-id") {
            reason = "被 WAF 拦截(418)"
        } else if code == 0 || r.code == 7 {
            reason = "重定向后不可达"
        } else if r.code == 28 || code == 408 {
            reason = "请求超时"
        } else if isHTML || low.contains("cerberus") || low.contains("challenge") {
            reason = "反爬挑战页"
        } else if code == 200 {
            // 真文件要么是 206 + 大 Content-Range，要么是 200 + 大响应体；
            // 200 却只有几 KB → 拿到的是网页/错误页，不是测速文件
            reason = "返回网页(\(bytes) 字节)"
        } else if (300...399).contains(code) {
            reason = "重定向异常"
        } else if code == 403 {
            reason = "拒绝访问(403)"
        } else if code == 404 {
            reason = "无此文件(404)"
        } else if code == 416 {
            reason = "不支持断点(416)"
        } else {
            reason = bytes > 0 ? "响应过小(\(bytes) 字节)" : "无测速文件(\(code))"
        }
        return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: reason, finalURL: final)
    }

    /// 从响应头文本里取某个头的值（大小写不敏感）
    static func headerValue(_ text: String, _ name: String) -> String {
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.lowercased().hasPrefix(name.lowercased() + ":") {
                return s.split(separator: ":", maxSplits: 1).dropFirst().joined()
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func listing(_ urlString: String, timeout: Double = 10) async -> (html: String, code: Int) {
        let curl = Shell.locate("curl") ?? "/usr/bin/curl"
        let r = await Shell.run(curl, ["-sL", "-m", "\(Int(timeout))", "-A", HTTP.ua,
                                       "-w", "\n##CODE=%{http_code}", urlString], timeout: timeout + 5)
        let text = r.combined
        var code = 0
        if let line = text.split(separator: "\n").last(where: { $0.contains("##CODE=") }),
           let v = Int(line.replacingOccurrences(of: "##CODE=", with: "").trimmingCharacters(in: .whitespaces)) {
            code = v
        }
        let html = text.split(separator: "\n").filter { !$0.contains("##CODE=") }.joined(separator: "\n")
        return (html, code)
    }

    private static func findISO(base: String, path: String, pattern: String) async -> ResolvedNode {
        let (html, code) = await listing(base + path)
        if code == 0 { return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "节点不可达") }
        if (300...399).contains(code) { return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "重定向异常") }
        guard code == 200 else {
            return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "无测速文件(\(code))")
        }
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range, in: html) else {
            return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "目录内无可用 ISO")
        }
        let file = String(html[r])
        let res = await probe(base + path + file)
        if !res.url.isEmpty { return res }
        return ResolvedNode(url: "", sizeMB: 0, rangeOK: false,
                            reason: res.reason.isEmpty ? "文件不可用(\(file.prefix(28)))" : res.reason)
    }

    private static func findUbuntu(base: String) async -> ResolvedNode {
        let (html, code) = await listing(base + "ubuntu-releases/")
        if code == 0 { return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "节点不可达") }
        if (300...399).contains(code) { return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "重定向异常") }
        guard code == 200 else {
            return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "无测速文件(\(code))")
        }
        guard let re = try? NSRegularExpression(pattern: #"href="(\d\d\.\d\d)/""#) else {
            return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "无可用测速文件")
        }
        var vers: [String] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            if let r = Range(m.range(at: 1), in: html) { vers.append(String(html[r])) }
        }
        for v in Set(vers).sorted(by: >).prefix(4) {
            let (sub, c2) = await listing(base + "ubuntu-releases/\(v)/", timeout: 8)
            guard c2 == 200 else { continue }
            let pats = [#"href="([^"]*desktop-amd64\.iso)""#,
                        #"href="([^"]*live-server-amd64\.iso)""#]
            var candidates: [String] = []
            for p in pats {
                guard let ire = try? NSRegularExpression(pattern: p) else { continue }
                for m in ire.matches(in: sub, range: NSRange(sub.startIndex..., in: sub)) {
                    if let r = Range(m.range(at: 1), in: sub) { candidates.append(String(sub[r])) }
                }
            }
            let stable = candidates.filter { !$0.lowercased().contains("beta") && !$0.lowercased().contains("alpha") }
            for file in stable + candidates {
                let res = await probe(base + "ubuntu-releases/\(v)/" + file)
                if !res.url.isEmpty { return res }
            }
        }
        return ResolvedNode(url: "", sizeMB: 0, rangeOK: false, reason: "目录内无可用 ISO")
    }
}

/// 节点批量测速（限时多连接下载）
@MainActor
final class NodeTester: ObservableObject {
    @Published var nodes: [SpeedNode] = NodeCatalog.all
    @Published var running = false
    @Published var status = "就绪"
    @Published var progress: Double = 0
    @Published var secondsPerNode: Double = 8
    @Published var connections: Int = 6
    @Published var concurrency: Int = 3

    private var cache: [String: ResolvedNode] = [:]   // node name -> 已解析的测速文件

    var usableCount: Int { nodes.filter { $0.ok == true }.count }
    var testedCount: Int { nodes.filter { $0.ok != nil }.count }

    func reset() {
        for i in nodes.indices {
            nodes[i].mbps = 0; nodes[i].status = "待测"; nodes[i].ok = nil; nodes[i].why = ""
            nodes[i].latencyMs = 0; nodes[i].fileURL = nil; nodes[i].fileSizeMB = 0
        }
        progress = 0
        status = "已重置"
    }

    /// 测一个节点：解析 → 测速 → 归类状态（静态方法，不持有 self，避免把主线程拖进耗时流程）
    static func runNode(_ snapshot: SpeedNode, cached: ResolvedNode?, secs: Double, conns: Int) async -> SpeedNode {
        var n = snapshot

        // ① Ookla 节点走 speedtest 二进制（它的目录里没有 ISO，用 ISO 解析必然失败）
        if let sid = n.ooklaID {
            guard OoklaEngine.available else {
                n.ok = false; n.status = "未安装 speedtest"; n.why = "本机缺少 /usr/local/bin/speedtest"
                return n
            }
            let run = await OoklaEngine.run(serverID: sid, download: true, upload: false,
                                            progress: { _ in }, token: nil)
            guard let r = run, r.downMbps > 0 else {
                n.ok = false; n.status = "测速失败"; n.why = "Ookla 通道无返回（可稍后重试）"
                return n
            }
            n.mbps = r.downMbps
            n.latencyMs = r.pingMs
            n.fileSizeMB = 0
            n.ok = true
            n.status = "完成"
            n.fileURL = "Ookla \(r.node)"
            n.why = "经 speedtest-go 实测（与镜像节点口径不同，含真实 TCP 传输）"
            return n
        }

        // ② 镜像节点：解析测速文件
        var resolved = cached
        if resolved == nil { resolved = await NodeCatalog.resolve(n) }
        guard let rs = resolved, !rs.url.isEmpty else {
            n.ok = false
            n.status = (resolved?.reason.isEmpty == false) ? resolved!.reason : "无可用测速文件"
            n.why = "镜像站侧原因（已探测确认）：\(n.status)。不是你的网络故障，也不是测速误差。"
            return n
        }
        n.fileURL = rs.url
        n.fileSizeMB = rs.sizeMB
        if let u = URL(string: rs.url) {
            let meter = HTTPMeter()
            let res = await meter.measureDownloadSmart(url: u, seconds: secs, connections: conns,
                                                       rangeHint: rs.rangeOK)
            n.mbps = res.mbps
        }
        // ③ 状态细分：能下到数据但很慢 ≠ 失败
        if n.mbps >= 1.0 {
            n.ok = true; n.status = "完成"
        } else if n.mbps > 0.001 {
            n.ok = false; n.status = "极慢"
            n.why = "有数据但低于 1 Mbps：多为镜像站对本线路限速，或教育网互联带宽受限（实测 \(String(format: "%.2f", n.mbps)) Mbps）"
        } else {
            n.ok = false; n.status = "失败"
            n.why = "\(Int(secs)) 秒内未收到任何数据（0 字节），可能是节点限速/被 CDN 拒绝"
        }
        return n
    }

    func testAll(selected: Set<UUID>? = nil) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let targets = nodes.indices.filter { selected == nil || selected!.isEmpty || selected!.contains(nodes[$0].id) }
        for idx in targets { nodes[idx].status = "排队中"; nodes[idx].ok = nil; nodes[idx].why = "" }
        progress = 0
        status = "开始测速（\(targets.count) 个节点）"

        let secs = secondsPerNode
        let conns = connections
        let conc = max(1, min(concurrency, 6))
        var done = 0
        var cursor = 0

        while cursor < targets.count {
            let batch = Array(targets[cursor ..< min(cursor + conc, targets.count)])
            for idx in batch { nodes[idx].status = "解析并测速中…" }
            let results: [SpeedNode] = await withTaskGroup(of: (Int, SpeedNode).self) { group in
                for idx in batch {
                    let snapshot = nodes[idx]
                    let cached = cache[snapshot.name]
                    group.addTask {
                        (idx, await NodeTester.runNode(snapshot, cached: cached, secs: secs, conns: conns))
                    }
                }
                var out: [(Int, SpeedNode)] = []
                for await r in group { out.append(r) }
                return out.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            for (i, n) in results.enumerated() {
                let idx = batch[i]
                nodes[idx] = n
                if let f = n.fileURL, n.ooklaID == nil {
                    cache[n.name] = ResolvedNode(url: f, sizeMB: n.fileSizeMB, rangeOK: true)
                }
                done += 1
                progress = Double(done) / Double(max(targets.count, 1))
                status = "已完成 \(done)/\(targets.count) 个节点"
            }
            cursor += batch.count
        }

        nodes.sort { ($0.ok == true ? $0.mbps : -1) > ($1.ok == true ? $1.mbps : -1) }
        let usable = nodes.filter { $0.ok == true }.count
        status = "全部完成：\(usable)/\(nodes.count) 个节点可用，已按下行速度排序"
        progress = 1
    }

    func testOne(_ id: UUID) async {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = nodes[idx]
        let cached = cache[snapshot.name]
        nodes[idx].status = "解析中…"
        nodes[idx].why = ""
        nodes[idx] = await Self.runNode(snapshot, cached: cached,
                                        secs: secondsPerNode, conns: connections)
        if let f = nodes[idx].fileURL, nodes[idx].ooklaID == nil, nodes[idx].ok == true {
            cache[snapshot.name] = ResolvedNode(url: f, sizeMB: nodes[idx].fileSizeMB, rangeOK: true)
        }
    }
}
