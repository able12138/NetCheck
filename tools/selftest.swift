import Foundation

/// 引擎自检（不依赖 GUI）：逐项跑真实网络操作并打印结果
@main
struct SelfTest {

    @MainActor
    static func main() async {
        let args = Set(CommandLine.arguments.dropFirst())
        let only = args.isEmpty ? nil : args

        func want(_ name: String) -> Bool { only == nil || only!.contains(name) }
        func head(_ t: String) { print("\n===== \(t) =====") }

        if want("wifi") {
            head("Wi-Fi 引擎")
            let engine = WiFiEngine()
            await engine.refresh()
            let l = engine.link
            print("网卡: \(l.ifName) 开机: \(l.powerOn) 信号: \(l.rssi) dBm 噪声: \(l.noise) dBm 信噪比: \(l.snr) dB")
            print("信道: \(l.channel) 带宽: \(l.widthMHz) MHz 频段: \(l.band) 协议: \(l.phy) 速率: \(Int(l.txRate)) Mbps")
            print("加密: \(l.security) 国家码: \(l.country) 评分: \(WiFiLink.score(rssi: l.rssi))")
            await engine.scanNeighbors()
            print("周边网络: \(engine.neighbors.count) 个")
            for n in engine.neighbors.prefix(6) {
                print("  \(n.ssid.isEmpty ? "(名称隐藏)" : n.ssid)\t\(n.rssi)dBm\tch\(n.channel)\t\(n.band)\t\(n.widthMHz)MHz\t\(n.security)")
            }
            print("2.4G 各信道负载: \(engine.channelLoad(band: "2.4 GHz").map { "\($0.channel):\($0.count)" }.joined(separator: " "))")
            print("建议条数: \(engine.advice().count)")
            for a in engine.advice().prefix(4) { print("  · \(a)") }
        }

        if want("nodes") {
            head("国内节点解析与测速")
            for name in ["腾讯云", "华为云", "网易", "搜狐"] {
                guard let n = NodeCatalog.all.first(where: { $0.name == name }) else { continue }
                let t0 = Date()
                if let r = await NodeCatalog.resolve(n) {
                    print("\(name) 解析成功（\(String(format: "%.1f", Date().timeIntervalSince(t0)))s）: \(String(format: "%.0f", r.sizeMB)) MB  断点续传=\(r.rangeOK)")
                    print("   \(r.url)")
                    let meter = HTTPMeter()
                    let res = await meter.measureDownloadSmart(url: URL(string: r.url)!, seconds: 6,
                                                               connections: 6, rangeHint: r.rangeOK)
                    print("   实测下行: \(String(format: "%.2f", res.mbps)) Mbps（\(res.bytes / 1048576) MB / 6s，6 连接）")
                } else {
                    print("\(name) 解析失败（无可用大文件）")
                }
            }
        }

        if want("ookla") {
            head("Ookla 引擎")
            print("二进制可用: \(OoklaEngine.available) 路径: \(OoklaEngine.binaryPath ?? "-")")
            let cn = await OoklaEngine.listServers(cnOnly: true)
            print("中国节点数: \(cn.count)")
            for s in cn { print("  [\(s.id)] \(s.name) · \(s.sponsor) 延迟 \(s.latencyMs)ms") }
            let all = await OoklaEngine.listServers(cnOnly: false)
            print("默认列表节点数: \(all.count)")
            for s in all.prefix(3) { print("  [\(s.id)] \(s.name) \(s.cc) · \(s.sponsor)") }
        }

        if want("lan") {
            head("局域网扫描")
            let scanner = LANScanner()
            let cidr = await scanner.detectSubnet()
            let selfIP = await scanner.selfIPv4()
            let gw = await scanner.defaultGateway()
            print("自动识别网段: \(cidr)  本机: \(selfIP)  网关: \(gw)")
            await scanner.scan(custom: cidr)
            print("发现设备: \(scanner.hosts.count) 台")
            print("IP\t\tMAC\t\t厂商\t\t主机名\t类型\t端口")
            for h in scanner.hosts {
                print("\(h.ip)\t\(h.mac)\t\(h.vendor)\t\(h.hostname)\t\(h.kind)\t\(h.openPorts.map(String.init).joined(separator: ","))")
            }
            print("mDNS 服务: \(scanner.mdnsServices.joined(separator: "、"))")
            print("厂商库自检: 60:aa:ef:00:00:01 → \(OUIDB.friendlyVendor(OUIDB.shared.vendor(for: "60:aa:ef:00:00:01")) ?? "nil")")
            print("厂商库自检: 8c:17:59:00:00:08 → \(OUIDB.friendlyVendor(OUIDB.shared.vendor(for: "8c:17:59:00:00:08")) ?? "nil")")
        }

        if want("info") {
            head("网络信息")
            let net = NetInfoCenter()
            await net.refreshProfile()
            print("网关: \(net.profile.gateway)")
            print("DNS: \(net.profile.dns.joined(separator: ", "))")
            print("代理: \(net.profile.proxyInfo)")
            print("隧道接口: \(net.profile.vpnInterfaces.joined(separator: ", "))")
            for i in net.profile.interfaces {
                print("  接口 \(i.name) \(i.kind) ipv4=\(i.ipv4) mac=\(i.mac) up=\(i.isUp)")
            }
            await net.checkExits()
            print("出口样本: \(net.profile.exitSamples.map { "\($0.ip)/\($0.region)/\($0.isp)via \($0.source)" }.joined(separator: " ; "))")
            print("去重出口: \(net.profile.exitIPList.joined(separator: ", "))")
        }

        if want("latency") {
            head("延迟矩阵")
            let net = NetInfoCenter()
            await net.refreshProfile()
            await net.runLatencyMatrix()
            for p in net.probes {
                print("\(p.group)\t\(p.label)\t\(p.target)\t" + (p.ok ? "\(String(format: "%.1f", p.avgMs))ms 抖动\(String(format: "%.1f", p.stddevMs)) 丢包\(Int(p.lossPct))%" : "超时"))
            }
        }

        if want("nq") {
            head("networkQuality")
            if let r = await NetworkQualityEngine.run(progress: { _ in }) {
                print("下行 \(r.downMbps) 上行 \(r.upMbps) 延迟 \(r.pingMs)\n\(r.note)")
            } else {
                print("执行失败")
            }
        }

        print("\n自检结束")
    }
}
