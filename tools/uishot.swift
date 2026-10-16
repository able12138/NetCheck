import SwiftUI
import AppKit

/// 离屏渲染各界面到 PNG（不需要屏幕录制权限，用于验证布局与文案）
@main
struct UIShot {

    @MainActor
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/netcheck_ui"
        let only: String? = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let app = AppModel()
        // ---- 填充示例数据 ----
        var run = SpeedRun()
        run.engine = "国内多连接"
        run.node = "腾讯云 · 深圳（多线 BGP）"
        run.downMbps = 37.63
        run.upMbps = 28.94
        run.pingMs = 24.8
        run.jitterMs = 5.2
        run.exitIP = "203.0.113.45"
        run.isp = "中国电信（深圳）"
        run.note = "上行经 Ookla 上海电信节点测得"
        app.current = run
        var run2 = SpeedRun()
        run2.engine = "Ookla 节点"
        run2.node = "China Telecom · Shanghai"
        run2.downMbps = 27.18
        run2.upMbps = 35.21
        run2.pingMs = 26.4
        run2.exitIP = "203.0.113.45"
        app.history = [run, run2]
        app.phase = .done
        app.phaseText = "测试完成"
        app.progress = 1

        // 节点
        let tester = app.nodes
        var nodes = tester.nodes
        // 真实复验结果（2026-10-16 运行 ./tools/nodetest.sh 所得，见 使用说明.md 第十节）
        let values: [String: (Double, String, Double)] = [
            "腾讯云": (37.36, "完成", 631), "清华 TUNA": (42.21, "完成", 756),
            "Ookla 上海电信": (20.33, "完成", 0), "华中科大": (13.90, "完成", 756),
            "齐鲁工大": (2.09, "完成", 756), "网易": (2.01, "完成", 756),
            "北京外国语": (1.71, "完成", 756), "西安交大": (0.93, "极慢", 756),
            "搜狐": (0.02, "极慢", 756), "华为云": (0, "被 WAF 拦截(418)", 0),
            "阿里云": (0, "重定向后不可达", 0), "南京大学": (0, "重定向异常", 0),
            "首都在线": (0, "节点不可达", 0), "重庆大学": (0, "节点不可达", 0),
            "中科大 USTC": (0, "返回网页(923 字节)", 0),
            "上海交大": (0, "反爬挑战页", 0),
        ]
        for i in nodes.indices {
            if let v = values[nodes[i].name] {
                nodes[i].mbps = v.0
                nodes[i].ok = v.1 == "完成" ? true : false
                nodes[i].status = v.1
                nodes[i].fileSizeMB = v.2
                if v.0 == 0 { nodes[i].why = "镜像站侧原因（已探测确认）：\(v.1)。不是你的网络故障，也不是测速误差。" }
            }
        }
        tester.nodes = nodes
        tester.status = "全部完成：7/16 个节点可用，已按下行速度排序"
        tester.progress = 1

        // 局域网
        let lan = app.lan
        lan.subnet = "192.168.1.0/24"
        lan.status = "扫描完成：发现 12 台设备，7 类 mDNS 服务"
        lan.progress = 1
        lan.mdnsServices = ["AirPlay 投屏", "AirPlay 音频", "Apple 设备", "屏幕共享(VNC)", "文件共享(SMB)", "SSH", "SFTP"]
        lan.hosts = [
            LANHost(ip: "192.168.1.1", mac: "60:aa:ef:00:00:01", vendor: "华为｜Huawei Device Co., Ltd.", hostname: "", openPorts: [53, 80, 443], kind: "路由器 / 网关", isGateway: true),
            LANHost(ip: "192.168.1.142", mac: "8e:34:b7:00:00:02", vendor: "随机 MAC（隐私保护）", hostname: "", openPorts: [22, 445, 5000, 5900, 7000], kind: "本机", isSelf: true),
            LANHost(ip: "192.168.1.8", mac: "dc:84:e9:00:00:03", vendor: "深圳厂商｜Shenzhen Qihoo Intelligent Technology", hostname: "", openPorts: [80], kind: "带 Web 界面的设备"),
            LANHost(ip: "192.168.1.15", mac: "90:6a:94:00:00:04", vendor: "杭州厂商｜hangzhou huacheng network technology", hostname: "", openPorts: [], kind: "在线设备（未开放常用端口）"),
            LANHost(ip: "192.168.1.35", mac: "cc:29:bd:00:00:05", vendor: "中兴｜zte corporation", hostname: "", openPorts: [], kind: "在线设备（未开放常用端口）"),
            LANHost(ip: "192.168.1.139", mac: "be:48:f7:00:00:06", vendor: "随机 MAC（隐私保护）", hostname: "", openPorts: [], kind: "在线设备（未开放常用端口）"),
            LANHost(ip: "192.168.1.155", mac: "f0:9f:fc:00:00:07", vendor: "SHARP Corporation", hostname: "", openPorts: [21, 80, 443, 631, 5900, 9100], kind: "网络打印机"),
        ]

