import SwiftUI
import Charts
import AppKit

struct WiFiView: View {
    @ObservedObject var engine: WiFiEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !engine.ssidVisible { permissionBanner }
                linkPanel
                advicePanel
                monitorPanel
                neighborPanel
                channelPanel
            }
            .padding(20)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .navigationTitle("Wi-Fi 检测分析")
        .task {
            await engine.refresh()
            await engine.scanIfStale()
        }
    }

    // MARK: 权限

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("需要「定位服务」权限才能显示 Wi-Fi 名称").font(.callout).bold()
                Text("macOS 14 起系统会隐藏网络名称（SSID/BSSID）。授权后本页可显示名称；即便不授权，信号强度、信道、噪声等分析数据依然有效。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 6) {
                Button("请求授权") { engine.requestLocationPermission() }
                Button("打开系统设置") { openLocationSettings() }
                    .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
    }

    private func openLocationSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(u)
        }
    }

    // MARK: 当前连接

    private var linkPanel: some View {
        CardBox(title: "当前连接", icon: "wifi") {
            if !engine.link.powerOn {
                Text("Wi-Fi 已关闭或未连接。若正在使用网线，请忽略此页。")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SignalBars(rssi: engine.link.rssi)
                            Text(engine.link.ssid.isEmpty ? "（未授权显示名称）" : engine.link.ssid)
                                .font(.title2).bold()
                        }
                        Text("网卡 \(engine.link.ifName)")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Gauge(value: Double(WiFiLink.score(rssi: engine.link.rssi)), in: 0 ... 100) {
                                EmptyView()
                            } currentValueLabel: {
                                Text("\(WiFiLink.score(rssi: engine.link.rssi))")
                                    .font(.caption).monospacedDigit()
                            }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(scoreColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(WiFiLink.qualityLabel(rssi: engine.link.rssi).0).font(.callout).bold()
                                Text("综合质量评分").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 260, alignment: .leading)

                    VStack(alignment: .leading, spacing: 5) {
                        KV(k: "信号强度", v: "\(engine.link.rssi) dBm", width: 76)
                        KV(k: "噪声", v: "\(engine.link.noise) dBm", width: 76)
                        KV(k: "信噪比", v: "\(engine.link.snr) dB", width: 76)
                        KV(k: "协商速率", v: "\(Int(engine.link.txRate)) Mbps", width: 76)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        KV(k: "信道", v: "\(engine.link.channel)（\(engine.link.widthMHz) MHz）", width: 76)
                        KV(k: "频段", v: engine.link.band, width: 76)
                        KV(k: "协议", v: engine.link.phy, width: 76)
                        KV(k: "加密", v: engine.link.security, width: 76)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        KV(k: "BSSID", v: engine.link.bssid, mono: true, width: 66)
                        KV(k: "国家码", v: engine.link.country, width: 66)
                        HStack {
                            Spacer()
                            Button {
                                Task { await engine.refresh(); await engine.scanNeighbors() }
                            } label: { Label("刷新", systemImage: "arrow.clockwise") }
                            .buttonStyle(.link)
                        }
                    }
                    .frame(width: 210)
                }
                if !engine.note.isEmpty {
                    Text(engine.note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scoreColor: Color {
        let s = WiFiLink.score(rssi: engine.link.rssi)
        return s >= 70 ? .green : s >= 45 ? .yellow : .red
    }

    // MARK: 建议

    private var advicePanel: some View {
        CardBox(title: "分析建议", icon: "lightbulb") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(engine.advice().enumerated()), id: \.offset) { _, a in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: a.hasPrefix("⚠️") ? "exclamationmark.triangle.fill" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(a.hasPrefix("⚠️") ? .red : .accentColor)
                        Text(a).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 实时信号

    private var monitorPanel: some View {
        CardBox(title: "实时信号曲线", icon: "chart.xyaxis.line") {
            HStack {
                Button {
                    engine.monitoring ? engine.stopMonitoring() : engine.startMonitoring()
                } label: {
                    Label(engine.monitoring ? "停止监视" : "开始监视", systemImage: engine.monitoring ? "stop.fill" : "record.circle")
                }
                .buttonStyle(.bordered)
                Spacer()
                if engine.monitoring {
                    Text("每 1 秒采样 · 已采集 \(engine.history.count) 点")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if engine.history.count > 1 {
                Chart {
                    ForEach(Array(engine.history.enumerated()), id: \.offset) { idx, item in
                        LineMark(x: .value("采样点", idx), y: .value("信号", item.1))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.blue)
                        AreaMark(x: .value("采样点", idx), y: .value("信号", item.1))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.25), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    }
                    RuleMark(y: .value("良好线", -65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.orange)
                }
                .chartYScale(domain: -95 ... -25)
                .chartXAxis(.hidden)
                .chartYAxisLabel("dBm")
                .frame(height: 170)
            } else {
                Text("点击「开始监视」可在走动中观察信号变化，用于寻找最佳路由器摆放位置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 邻居网络

    private var neighborPanel: some View {
        CardBox(title: "周边网络（共 \(engine.neighbors.count) 个）", icon: "dot.radiowaves.left.and.right") {
            Table(engine.neighbors) {
                TableColumn("网络名称") { n in
                    HStack(spacing: 6) {
                        SignalBars(rssi: n.rssi)
                        Text(n.hidden ? "（隐藏网络）" : n.ssid).lineLimit(1)
                        if n.ssid == engine.link.ssid && !n.ssid.isEmpty { Pill(text: "当前", color: .blue) }
                    }
                }
                .width(min: 130, ideal: 190)
                TableColumn("信号") { n in Text("\(n.rssi)").monospacedDigit().foregroundStyle(colorFor(n.rssi)) }.width(60)
                TableColumn("信道") { n in Text("\(n.channel)").monospacedDigit() }.width(50)
                TableColumn("带宽") { n in Text(n.widthMHz > 0 ? "\(n.widthMHz) MHz" : "—") }.width(70)
                TableColumn("频段") { n in Text(n.band) }.width(70)
                TableColumn("加密") { n in Text(n.security.isEmpty ? "—" : n.security).font(.caption) }.width(min: 90, ideal: 140)
                TableColumn("BSSID") { n in Text(n.bssid.isEmpty ? "（需定位权限）" : n.bssid).font(.system(.caption2, design: .monospaced)) }
                    .width(min: 110, ideal: 150)
            }
            .frame(height: min(CGFloat(engine.neighbors.count) * 26 + 40, 320))
            Text("说明：网络名称/BSSID 需授予定位权限（macOS 系统限制）。加密方式在未授权时只能可靠识别「开放（无密码）」与 WEP，其余如实标为需定位权限；授权后会解析 802.11 信息元素给出精确类型。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func colorFor(_ rssi: Int) -> Color {
        rssi >= -60 ? .green : rssi >= -70 ? .yellow : rssi >= -80 ? .orange : .red
    }

    // MARK: 信道占用

    private var channelPanel: some View {
        CardBox(title: "信道占用分析", icon: "chart.bar") {
            Picker("", selection: $selectedBand) {
                Text("2.4 GHz").tag("2.4 GHz")
                Text("5 GHz").tag("5 GHz")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            let load = engine.channelLoad(band: selectedBand)
            if load.isEmpty {
                Text("该频段暂未扫描到其他网络。").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(load, id: \.channel) { item in
                    BarMark(
                        x: .value("信道", String(item.channel)),
                        y: .value("网络数", item.count)
                    )
                    .foregroundStyle(item.count >= 3 ? Color.red : item.count >= 2 ? Color.orange : Color.green)
                    .annotation(position: .top) {
                        Text("\(item.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .chartYAxisLabel("网络数量")

                if selectedBand == "2.4 GHz" {
                    Text("2.4 GHz 只有 1/6/11 三个互不重叠信道。柱子越高说明该信道越拥挤，尽量让路由器固定在最矮的那根柱子上。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("5 GHz 建议优先选择柱子最矮的信道；国内低频段(36-48)通用性最好，高频段(149-165)往往更干净。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text("各信道详情：" + load.map { "\($0.channel)→\($0.count)个/最强\($0.strongest)dBm" }.joined(separator: "，"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @State private var selectedBand = "2.4 GHz"
}
