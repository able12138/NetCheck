import Foundation
import CoreWLAN

/// 主线程排队延迟探针：后台线程每 50ms 尝试跳到主线程一次，记录等待时长。
/// 主线程被同步任务占住多久，探针就排队多久 —— 这就是「界面卡不卡」的本质指标。
final class MainActorDelayProbe: @unchecked Sendable {
    private var samples: [Double] = []
    private let lock = NSLock()

    func start(intervalMs: Int = 50) -> Task<Void, Never> {
        Task.detached { [self] in
            while !Task.isCancelled {
                let t0 = Date()
                await MainActor.run { }
                let d = Date().timeIntervalSince(t0)
                lock.lock(); samples.append(d); lock.unlock()
                try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
            }
        }
    }

    var maxMs: Double {
        lock.lock(); defer { lock.unlock() }
        return (samples.max() ?? 0) * 1000
    }

    var avgMs: Double {
        lock.lock(); defer { lock.unlock() }
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count) * 1000
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
}

/// 响应性基线测量：
/// T1 主线程阻塞 —— 扫描 Wi-Fi 时主线程排队延迟（>500ms 用户就能感到卡）
/// T2 进度回调风暴 —— 测速时进度回调频率（每次回调都是一次跨线程 UI 更新）
/// T3 同步子进程 —— 局域网扫描里的同步 shell 调用在主线程上耗时
@main
struct PerfCheck {

    @MainActor
    static func main() async {
        print("===== 响应性基线 =====")

        // ---------- T1（Wi-Fi 扫描，看主线程是否被占住）----------
        let engine = WiFiEngine()
        let probe1 = MainActorDelayProbe()
        let t1 = probe1.start()
        try? await Task.sleep(nanoseconds: 300_000_000)
        var t = Date()
        await engine.scanNeighbors()
        let scanTime = Date().timeIntervalSince(t)
        try? await Task.sleep(nanoseconds: 300_000_000)
        t1.cancel()
        print(String(format: "T1 Wi-Fi 扫描：耗时 %.2fs；期间主线程最大排队 %.0fms、平均 %.0fms（样本 %d）",
                     scanTime, probe1.maxMs, probe1.avgMs, probe1.count))

        // ---------- T2 ----------
        let urlStr = "https://mirrors.cloud.tencent.com/debian-cd/current/amd64/iso-cd/debian-12.7.0-amd64-netinst.iso"
        if let u = URL(string: urlStr) {
            let lock = NSLock()
            var n = 0
            let meter = HTTPMeter()
            t = Date()
            let res = await meter.measureDownload(url: u, seconds: 5, connections: 8) { _ in
                lock.lock(); n += 1; lock.unlock()
            }
            let el = Date().timeIntervalSince(t)
            lock.lock(); let calls = n; lock.unlock()
            print(String(format: "T2 测速进度回调：%.1f 次/秒（%d 次 / %.1fs），下行 %.1f Mbps",
                         Double(calls) / el, calls, el, res.mbps))
        }

        // ---------- T3（局域网网段推断，看主线程是否被占住）----------
        let lan = LANScanner()
        let probe2 = MainActorDelayProbe()
        let t3 = probe2.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        t = Date()
        let cidr = await lan.detectSubnet()
        let d1 = Date().timeIntervalSince(t)
        t = Date()
        _ = await lan.selfIPv4()
        let d2 = Date().timeIntervalSince(t)
        try? await Task.sleep(nanoseconds: 200_000_000)
        t3.cancel()
        print(String(format: "T3 网段推断：detectSubnet %.0fms（%@）、selfIPv4 %.0fms；主线程最大排队 %.0fms",
                     d1 * 1000, cidr, d2 * 1000, probe2.maxMs))

        print("===== 测量结束 =====")
    }
}
