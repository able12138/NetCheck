import SwiftUI

enum NavItem: String, CaseIterable, Identifiable {
    case home, speed, nodes, lan, wifi, info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .speed: return "本机测速"
        case .nodes: return "宽带节点测速"
        case .lan: return "局域网设备"
        case .wifi: return "Wi-Fi 检测分析"
        case .info: return "网络诊断"
        }
    }

    var icon: String {
        switch self {
        case .home: return "checkmark.shield.fill"
        case .speed: return "speedometer"
        case .nodes: return "point.3.filled.connected.trianglepath.dotted"
        case .lan: return "desktopcomputer"
        case .wifi: return "wifi"
        case .info: return "stethoscope"
        }
    }
}

enum SpeedEngineChoice: String, CaseIterable, Identifiable {
    case chinaMulti = "国内多连接"
    case ookla = "Ookla 节点"
    case apple = "Apple 官方"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .chinaMulti: return "对国内云镜像/骨干节点发起多连接下载，最贴近国内真实宽带体验（不依赖 Ookla）"
        case .ookla: return "使用已安装的 speedtest-go 连接 Ookla 测速节点（国内仅上海电信 1 个，其余为香港）"
        case .apple: return "调用系统自带 networkQuality，测 Apple 边缘节点（境外），含官方「响应性」指标"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: NavItem? = .home

    let nodes = NodeTester()
    let wifi = WiFiEngine()
    let lan = LANScanner()
    let net = NetInfoCenter()

    // 首页体检状态
    @Published var health = HealthReport()
    @Published var checking = false
    @Published var checkSteps: [CheckStep] = []

    // 本机测速状态
    @Published var engineChoice: SpeedEngineChoice = .chinaMulti
    @Published var phase: SpeedPhase = .idle
    @Published var phaseText = "选择测速引擎后点击「开始测速」"
    @Published var testing = false
    @Published var progress: Double = 0
    @Published var liveMbps: Double = 0
    @Published var elapsed: Double = 0
    @Published var current = SpeedRun()
    @Published var history: [SpeedRun] = []
    @Published var ooklaServers: [OoklaServer] = []
    @Published var ooklaServerID: String = "3633"
    @Published var loadingServers = false

    private var cachedNode: (SpeedNode, ResolvedNode)?
    private var activeMeter: HTTPMeter?
    private var activeToken: ProcessToken?
    private var runSeq = 0

    init() {
        if !OoklaEngine.available {
            ooklaServerID = ""
        }
    }

    // MARK: 本机测速

    func startTest() async {
        guard !testing else { return }
        runSeq += 1
        let seq = runSeq
        testing = true
        liveMbps = 0
        elapsed = 0
        progress = 0
        let token = ProcessToken()
        activeToken = token
        switch engineChoice {
        case .chinaMulti: await runChinaMulti(seq: seq, token: token)
        case .ookla: await runOokla(seq: seq, token: token)
        case .apple: await runApple(seq: seq, token: token)
        }
        guard seq == runSeq else { return }
        testing = false
        if phase != .failed { phase = .done }
        progress = 1
        activeMeter = nil
        activeToken = nil
        if current.downMbps > 0 || current.upMbps > 0 {
            history.insert(current, at: 0)
            if history.count > 20 { history.removeLast() }
        }
    }

    /// 手动停止（停止当前阶段；已完成的阶段结果保留）
    func cancelTest() {
        runSeq += 1
        activeToken?.cancel()
        activeMeter?.abort()
        activeMeter = nil
        activeToken = nil
        testing = false
        liveMbps = 0
        phase = .failed
        phaseText = "已手动停止。已测出的阶段结果仍保留在结果卡片中。"
    }

