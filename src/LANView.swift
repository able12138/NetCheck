import SwiftUI

struct LANView: View {
    @ObservedObject var scanner: LANScanner
    @State private var subnetInput = ""
    @State private var selection = Set<UUID>()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if scanner.running || (scanner.progress > 0 && scanner.progress < 1) {
                ProgressView(value: scanner.progress) { Text(scanner.status).font(.caption) }
                    .progressViewStyle(.linear)
            }
            Table(scanner.hosts, selection: $selection) {
                TableColumn("设备") { h in
                    HStack(spacing: 6) {
                        Image(systemName: icon(h))
                            .foregroundStyle(h.isGateway ? .orange : h.isSelf ? .blue : .secondary)
                        Text(h.kind.isEmpty ? "在线设备" : h.kind).lineLimit(1)
                    }
                }
                .width(min: 150, ideal: 195)
                TableColumn("IP 地址") { h in Text(h.ip).monospacedDigit() }.width(120)
                TableColumn("MAC 地址") { h in Text(h.mac.isEmpty ? "—" : h.mac).font(.system(.caption, design: .monospaced)) }
                    .width(150)
                TableColumn("厂商") { h in Text(h.vendor).font(.caption).lineLimit(1) }.width(min: 90, ideal: 150)
                TableColumn("主机名") { h in Text(h.hostname.isEmpty ? "—" : h.hostname).font(.caption).lineLimit(1) }
                    .width(min: 100, ideal: 170)
                TableColumn("开放端口") { h in
                    Text(h.openPorts.isEmpty ? "—" : h.openPorts.map(String.init).joined(separator: ", "))
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 160)
            }
            footer
        }
        .padding(20)
        .navigationTitle("局域网设备")
        .task {
            if subnetInput.isEmpty { subnetInput = await scanner.detectSubnet() }
        }
    }

    private func icon(_ h: LANHost) -> String {
        if h.isGateway { return "wifi.router" }
        if h.isSelf { return "laptopcomputer" }
        let k = h.kind
        if k.contains("iPhone") || k.contains("iPad") { return "iphone" }
        if k.contains("打印") { return "printer" }
        if k.contains("NAS") { return "externaldrive.connected.to.line.below" }
        if k.contains("Windows") { return "pc" }
        if k.contains("智能") { return "homekit" }
        if k.contains("投屏") { return "appletv" }
        if k.contains("Apple") { return "apple.logo" }
        if k.contains("Linux") { return "terminal" }
        if k.contains("路由器") || k.contains("网络") { return "network" }
        return "desktopcomputer"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await scanner.scan(custom: subnetInput) }
                } label: {
                    Label(scanner.running ? "扫描中…" : "开始扫描", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanner.running)

                HStack(spacing: 4) {
                    Text("网段").font(.callout).foregroundStyle(.secondary)
                    TextField("192.168.1.0/24", text: $subnetInput)
                        .frame(width: 160)
                        .textFieldStyle(.roundedBorder)
                        .disabled(scanner.running)
                    Button {
                        Task { subnetInput = await scanner.detectSubnet() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("自动识别本机所在网段")
                        .disabled(scanner.running)
                }

                Toggle("端口指纹识别", isOn: $scanner.deepProbe)
                    .toggleStyle(.checkbox)
                    .disabled(scanner.running)

                Spacer()
            }

            if !scanner.mdnsServices.isEmpty {
                HStack(spacing: 6) {
                    Text("mDNS 服务：").font(.caption).foregroundStyle(.secondary)
                    ForEach(scanner.mdnsServices.prefix(10), id: \.self) { s in
                        Pill(text: s, color: .purple)
                    }
                }
            }

            Text("扫描原理：ARP 表 + ICMP 存活探测 + 反向 DNS + 常用端口/服务指纹。可在路由器后台关闭「AP 隔离」后获得更完整结果；设备未开放端口时仍会显示为「在线设备」。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text(scanner.status).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !scanner.hosts.isEmpty {
                Text("共 \(scanner.hosts.count) 台").font(.caption).foregroundStyle(.secondary)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(report(), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制清单", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.link)
            }
        }
    }

    private func report() -> String {
        var s = "【局域网设备清单】网段 \(scanner.subnet)\n"
        for h in scanner.hosts {
            s += "\(h.ip)\t\(h.mac)\t\(h.vendor)\t\(h.hostname)\t\(h.kind)"
            if !h.openPorts.isEmpty { s += "\t端口:\(h.openPorts.map(String.init).joined(separator: ","))" }
            s += "\n"
        }
        if !scanner.mdnsServices.isEmpty {
            s += "mDNS 服务：" + scanner.mdnsServices.joined(separator: "、") + "\n"
        }
        return s
    }
}
