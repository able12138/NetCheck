import SwiftUI

struct DashboardView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    checkCard
                        .frame(width: 330)
                    statusGrid
                }
                toolbox
                if !app.health.problems.isEmpty { problemCard }
            }
            .padding(18)
            .frame(maxWidth: 1020, alignment: .leading)
        }
        .navigationTitle("首页")
        .task { app.refreshHealth() }
    }

    // MARK: 一键体检

    private var checkCard: some View {
        CardBox(title: "网络体检", icon: "checkmark.shield", accent: Palette.blue) {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    ScoreRing(score: app.health.score, grade: app.health.grade,
                              color: app.health.gradeColor)
                    Spacer()
                }
                Text(app.health.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await app.runQuickCheck() }
                } label: {
                    HStack(spacing: 6) {
                        if app.checking {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(app.checking ? "体检中…" : "一键体检")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.blue)
                .disabled(app.checking)

                if !app.checkSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(app.checkSteps) { step in
                            HStack(spacing: 6) {
                                Image(systemName: icon(step.state))
                                    .font(.system(size: 10))
                                    .foregroundStyle(color(step.state))
                                Text(step.title).font(.system(size: 11))
                                Spacer()
                                if !step.detail.isEmpty {
                                    Text(step.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func icon(_ s: CheckStep.State) -> String {
        switch s {
        case .pending: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private func color(_ s: CheckStep.State) -> Color {
        switch s {
        case .pending: return .secondary
        case .running: return Palette.blue
        case .done: return .green
        case .failed: return .orange
        }
    }

    // MARK: 状态卡

    private var statusGrid: some View {
        let link = app.wifi.link
        let last = app.history.first
        let dns = app.net.probes.filter { $0.group.contains("DNS") && $0.ok }
        let avgLatency = dns.isEmpty ? 0 : dns.map { $0.avgMs }.reduce(0, +) / Double(dns.count)

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatusCard(title: "无线信号",
                       value: link.powerOn && link.channel > 0 ? "\(link.rssi)" : "—",
                       unit: link.powerOn && link.channel > 0 ? "dBm" : "",
                       caption: link.powerOn && link.channel > 0
                           ? "\(link.ssid.isEmpty ? "名称需定位权限" : link.ssid) · \(link.band) 信道 \(link.channel)"
                           : "未连接 Wi-Fi（可能使用网线）",
                       icon: "wifi", color: Palette.blue,
                       state: link.powerOn && link.channel > 0
                           ? (WiFiLink.score(rssi: link.rssi) >= 75 ? "正常" : "注意") : "未测")

            StatusCard(title: "宽带上/下行",
                       value: last == nil ? "—" : fmtMbps(last!.downMbps),
                       unit: last == nil ? "" : "Mbps",
                       caption: last == nil ? "尚未测速，可在「本机测速」运行"
                           : "上行 \(fmtMbps(last!.upMbps)) Mbps · \(last!.node)",
                       icon: "speedometer", color: Palette.cyan,
                       state: last == nil ? "未测" : (HealthScore.downloadScore(last!.downMbps) >= 75 ? "正常" : "注意"))

            StatusCard(title: "出口延迟",
                       value: avgLatency > 0 ? fmtMs(avgLatency) : "—",
                       unit: avgLatency > 0 ? "ms" : "",
                       caption: avgLatency > 0 ? "国内公共 DNS 平均" : "可在「网络诊断」运行延迟测试",
                       icon: "clock", color: Palette.purple,
                       state: avgLatency == 0 ? "未测" : (avgLatency < 40 ? "正常" : "注意"))

            StatusCard(title: "局域网设备",
                       value: app.lan.hosts.isEmpty ? "—" : "\(app.lan.hosts.count)",
                       unit: app.lan.hosts.isEmpty ? "" : "台",
                       caption: app.lan.hosts.isEmpty ? "尚未扫描"
                           : "含路由器与 \(max(0, app.lan.hosts.count - 1)) 台其他设备",
                       icon: "desktopcomputer", color: Palette.green,
                       state: app.lan.hosts.isEmpty ? "未测" : "正常")
        }
    }

    // MARK: 工具箱

    private var toolbox: some View {
        CardBox(title: "工具箱", icon: "square.grid.2x2", accent: Palette.purple) {
            HStack(spacing: 10) {
                ForEach(NavItem.allCases.filter { $0 != .home }) { item in
                    Button {
                        app.selection = item
                    } label: {
                        ToolTile(item: item, subtitle: subtitle(item))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private func subtitle(_ item: NavItem) -> String {
        switch item {
        case .home: return ""
        case .speed: return "上下行真实测速"
        case .nodes: return "国内 15 个节点"
        case .lan: return "设备与端口扫描"
        case .wifi: return "信号与信道分析"
        case .info: return "出口与延迟矩阵"
        }
    }

    // MARK: 问题与建议

    private var problemCard: some View {
        CardBox(title: "可优化项", icon: "exclamationmark.triangle", accent: Palette.orange) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(app.health.problems.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Palette.orange).padding(.top, 5)
                        Text(p).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// 体检步骤
struct CheckStep: Identifiable {
    enum State { case pending, running, done, failed }
    let id = UUID()
    var title: String
    var state: State = .pending
    var detail: String = ""
}