    private func pickChinaNode() async -> (SpeedNode, ResolvedNode)? {
        if let c = cachedNode { return c }
        // 顺序 = 实测可用性优先（2026-10-16 逐节点实测：腾讯云/齐鲁工大/北外/清华/西安交大 可用；首都在线、重庆大学等对本线路不通）
        let order = ["腾讯云", "齐鲁工大", "北京外国语", "清华 TUNA", "西安交大", "华中科大",
                     "阿里云", "华为云", "网易", "搜狐", "中科大 USTC", "上海交大"]
        for name in order {
            guard let n = NodeCatalog.all.first(where: { $0.name == name }) else { continue }
            phaseText = "正在解析 \(n.name) 的测速文件…"
            let r = await NodeCatalog.resolve(n)
            if !r.url.isEmpty {
                cachedNode = (n, r)
                return cachedNode
            }
        }
        return nil
    }

    private func runChinaMulti(seq: Int, token: ProcessToken) async {
        var r = SpeedRun()
        r.engine = "国内多连接"
        phase = .ping
        phaseText = "选择国内测速节点…"
        guard let (node, resolved) = await pickChinaNode(), let url = URL(string: resolved.url) else {
            phase = .failed
            phaseText = "国内节点均不可达（可能被网络策略拦截），请改用 Ookla 或 Apple 引擎"
            return
        }
        guard seq == runSeq else { return }
        r.node = "\(node.name) · \(node.region)（\(node.isp)）"
        let connections = resolved.rangeOK ? 8 : 6

        // 延迟
        var lats: [Double] = []
        for _ in 0 ..< 5 {
            if let ms = await HTTP.ping(url, timeout: 6) { lats.append(ms) }
        }
        guard seq == runSeq else { return }
        r.pingMs = lats.isEmpty ? 0 : lats.reduce(0, +) / Double(lats.count)
        r.jitterMs = lats.count > 1 ? (lats.max()! - lats.min()!) : 0

        // 下行
        phase = .download
        phaseText = "正在测试下行（\(node.name)，\(connections) 连接 / 12 秒）…"
        let meter = HTTPMeter()
        activeMeter = meter
        let t0 = Date()
        let res = await meter.measureDownloadSmart(url: url, seconds: 12, connections: connections,
                                                  rangeHint: resolved.rangeOK) { bytes in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let e = Date().timeIntervalSince(t0)
                self.elapsed = e
                self.liveMbps = Double(bytes) * 8 / 1_000_000 / max(e, 0.4)
                self.progress = min(0.75, e / 12 * 0.75)
            }
        }
        guard seq == runSeq else { return }
        activeMeter = nil
        r.downMbps = res.mbps
        liveMbps = 0
        progress = 0.78
        current = r          // 先把已测到的下行落到界面

        // 上行
        phase = .upload
        progress = 0.8
        let up = await measureUploadBest(token: token)
        guard seq == runSeq else { return }
        r.upMbps = up.mbps
        if let note = up.note { r.note = note }

