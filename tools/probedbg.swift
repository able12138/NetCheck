import Foundation

/// probe() 调试：打印 curl 原始输出 + 解析结果
@main
struct ProbeDebug {
    static func main() async {
        let urls = [
            ("华为云", "https://mirrors.huaweicloud.com/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso"),
            ("中科大", "https://mirrors.ustc.edu.cn/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso"),
            ("上海交大", "https://mirror.sjtu.edu.cn/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso"),
            ("阿里云", "https://mirrors.aliyun.com/debian-cd/current/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso"),
        ]
        let curl = Shell.locate("curl") ?? "/usr/bin/curl"
        for (name, u) in urls {
            print("\n========== \(name) ==========")
            // 原始 curl 输出
            let raw = await Shell.run(curl, ["-sL", "-o", "/dev/null", "-m", "8",
                                             "--range", "0-524287", "-D", "-", "-A", HTTP.ua,
                                             "-w", "\n##CODE=%{http_code} BYTES=%{size_download} FINAL=%{url_effective}",
                                             u], timeout: 14)
            print("exit=\(raw.code)  stdout=\(raw.out.count)字  stderr=\(raw.err.prefix(120))")
            let head = raw.out.split(separator: "\n").prefix(12).joined(separator: " | ")
            print("前几行: \(head.prefix(420))")
            print("末行: \(raw.out.split(separator: "\n").last.map(String.init) ?? "无")")
            // 解析结果
            let pr = await NodeCatalog.probe(u)
            print("→ probe: url=\(pr.url.isEmpty ? "空" : "OK") size=\(String(format: "%.1f", pr.sizeMB))MB range=\(pr.rangeOK) reason=\(pr.reason)")
        }
    }
}