        // Wi-Fi
        let wifi = app.wifi
        wifi.authStatus = .authorized
        wifi.link = WiFiLink(ifName: "en0", ssid: "MyHome-5G", bssid: "60:aa:ef:00:00:0a",
                             rssi: -47, noise: -92, txRate: 650, channel: 44, widthMHz: 80,
                             band: "5 GHz", phy: "802.11ac", security: "WPA2 个人版",
                             country: "CN", powerOn: true)
        wifi.neighbors = [
            WiFiNeighbor(ssid: "MyHome-5G", bssid: "60:aa:ef:00:00:0a", rssi: -35, noise: -92, channel: 44, widthMHz: 80, band: "5 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "ChinaNet-1A2B", bssid: "3c:46:d8:11:22:33", rssi: -52, noise: -92, channel: 1, widthMHz: 20, band: "2.4 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "CMCC-5G-Home", bssid: "a4:2b:b0:44:55:66", rssi: -56, noise: -92, channel: 36, widthMHz: 80, band: "5 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "Xiaomi_AX6000", bssid: "5c:02:14:77:88:99", rssi: -48, noise: -92, channel: 149, widthMHz: 80, band: "5 GHz", security: "WPA3/WPA2 过渡", hidden: false),
            WiFiNeighbor(ssid: "HUAWEI-2.4G", bssid: "d0:3e:5c:aa:bb:cc", rssi: -61, noise: -92, channel: 6, widthMHz: 20, band: "2.4 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "TP-LINK_5G_1F", bssid: "1c:61:b4:dd:ee:ff", rssi: -63, noise: -92, channel: 157, widthMHz: 80, band: "5 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "DIRECT-7c-HP M132", bssid: "b0:5a:da:12:34:56", rssi: -74, noise: -92, channel: 11, widthMHz: 20, band: "2.4 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "MERCURY_2.4G", bssid: "9c:53:cd:65:43:21", rssi: -75, noise: -92, channel: 10, widthMHz: 20, band: "2.4 GHz", security: "WPA/WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "Tenda_1A2B3C", bssid: "c8:3a:35:fe:dc:ba", rssi: -82, noise: -92, channel: 4, widthMHz: 20, band: "2.4 GHz", security: "WPA2 个人版", hidden: false),
            WiFiNeighbor(ssid: "", bssid: "11:22:33:44:55:66", rssi: -84, noise: -92, channel: 8, widthMHz: 40, band: "2.4 GHz", security: "WPA2 个人版", hidden: true),
        ]
        wifi.note = "共扫描到 10 个网络"
        wifi.history = sampleHistory()

        // 网络信息
        let net = app.net
        net.profile = NetProfile(
            interfaces: [
                NetInterface(name: "en0", kind: "Wi-Fi / 以太网", ipv4: "192.168.1.142", mac: "8e:34:b7:00:00:02", isUp: true),
                NetInterface(name: "en5", kind: "网络接口", ipv4: "", mac: "8c:16:45:00:11:22", isUp: true),
                NetInterface(name: "utun4", kind: "VPN / 隧道", ipv4: "100.64.0.1", isUp: true),
            ],
            gateway: "192.168.1.1",
            dns: ["100.100.100.100", "223.5.5.5", "223.6.6.6"],
            proxyInfo: "未启用系统代理",
            vpnInterfaces: ["utun4"],
            exitSamples: [
                ExitSample(ip: "203.0.113.45", region: "中国 广东 深圳", isp: "电信", source: "cip.cc"),
                ExitSample(ip: "203.0.113.45", region: "", isp: "", source: "ip.3322.net"),
                ExitSample(ip: "198.51.100.7", region: "中国 广东", isp: "联通", source: "ip.3322.net"),
            ],
            exitIPList: ["198.51.100.7", "203.0.113.45"]
        )
        net.probes = [
            LatencyProbe(target: "192.168.1.1", label: "本机网关（局域网）", group: "第一跳", avgMs: 3.7, minMs: 3.2, maxMs: 4.9, stddevMs: 0.4, lossPct: 0),
            LatencyProbe(target: "223.5.5.5", label: "阿里公共 DNS", group: "国内公共 DNS", avgMs: 12.4, minMs: 11.1, maxMs: 15.2, stddevMs: 1.1, lossPct: 0),
            LatencyProbe(target: "119.29.29.29", label: "腾讯 DNSPod", group: "国内公共 DNS", avgMs: 18.9, minMs: 17.4, maxMs: 22.6, stddevMs: 1.4, lossPct: 0),
            LatencyProbe(target: "114.114.114.114", label: "114 DNS", group: "国内公共 DNS", avgMs: 21.7, minMs: 19.8, maxMs: 26.3, stddevMs: 1.9, lossPct: 0),
            LatencyProbe(target: "180.76.76.76", label: "百度 DNS", group: "国内公共 DNS", avgMs: 24.5, minMs: 22.1, maxMs: 30.4, stddevMs: 2.2, lossPct: 0),
            LatencyProbe(target: "1.2.4.8", label: "CNNIC DNS", group: "国内公共 DNS", avgMs: 33.8, minMs: 31.2, maxMs: 41.0, stddevMs: 2.6, lossPct: 0),
            LatencyProbe(target: "www.baidu.com", label: "百度", group: "国内常用网站", avgMs: 26.1, minMs: 24.5, maxMs: 31.2, stddevMs: 1.7, lossPct: 0),
            LatencyProbe(target: "www.taobao.com", label: "淘宝", group: "国内常用网站", avgMs: 31.4, minMs: 28.9, maxMs: 39.7, stddevMs: 2.8, lossPct: 0),
            LatencyProbe(target: "www.qq.com", label: "腾讯网", group: "国内常用网站", avgMs: 28.2, minMs: 26.4, maxMs: 34.1, stddevMs: 2.1, lossPct: 0),
            LatencyProbe(target: "www.163.com", label: "网易", group: "国内常用网站", avgMs: 0, minMs: 0, maxMs: 0, stddevMs: 0, lossPct: 100),
        ]

        // 首页体检数据
        app.health = HealthScore.evaluate(wifi: wifi, net: net, lastRun: app.history.first, lanCount: lan.hosts.count)
        app.checkSteps = [
            CheckStep(title: "无线链路", state: .done, detail: "-47 dBm"),
            CheckStep(title: "周边信道", state: .done, detail: "邻区 12 个"),
            CheckStep(title: "公网出口", state: .done, detail: "203.0.113.45"),
            CheckStep(title: "出口延迟", state: .done, detail: "22 ms"),
            CheckStep(title: "宽带速度", state: .done, detail: "37.63 Mbps"),
        ]
        app.progress = 1

        // ---- 渲染 ----
        func want(_ k: String) -> Bool { only == nil || only == k }
        if want("home") { render(RootPreview(app: app, item: .home), "00-home", outDir) }
        if want("speed") { render(RootPreview(app: app, item: .speed), "01-speedtest", outDir) }
        if want("nodes") { render(NodesView(tester: tester), "02-nodes", outDir) }
        if want("lan") { render(LANView(scanner: lan), "03-lan", outDir) }
        if want("wifi") { render(WiFiView(engine: wifi), "04-wifi", outDir) }
        if want("info") { render(InfoView(net: net), "05-diagnostics", outDir) }

        print("已输出到 \(outDir)")
    }

