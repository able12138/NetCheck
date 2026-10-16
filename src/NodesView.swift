import SwiftUI

struct NodesView: View {
    @ObservedObject var tester: NodeTester
    @State private var selection = Set<UUID>()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if tester.running || tester.progress > 0 && tester.progress < 1 {
                ProgressView(value: tester.progress) { Text(tester.status).font(.caption) }
                    .progressViewStyle(.linear)
            }
            Table(tester.nodes, selection: $selection) {
                TableColumn("节点") { n in
                    HStack(spacing: 6) {
                        Circle().fill(dot(n)).frame(width: 7, height: 7)
                        Text(n.name)
                        if n.ok == true, n.mbps == maxMbps {
                            Pill(text: "最快", color: .green)
                        }
                    }
                }
                .width(min: 130, ideal: 170)
                TableColumn("地区") { n in Text(n.region) }.width(60)
                TableColumn("线路") { n in Text(n.isp).font(.caption) }.width(min: 70, ideal: 100)
                TableColumn("类型") { n in
                    Pill(text: n.kind.rawValue, color: n.kind == .edu ? .orange : n.kind == .isp ? .purple : .blue)
                }
                .width(70)
                TableColumn("下行速度") { n in
                    Text(speedText(n))
                        .monospacedDigit()
                        .foregroundStyle(speedColor(n))
                }
                .width(110)
                TableColumn("测速文件") { n in
                    Text(n.fileSizeMB > 0 ? String(format: "%.0f MB", n.fileSizeMB) : "—")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .width(80)
                TableColumn("状态") { n in
                    HStack(spacing: 4) {
                        Text(n.status).font(.caption)
                            .foregroundStyle(statusColor(n))
                        if !n.why.isEmpty {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .help(n.why.isEmpty ? n.status : n.why)
                }
                .width(min: 110, ideal: 130)
                TableColumn("操作") { n in
                    Button("单测") { Task { await tester.testOne(n.id) } }
                        .buttonStyle(.link)
                        .disabled(tester.running)
                }
                .width(60)
            }
            footer
        }
        .padding(20)
        .navigationTitle("宽带节点测速")
    }

    private func dot(_ n: SpeedNode) -> Color {
        if n.ok == true { return n.mbps >= 20 ? .green : .yellow }
        if n.status == "极慢" { return .orange }
        if n.ok == false { return .red }
        return .secondary.opacity(0.4)
    }

    private func speedText(_ n: SpeedNode) -> String {
        n.mbps > 0 ? fmtMbps(n.mbps) + " Mbps" : "—"
    }

    private func speedColor(_ n: SpeedNode) -> Color {
        if n.ok == true { return .primary }
        return n.status == "极慢" ? .orange : .secondary
    }

    private func statusColor(_ n: SpeedNode) -> Color {
        if n.ok == true { return .green }
        switch n.status {
        case "极慢":                 return .orange
        case "待测", "排队中", "已重置": return .secondary
        default:
            if n.status.contains("中…") { return .secondary }
            return .red
        }
    }

    /// 失败原因分类（互斥：一个节点只进一类，避免重复计数）
    enum FailKind: String {
        case waf = "被 WAF 拦截"
        case redirectDead = "重定向后不可达"
        case redirect = "重定向异常"
        case unreachable = "节点不可达"
        case webpage = "返回网页而非文件"
        case nofile = "无测速文件"
        case timeout = "请求超时"
        case other = "其他"
    }

    private func failKind(_ n: SpeedNode) -> FailKind? {
        if n.ok == true { return nil }
        let s = n.status
        if s == "极慢" { return nil }        // 单独统计，不再计入失败分类
        if s.contains("WAF") || s.contains("418") { return .waf }
        if s.contains("重定向后不可达") { return .redirectDead }
        if s.contains("重定向") { return .redirect }
        if s.contains("反爬") || s.contains("网页") { return .webpage }
        if s.contains("不可达") { return .unreachable }
        if s.contains("无测速文件") || s.contains("无此文件") || s.contains("目录内无")
            || s.contains("拒绝访问") || s.contains("响应过小") || s.contains("不支持断点") { return .nofile }
        if s.contains("超时") { return .timeout }
        if s == "待测" || s == "排队中" || s == "已重置" || s.contains("中…") { return nil }
        return .other
    }

    /// 按原因汇总（只统计已测过的节点，各类互斥）
    private var summary: String {
        let tested = tester.nodes.filter { $0.ok != nil }
        guard !tested.isEmpty else { return "" }
        let ok = tested.filter { $0.ok == true }.count
        let slow = tested.filter { $0.ok == false && $0.status == "极慢" }.count
        var counts: [FailKind: Int] = [:]
        for n in tested where failKind(n) != nil {
            counts[failKind(n)!, default: 0] += 1
        }
        var parts: [String] = ["可用 \(ok)"]
        if slow > 0 { parts.append("极慢 \(slow)") }
        for k in [FailKind.waf, .redirectDead, .redirect, .unreachable, .webpage, .nofile, .timeout, .other] {
            if let c = counts[k], c > 0 { parts.append("\(k.rawValue) \(c)") }
        }
        return "\(tested.count)/\(tester.nodes.count) 已测：" + parts.joined(separator: " · ")
    }

    private var maxMbps: Double {
        tester.nodes.filter { $0.ok == true }.map { $0.mbps }.max() ?? 0
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { await tester.testAll(selected: selection) }
                } label: {
                    Label(selection.isEmpty ? "全部节点测速" : "测选中节点（\(selection.count)）",
                          systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tester.running)

                Button("重置结果") { tester.reset(); selection.removeAll() }
                    .disabled(tester.running)

                Spacer()

                HStack(spacing: 6) {
                    Text("单节点").font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $tester.secondsPerNode, in: 3 ... 20, step: 1) {
                        Text("\(Int(tester.secondsPerNode)) 秒").monospacedDigit().frame(width: 52, alignment: .leading)
                    }
                    .controlSize(.small)
                    Stepper(value: $tester.connections, in: 2 ... 16, step: 1) {
                        Text("\(tester.connections) 连接").monospacedDigit().frame(width: 62, alignment: .leading)
                    }
                    .controlSize(.small)
                }
                .disabled(tester.running)
            }

