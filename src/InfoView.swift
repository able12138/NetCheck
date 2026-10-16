import SwiftUI
import AppKit

struct InfoView: View {
    @ObservedObject var net: NetInfoCenter
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                basicPanel
                exitPanel
                latencyPanel
            }
            .padding(20)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("网络诊断")
    }

    // MARK: 本机配置

    private var basicPanel: some View {
        CardBox(title: "本机网络配置", icon: "gearshape.2") {
            VStack(alignment: .leading, spacing: 6) {
                KV(k: "默认网关", v: net.profile.gateway, mono: true)
                KV(k: "DNS 服务器", v: net.profile.dns.joined(separator: "，"), mono: true)
                if net.profile.dns.contains(where: { $0.hasPrefix("100.") || $0.hasPrefix("fd7a:") }) {
                    Text("检测到 Tailscale（MagicDNS 100.100.100.100）等隧道 DNS，域名解析可能走加密隧道，测速时请注意是否绕行。")
                        .font(.caption).foregroundStyle(.orange)
                }
                KV(k: "系统代理", v: net.profile.proxyInfo)
                if !net.profile.vpnInterfaces.isEmpty {
                    KV(k: "隧道接口", v: net.profile.vpnInterfaces.joined(separator: "，"), mono: true)
                    Text("存在隧道/VPN 接口。若测速明显低于预期，请确认流量是否被隧道绕行（部分代理会大幅降低下行）。")
                        .font(.caption).foregroundStyle(.orange)
                }
                Divider().padding(.vertical, 2)
                Text("网络接口").font(.callout).bold()
                Table(net.profile.interfaces) {
                    TableColumn("接口") { i in Text(i.name).monospaced() }.width(70)
                    TableColumn("类型") { i in Text(i.kind).font(.caption) }.width(min: 90, ideal: 120)
                    TableColumn("IPv4") { i in Text(i.ipv4.isEmpty ? "—" : i.ipv4).monospacedDigit() }.width(130)
                    TableColumn("MAC") { i in Text(i.mac.isEmpty ? "—" : i.mac).font(.system(.caption, design: .monospaced)) }
                        .width(min: 120, ideal: 150)
                    TableColumn("状态") { i in
                        Text(i.isUp ? "已启用" : "未启用").font(.caption)
                            .foregroundStyle(i.isUp ? .green : .secondary)
                    }
                    .width(60)
                }
                .frame(height: min(CGFloat(net.profile.interfaces.count) * 26 + 40, 200))

                HStack {
                    Button {
                        Task { await net.refreshProfile() }
                    } label: { Label("刷新配置", systemImage: "arrow.clockwise") }
                        .disabled(net.busy)
                    Spacer()
                    Text(net.status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 公网出口

    private var exitPanel: some View {
        CardBox(title: "公网出口与运营商", icon: "globe.asia.australia") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        Task { await net.checkExits() }
                    } label: {
                        Label(net.exitChecking ? "检测中…" : "检测公网出口", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(net.exitChecking)
                    if net.profile.exitIPList.count > 1 {
                        Pill(text: "检测到 \(net.profile.exitIPList.count) 个出口 IP", color: .orange)
                        Text("同一网络出现多个公网 IP，通常说明存在双出口/多线路策略路由或代理切换。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if net.profile.exitSamples.isEmpty {
                    Text("点击上方按钮，通过国内接口（ip.3322.net / cip.cc / ipip.net）查询出口 IP 与运营商归属。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Table(net.profile.exitSamples) {
                        TableColumn("出口 IP") { s in Text(s.ip).monospacedDigit() }.width(130)
                        TableColumn("归属地") { s in Text(s.region.isEmpty ? "—" : s.region).font(.caption) }
                            .width(min: 100, ideal: 200)
                        TableColumn("运营商") { s in Text(s.isp.isEmpty ? "—" : s.isp).font(.caption) }.width(80)
                        TableColumn("查询源") { s in Text(s.source).font(.caption2).foregroundStyle(.secondary) }.width(110)
                    }
                    .frame(height: min(CGFloat(net.profile.exitSamples.count) * 26 + 40, 180))
                }
            }
        }
    }

    // MARK: 延迟矩阵

    private var latencyPanel: some View {
        CardBox(title: "国内延迟矩阵", icon: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        Task { await net.runLatencyMatrix() }
                    } label: {
                        Label(net.busy ? "测试中…" : "开始延迟测试", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(net.busy)
                    Spacer()
                    if !net.probes.isEmpty {
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(report(), forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Label(copied ? "已复制" : "复制报告", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.link)
                    }
                }
                if net.probes.isEmpty {
                    Text("依次探测本机网关、国内公共 DNS 与国内常用网站，用于判断问题是出在局域网、运营商出口还是目标站点。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Table(net.probes) {
                        TableColumn("分组") { p in Text(p.group).font(.caption2).foregroundStyle(.secondary) }
                            .width(min: 80, ideal: 110)
                        TableColumn("目标") { p in Text(p.label).lineLimit(1) }.width(min: 90, ideal: 150)
                        TableColumn("地址") { p in Text(p.target).font(.system(.caption, design: .monospaced)) }
                            .width(min: 100, ideal: 160)
                        TableColumn("平均") { p in
                            Text(p.ok ? fmtMs(p.avgMs) + " ms" : "超时").monospacedDigit()
                                .foregroundStyle(p.ok ? latencyColor(p.avgMs) : .red)
                        }
                        .width(90)
                        TableColumn("最小/最大") { p in
                            Text(p.ok ? "\(fmtMs(p.minMs)) / \(fmtMs(p.maxMs))" : "—").monospacedDigit().font(.caption)
                        }
                        .width(100)
                        TableColumn("抖动") { p in Text(p.ok ? fmtMs(p.stddevMs) : "—").monospacedDigit() }.width(60)
                        TableColumn("丢包") { p in
                            Text(String(format: "%.0f%%", p.lossPct)).monospacedDigit()
                                .foregroundStyle(p.lossPct > 0 ? .orange : .secondary)
                        }
                        .width(60)
                    }
                    .frame(height: min(CGFloat(net.probes.count) * 26 + 40, 380))
                    Text("判读要点：网关延迟应 < 5 ms；国内公共 DNS 正常 10–50 ms；若网关正常而 DNS/站点普遍高延迟，瓶颈在宽带出口；个别站点超时通常是该站限速而非宽带故障。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func latencyColor(_ ms: Double) -> Color {
        ms < 40 ? .green : ms < 90 ? .yellow : ms < 180 ? .orange : .red
    }

    private func report() -> String {
        var s = "【网络诊断报告】\n网关：\(net.profile.gateway)\nDNS：\(net.profile.dns.joined(separator: ", "))\n代理：\(net.profile.proxyInfo)\n"
        if !net.profile.exitIPList.isEmpty {
            s += "公网出口：" + net.profile.exitIPList.joined(separator: ", ") + "\n"
        }
        s += "\n延迟矩阵：\n"
        for p in net.probes {
            s += "\(p.label)（\(p.target)）：" + (p.ok ? "\(fmtMs(p.avgMs)) ms，抖动 \(fmtMs(p.stddevMs))，丢包 \(Int(p.lossPct))%" : "超时/不可达") + "\n"
        }
        return s
    }
}