    @MainActor
    static func render(_ view: some View, _ name: String, _ dir: String) {
        let size = NSSize(width: 1000, height: 820)
        let hosting = NSHostingView(rootView: AnyView(
            view
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        ))
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.title = name
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))   // 移到屏幕外，不打扰用户
        window.orderFront(nil)

        // 让 SwiftUI 完成布局与绘制
        for _ in 0 ..< 6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        }

        var wrote = false
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                let path = dir + "/" + name + ".png"
                try? png.write(to: URL(fileURLWithPath: path))
                print("已渲染 \(name) → \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
                wrote = true
            }
        }
        if !wrote { print("渲染失败: \(name)") }
        window.orderOut(nil)
        window.close()
    }
}

/// 生成示例信号曲线
func sampleHistory() -> [(Date, Int)] {
    var out: [(Date, Int)] = []
    for i in 0 ..< 40 {
        let t = Date().addingTimeInterval(Double(i - 40))
        var rssi = -47 + Int(3.0 * sin(Double(i) / 3.0))
        if i > 25 { rssi -= 4 }
        out.append((t, rssi))
    }
    return out
}

/// 带侧边栏的整窗预览
struct RootPreview: View {
    @ObservedObject var app: AppModel
    var item: NavItem = .speed

    var body: some View {
        NavigationSplitView {
            List(NavItem.allCases, selection: .constant(item)) { i in
                HStack(spacing: 9) {
                    TileIcon(systemName: i.icon, gradient: Palette.gradient(for: i), size: 24)
                    Text(i.title).font(.system(size: 12.5))
                    Spacer()
                }
                .padding(.vertical, 2)
                .tag(i)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 205, ideal: 240, max: 300)
        } detail: {
            switch item {
            case .home: DashboardView(app: app)
            case .speed: SpeedView(app: app)
            case .nodes: NodesView(tester: app.nodes)
            case .lan: LANView(scanner: app.lan)
            case .wifi: WiFiView(engine: app.wifi)
            case .info: InfoView(net: app.net)
            }
        }
    }
}