            Text("国内 Ookla 公共节点极少（全国仅 1 个：上海电信），本页主体走国内云厂商与高校镜像骨干节点，覆盖多线 BGP、电信、联通、教育网线路。每个节点先探测可用的测速文件再限时下载，失败会**如实归因**（鼠标悬停状态列看详情）：\n• 节点不可达 —— 镜像站对本线路不通（TCP 层就不响应）　• 重定向异常 —— 直链被跳走或形成跳转环\n• 被 WAF 拦截 —— 站点防火墙把测速请求判为攻击　• 反爬挑战页 / 返回网页 —— 拿到的是网页而不是文件\n• 无测速文件 —— 目录里没有可下载的大文件　• 极慢 —— 有数据但低于 1 Mbps（镜像限速或教育网互联受限）\n镜像站速度随线路与时段波动很大，个别节点不可用**不代表你的网络有问题**。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Text(tester.status).font(.caption).foregroundStyle(.secondary)
            if !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let best = tester.nodes.first(where: { $0.ok == true }) {
                Text("最优：\(best.name)（\(best.region)） \(fmtMbps(best.mbps)) Mbps")
                    .font(.caption).foregroundStyle(.green)
            }
            Button {
                let text = report()
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "已复制" : "复制结果", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.link)
        }
    }

    private func report() -> String {
        var s = "【国内节点测速结果】\n"
        for n in tester.nodes where n.ok == true {
            s += "\(n.name)（\(n.region) \(n.isp)）：\(fmtMbps(n.mbps)) Mbps\n"
        }
        s += "\n【未达标节点及原因】\n"
        for n in tester.nodes where n.ok != true && n.ok != nil {
            s += "\(n.name)：\(n.status)\(n.why.isEmpty ? "" : "（\(n.why)）")\n"
        }
        return s
    }
}