        // 出口信息
        await fillExit(&r)
        guard seq == runSeq else { return }
        current = r
        phaseText = "测试完成"
    }

    private func measureUploadBest(token: ProcessToken) async -> (mbps: Double, note: String?) {
        if OoklaEngine.available {
            phaseText = "正在测试上行（Ookla 上传通道，约 20 秒）…"
            if let r = await OoklaEngine.run(serverID: ooklaServerID.isEmpty ? nil : ooklaServerID,
                                             download: false, upload: true, progress: { _ in },
                                             token: token),
               r.upMbps > 0 {
                return (r.upMbps, "上行经 Ookla 节点测得（\(r.node)）")
            }
        }
        guard !token.isCancelled else { return (0, nil) }
        phaseText = "正在测试上行（Cloudflare 通道，跨境仅供参考）…"
        if let u = URL(string: "https://speed.cloudflare.com/__up") {
            let meter = HTTPMeter()
            activeMeter = meter
            let t0 = Date()
            let res = await meter.measureUpload(url: u, seconds: 8, connections: 4) { bytes in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let e = Date().timeIntervalSince(t0)
                    self.elapsed = e
                    self.liveMbps = Double(bytes) * 8 / 1_000_000 / max(e, 0.4)
                }
            }
            activeMeter = nil
            return (res.mbps, res.mbps > 0 ? "上行经 Cloudflare 测得，跨境链路，数值仅供参考" : nil)
        }
        return (0, "上行测试不可用")
    }

    private func runOokla(seq: Int, token: ProcessToken) async {
        phase = .ping
        phaseText = "正在连接 Ookla 节点（约 20–40 秒，可随时点「停止」）…"
        progress = 0.1
        let sid = ooklaServerID.isEmpty ? nil : ooklaServerID
        guard let r = await OoklaEngine.run(serverID: sid, download: true, upload: true,
                                            progress: { _ in }, token: token) else {
            guard seq == runSeq else { return }
            phase = .failed
            phaseText = "Ookla 测速失败或已停止：请确认 /usr/local/bin/speedtest 存在且可访问 speedtest.net"
            return
        }
        guard seq == runSeq else { return }
        current = r
        progress = 1
        phaseText = "测试完成"
    }

    private func runApple(seq: Int, token: ProcessToken) async {
        phase = .ping
        phaseText = "正在调用 Apple networkQuality（约 20 秒）…"
        progress = 0.2
        guard let r = await NetworkQualityEngine.run(progress: { _ in }, token: token) else {
            guard seq == runSeq else { return }
            phase = .failed
            phaseText = "networkQuality 执行失败或已停止"
            return
        }
        guard seq == runSeq else { return }
        var run = r
        await fillExit(&run)
        guard seq == runSeq else { return }
        current = run
        progress = 1
        phaseText = "测试完成"
    }

    private func fillExit(_ r: inout SpeedRun) async {
        if !r.exitIP.isEmpty { return }
        if let ip = await HTTP.fetch(URL(string: "http://ip.3322.net")!, timeout: 6)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            ip.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil {
            r.exitIP = ip
        }
    }

    func loadOoklaServers() async {
        guard OoklaEngine.available else { return }
        loadingServers = true
        var list = await OoklaEngine.listServers(cnOnly: true)
        if list.isEmpty { list = await OoklaEngine.listServers(cnOnly: false) }
        ooklaServers = list
        loadingServers = false
    }

    // MARK: 首页一键体检

    func refreshHealth() {
        let last = history.first ?? (current.downMbps > 0 ? current : nil)
        health = HealthScore.evaluate(wifi: wifi, net: net, lastRun: last, lanCount: lan.hosts.count)
    }

    private func setStep(_ i: Int, _ st: CheckStep.State, _ detail: String = "") {
        guard checkSteps.indices.contains(i) else { return }
        checkSteps[i].state = st
        if !detail.isEmpty { checkSteps[i].detail = detail }
    }

    /// 一键体检：无线 → 信道 → 出口 → 延迟 → 带宽（约 15–20 秒）
    func runQuickCheck() async {
        guard !checking else { return }
        checking = true
        checkSteps = [
            CheckStep(title: "无线链路"),
            CheckStep(title: "周边信道"),
            CheckStep(title: "公网出口"),
            CheckStep(title: "出口延迟"),
            CheckStep(title: "宽带速度"),
        ]
        defer { checking = false }

        // 1 无线链路
        setStep(0, .running)
        await wifi.refresh()
        setStep(0, .done, wifi.link.powerOn && wifi.link.channel > 0
                ? "\(wifi.link.rssi) dBm" : "未连接 Wi-Fi")

        // 2 周边信道
        setStep(1, .running)
        await wifi.scanNeighbors()
        setStep(1, .done, "邻区 \(wifi.neighbors.count) 个")

        // 3 公网出口
        setStep(2, .running)
        await net.refreshProfile()
        await net.checkExits(rounds: 1)
        setStep(2, .done, net.profile.exitIPList.first ?? "未获取")

        // 4 出口延迟（精简目标，3 次采样）
        setStep(3, .running)
        await net.runLatencyMatrix(quick: true)
        let dns = net.probes.filter { $0.group.contains("DNS") && $0.ok }
        if dns.isEmpty {
            setStep(3, .failed, "无响应")
        } else {
            let avg = dns.map { $0.avgMs }.reduce(0, +) / Double(dns.count)
            setStep(3, .done, String(format: "%.0f ms", avg))
        }

        // 5 宽带速度（6 秒 / 8 连接）
        setStep(4, .running)
        if let r = await quickSpeedRun() {
            history.insert(r, at: 0)
            if history.count > 20 { history.removeLast() }
            current = r
            setStep(4, .done, "\(fmtMbps(r.downMbps)) Mbps")
        } else {
            setStep(4, .failed, "跳过")
        }

        refreshHealth()
    }

    /// 体检用的短测速（不带动画干扰，用缓存节点快速出结果）
    private func quickSpeedRun() async -> SpeedRun? {
        guard let (node, resolved) = await pickChinaNode(),
              let url = URL(string: resolved.url) else { return nil }
        var r = SpeedRun()
        r.engine = "国内多连接（体检）"
        r.node = "\(node.name) · \(node.region)"
        var lats: [Double] = []
        for _ in 0 ..< 3 {
            if let ms = await HTTP.ping(url, timeout: 5) { lats.append(ms) }
        }
        r.pingMs = lats.isEmpty ? 0 : lats.reduce(0, +) / Double(lats.count)
        let meter = HTTPMeter()
        let res = await meter.measureDownloadSmart(url: url, seconds: 6,
                                                   connections: resolved.rangeOK ? 8 : 6,
                                                   rangeHint: resolved.rangeOK)
        r.downMbps = res.mbps
        r.upMbps = 0
        r.note = "体检快速测速（6 秒 / \(resolved.rangeOK ? 8 : 6) 连接）；完整上下行请到「本机测速」"
        return r.downMbps > 0.3 ? r : nil
    }

    func copyReport(_ r: SpeedRun) -> String {
        var s = "【网络体检报告】\(r.date.formatted(date: .numeric, time: .standard))\n"
        s += "引擎：\(r.engine)\n节点：\(r.node)\n"
        s += "下行：\(fmtMbps(r.downMbps)) Mbps\n上行：\(fmtMbps(r.upMbps)) Mbps\n"
        s += "延迟：\(fmtMs(r.pingMs)) ms\n抖动：\(fmtMs(r.jitterMs)) ms\n"
        if !r.exitIP.isEmpty { s += "公网出口：\(r.exitIP) \(r.isp)\n" }
        if !r.note.isEmpty { s += "备注：\(r.note)\n" }
        return s
    }
}

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        NavigationSplitView {
            List(NavItem.allCases, selection: $app.selection) { item in
                HStack(spacing: 9) {
                    TileIcon(systemName: item.icon, gradient: Palette.gradient(for: item), size: 24)
                    Text(item.title).font(.system(size: 12.5))
                    Spacer()
                }
                .padding(.vertical, 2)
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 240, max: 300)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Divider()
                    Text("面向国内网络环境")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: "v1.1 · 本机原生工具")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            Group {
                switch app.selection ?? .home {
                case .home: DashboardView(app: app)
                case .speed: SpeedView(app: app)
                case .nodes: NodesView(tester: app.nodes)
                case .lan: LANView(scanner: app.lan)
                case .wifi: WiFiView(engine: app.wifi)
                case .info: InfoView(net: app.net)
                }
            }
            .frame(minWidth: 760, minHeight: 560)
        }
        .task {
            // 启动只做必要且不阻塞的工作：Wi-Fi 扫描（1.6–3.6 秒）改为进入页面时按需触发
            await app.net.refreshProfile()
            await app.wifi.refresh()
            app.refreshHealth()
        }
    }
}
