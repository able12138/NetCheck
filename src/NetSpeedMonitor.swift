import SwiftUI
import AppKit

/// 实时网速监视（对位「腾讯电脑管家」的加速球/悬浮窗，Mac 原生做法放菜单栏）
///
/// 数据来源：getifaddrs 的 AF_LINK 统计（ifi_ibytes / ifi_obytes）。
/// 注意 macOS 这两个字段是 **32 位**（4GB 回绕），速率计算必须处理回绕。
@MainActor
final class NetSpeedMonitor: ObservableObject {
    @Published var downMbps: Double = 0
    @Published var upMbps: Double = 0
    @Published var ifName: String = ""
    @Published var totalDownMB: Double = 0
    @Published var totalUpMB: Double = 0

    private var lastIn: UInt32 = 0
    private var lastOut: UInt32 = 0
    private var lastAt: Date?
    private var task: Task<Void, Never>?

    func start(ifName: String, interval: Double = 1.0) {
        self.ifName = ifName
        task?.cancel()
        lastAt = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func sample() async {
        guard !ifName.isEmpty else { return }
        let name = ifName
        let result: (UInt32, UInt32)? = await Task.detached(priority: .utility) {
            NetSpeedMonitor.bytes(ifName: name)
        }.value
        guard let (ib, ob) = result else { return }
        let now = Date()
        defer { lastIn = ib; lastOut = ob; lastAt = now }
        guard let prev = lastAt else { return }
        let dt = max(now.timeIntervalSince(prev), 0.2)

        func delta(_ cur: UInt32, _ old: UInt32) -> Double {
            if cur >= old { return Double(cur - old) }
            return Double(UInt32.max - old) + Double(cur) + 1   // 32 位回绕
        }
        let din = delta(ib, lastIn)
        let dout = delta(ob, lastOut)
        downMbps = din * 8 / 1_000_000 / dt
        upMbps = dout * 8 / 1_000_000 / dt
        totalDownMB += din / 1_048_576
        totalUpMB += dout / 1_048_576
    }

    /// 读取指定接口的累计字节数（32 位计数器）
    nonisolated static func bytes(ifName: String) -> (UInt32, UInt32)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        while let cur = p {
            let ifa = cur.pointee
            let name = String(cString: ifa.ifa_name)
            if name == ifName, let addr = ifa.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                return (d.ifi_ibytes, d.ifi_obytes)
            }
            p = ifa.ifa_next
        }
        return nil
    }

    /// 默认路由所在接口
    nonisolated static func defaultInterface() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "en0" }
        defer { freeifaddrs(ifaddr) }
        var p = ifaddr
        var best = "en0"
        while let cur = p {
            let ifa = cur.pointee
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            // 已启用、非回环、有 IPv4 的最前面一个
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, name.hasPrefix("en") {
                if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    best = name
                    break
                }
            }
            p = ifa.ifa_next
        }
        return best
    }
}

// MARK: - 菜单栏

struct MenuBarLabel: View {
    @ObservedObject var speed: NetSpeedMonitor

    private func short(_ v: Double) -> String {
        if v >= 100 { return String(format: "%.0f", v) }
        if v >= 10 { return String(format: "%.1f", v) }
        if v >= 1 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: speed.downMbps > 8 ? "arrow.down.circle.fill" : "wifi")
            if speed.downMbps > 0.02 || speed.upMbps > 0.02 {
                Text("↓\(short(speed.downMbps)) ↑\(short(speed.upMbps))")
                    .font(.system(size: 11, design: .monospaced))
            } else {
                Text("网速").font(.system(size: 11))
            }
        }
    }
}

struct MenuPanel: View {
    @ObservedObject var app: AppModel
    @ObservedObject var speed: NetSpeedMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时网速").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(speed.ifName.isEmpty ? "—" : speed.ifName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下载").font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(fmtMbps(speed.downMbps))
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Mbps").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("上传").font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(fmtMbps(speed.upMbps))
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Mbps").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text(String(format: "本次会话累计：↓ %.0f MB / ↑ %.0f MB", speed.totalDownMB, speed.totalUpMB))
                .font(.system(size: 10)).foregroundStyle(.tertiary)

            if let last = app.history.first {
                Divider()
                Text("上次测速：\(fmtMbps(last.downMbps)) / \(fmtMbps(last.upMbps)) Mbps")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(last.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }

            Divider()
            HStack(spacing: 8) {
                Button("打开主窗口") { showMain() }
                Button("立即测速") {
                    app.selection = .speed
                    showMain()
                    Task { await app.startTest() }
                }
                .disabled(app.testing)
            }
        }
        .padding(12)
        .frame(width: 250)
    }

    private func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeMain {
            w.makeKeyAndOrderFront(nil)
            break
        }
    }
}
