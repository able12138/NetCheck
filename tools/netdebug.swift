import Foundation

/// 下载引擎排障：逐步定位「0 字节」原因
@main
struct NetDebug {
    static func main() async {
        let urlStr = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "https://mirrors.cloud.tencent.com/debian-cd/current/amd64/iso-cd/debian-12.7.0-amd64-netinst.iso"

        print("目标: \(urlStr)")
        guard let url = URL(string: urlStr) else { print("URL 无效"); return }

        // 1) 普通 URLSession 小量取数
        print("\n[1] 普通 URLSession 单连接取前 64KB")
        var req = URLRequest(url: url)
        req.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        req.timeoutInterval = 15
        let t0 = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            print("    HTTP \(code)，收到 \(data.count) 字节，耗时 \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
        } catch {
            print("    失败: \(error)")
        }

        // 2) HTTPMeter 2 连接 / 6 秒
        print("\n[2] HTTPMeter 2 连接 / 6 秒")
        let meter = HTTPMeter()
        var lastBytes: Int64 = 0
        let res = await meter.measureDownload(url: url, seconds: 6, connections: 2) { b in
            lastBytes = b
        }
        print("    结果: \(String(format: "%.2f", res.mbps)) Mbps，共 \(res.bytes) 字节（回调最后 \(lastBytes)）")
        print("    状态码: \(meter.statusCodes)")
        print("    错误: \(meter.errors.isEmpty ? "无" : meter.errors.joined(separator: " | "))")

        // 3) HTTPMeter 6 连接 / 6 秒
        print("\n[3] HTTPMeter 6 连接 / 6 秒")
        let meter2 = HTTPMeter()
        let res2 = await meter2.measureDownload(url: url, seconds: 6, connections: 6)
        print("    结果: \(String(format: "%.2f", res2.mbps)) Mbps，共 \(res2.bytes) 字节")
        print("    状态码: \(meter2.statusCodes)")
        print("    错误: \(meter2.errors.isEmpty ? "无" : meter2.errors.joined(separator: " | "))")
    }
}
