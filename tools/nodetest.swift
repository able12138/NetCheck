import Foundation

/// 节点目录真实复验：把 NodeCatalog.all 全跑一遍，打印状态/速度/失败归因
/// 用法：./tools/nodetest.sh [每节点秒数，默认 6]
@main
struct NodeTestTool {
    static func main() async {
        let secs = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 6) : 6
        let nodes = NodeCatalog.all
        print("节点目录真实复验：\(nodes.count) 个节点 · 每节点 \(Int(secs)) 秒 · 3 并发\n")
        var results: [SpeedNode] = []
        var i = 0
        while i < nodes.count {
            let batch = Array(nodes[i ..< min(i + 3, nodes.count)])
            let out = await withTaskGroup(of: (Int, SpeedNode).self) { group in
                for (k, n) in batch.enumerated() {
                    group.addTask { (k, await NodeTester.runNode(n, cached: nil, secs: secs, conns: 6)) }
                }
                var acc: [(Int, SpeedNode)] = []
                for await r in group { acc.append(r) }
                return acc.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            for (k, r) in out.enumerated() {
                let sp = r.mbps > 0 ? String(format: "%7.2f Mbps", r.mbps) : "        —"
                print(String(format: "  [%2d/%2d] %-14@ %@   %@", i + k + 1, nodes.count,
                             r.name as NSString, sp, r.status))
                if !r.why.isEmpty { print("          └─ \(r.why)") }
                results.append(r)
            }
            i += batch.count
        }

        print("\n===== 汇总 =====")
        let ok = results.filter { $0.ok == true }
        let slow = results.filter { $0.ok == false && $0.status == "极慢" }
        let waf = results.filter { $0.status.contains("WAF") }
        let redirectDead = results.filter { $0.status.contains("重定向后不可达") }
        let redirect = results.filter { $0.status.contains("重定向") && !$0.status.contains("重定向后不可达") }
        let unreach = results.filter { $0.status.contains("不可达") && !$0.status.contains("重定向后不可达") }
        let webpage = results.filter { $0.status.contains("网页") }
        let nofile = results.filter {
            ($0.status.contains("无测速文件") || $0.status.contains("无此文件")
                || $0.status.contains("目录内无") || $0.status.contains("拒绝访问")
                || $0.status.contains("响应过小") || $0.status.contains("不支持断点"))
        }
        let nodata = results.filter { $0.status == "失败" || $0.status == "测速失败" }
        print("可用            \(ok.count)   （≥ 1 Mbps）")
        print("极慢            \(slow.count)   （有数据但 < 1 Mbps）")
        print("失败(0 字节)    \(nodata.count)")
        print("被 WAF 拦截     \(waf.count)")
        print("重定向后不可达  \(redirectDead.count)")
        print("重定向异常      \(redirect.count)")
        print("节点不可达      \(unreach.count)")
        print("返回网页非文件  \(webpage.count)")
        print("无测速文件      \(nofile.count)")
        print("\n可用节点明细：")
        for n in ok.sorted(by: { $0.mbps > $1.mbps }) {
            print(String(format: "  %-14@ %7.2f Mbps", n.name as NSString, n.mbps))
        }
        let bad = waf + redirectDead + redirect + unreach + webpage + nofile
        if !bad.isEmpty {
            print("\n节点侧问题（非本机网络故障）：")
            for n in bad {
                print("  \(n.name)：\(n.status)")
            }
        }
    }
}
