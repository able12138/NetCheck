import SwiftUI

struct SpeedView: View {
    @ObservedObject var app: AppModel
    @State private var copied = false

    private var r: SpeedRun { app.current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controlPanel
                if app.testing || app.phase == .done || app.phase == .failed { progressPanel }
                metricsGrid
                detailPanel
                if !app.history.isEmpty { historyPanel }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle("本机测速")
    }

    // MARK: 控制面板

    private var controlPanel: some View {
        CardBox(title: "测速引擎", icon: "gauge.with.dots.needle.67percent") {
            Picker("", selection: $app.engineChoice) {
                ForEach(SpeedEngineChoice.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(app.testing)

            Text(app.engineChoice.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await app.startTest() }
                } label: {
                    Label(app.testing ? "测速中…" : "开始测速", systemImage: app.testing ? "hourglass" : "play.fill")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(app.testing)

                if app.testing {
                    Button {
                        app.cancelTest()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(".", modifiers: .command)
                }

                if app.engineChoice == .ookla {
                    HStack(spacing: 6) {
                        Text("节点：").font(.callout).foregroundStyle(.secondary)
                        Picker("", selection: $app.ooklaServerID) {
                            Text("自动选择（最近节点）").tag("")
                            ForEach(app.ooklaServers) { s in
                                Text("[\(s.id)] \(s.name) · \(s.sponsor)").tag(s.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                        .disabled(app.testing)
                        Button {
                            Task { await app.loadOoklaServers() }
                        } label: {
                            if app.loadingServers { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.clockwise") }
                        }
                        .disabled(app.testing || app.loadingServers)
                        .help("加载 Ookla 可用节点列表")
                    }
                }
                Spacer()
                if !app.testing, !r.node.isEmpty {
                    Button {
                        let text = app.copyReport(r)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Label(copied ? "已复制" : "复制报告", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }

    private var progressPanel: some View {
        CardBox(title: "测速进度", icon: "timer") {
            HStack(spacing: 10) {
                ProgressView(value: app.progress)
                    .progressViewStyle(.linear)
                if app.testing {
                    Text(String(format: "%.1f s", app.elapsed))
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            HStack {
                Text(app.phaseText).font(.callout).foregroundStyle(app.phase == .failed ? .red : .secondary)
                Spacer()
                if app.testing, app.liveMbps > 0 {
                    Text("实时：\(fmtMbps(app.liveMbps)) Mbps")
                        .font(.callout).monospacedDigit().foregroundStyle(.green)
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            MetricCard(title: "下行速度", value: fmtMbps(r.downMbps), unit: "Mbps",
                       icon: "arrow.down.circle.fill", color: .blue,
                       subtitle: r.node.isEmpty ? "" : r.node)
            MetricCard(title: "上行速度", value: fmtMbps(r.upMbps), unit: "Mbps",
                       icon: "arrow.up.circle.fill", color: .green,
                       subtitle: r.note.isEmpty ? "" : r.note)
            MetricCard(title: "延迟", value: fmtMs(r.pingMs), unit: "ms",
                       icon: "clock", color: .orange,
                       subtitle: r.pingMs > 0 && r.pingMs < 50 ? "国内节点，表现良好" : "")
            MetricCard(title: "抖动", value: fmtMs(r.jitterMs), unit: "ms",
                       icon: "waveform.path", color: .purple,
                       subtitle: r.jitterMs > 0 ? "数值越小越稳定" : "")
            MetricCard(title: "公网出口", value: r.exitIP.isEmpty ? "—" : r.exitIP, unit: "",
                       icon: "globe.asia.australia", color: .teal,
                       subtitle: r.isp.isEmpty ? "点击「网络诊断」查询归属" : r.isp)
            MetricCard(title: "测速引擎", value: r.engine.isEmpty ? "—" : r.engine, unit: "",
                       icon: "cpu", color: .gray,
                       subtitle: r.date.formatted(date: .omitted, time: .standard))
        }
    }

    private var detailPanel: some View {
        CardBox(title: "结果说明", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                KV(k: "下行口径", v: "国内云镜像/骨干节点多连接下载，反映国内真实宽带下行能力")
                KV(k: "上行口径", v: r.note.isEmpty ? "Ookla 上传通道或 Cloudflare 跨境通道" : r.note)
                KV(k: "单位口径", v: "按国内习惯使用十进制 Mbps（1 Mbps = 0.125 MB/s）")
                Divider().padding(.vertical, 2)
                Text("提示：测速期间请关闭下载、视频、NAS 同步等占用带宽的程序；Wi-Fi 与网线结果可能差异明显，建议分别在「网络诊断」确认瓶颈位置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var historyPanel: some View {
        CardBox(title: "历史记录（本次会话）", icon: "clock.arrow.circlepath") {
            Table(app.history) {
                TableColumn("时间") { run in
                    Text(run.date.formatted(date: .omitted, time: .standard)).monospacedDigit()
                }
                .width(90)
                TableColumn("引擎") { run in Text(run.engine) }.width(min: 90, ideal: 110)
                TableColumn("节点") { run in Text(run.node).lineLimit(1) }.width(min: 140, ideal: 200)
                TableColumn("下行") { run in Text(fmtMbps(run.downMbps)).monospacedDigit() }.width(70)
                TableColumn("上行") { run in Text(fmtMbps(run.upMbps)).monospacedDigit() }.width(70)
                TableColumn("延迟") { run in Text(fmtMs(run.pingMs)).monospacedDigit() }.width(60)
            }
            .frame(height: min(CGFloat(app.history.count) * 26 + 34, 220))
        }
    }
}
