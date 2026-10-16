import Foundation
import CoreWLAN

/// 诊断：周边网络的 informationElementData 是否可用、supportsSecurity 的实际表现
@main
struct WiFiDbg {
    static func main() {
        guard let iface = CWWiFiClient.shared().interface() else { print("无网卡"); return }
        do {
            let nets = try iface.scanForNetworks(withSSID: nil)
            print("扫描到 \(nets.count) 个网络\n")
            var i = 0
            for n in nets {
                if i >= 6 { break }
                i += 1
                let ie = n.informationElementData
                let hex = ie.map { d -> String in
                    d.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " ")
                } ?? "<nil>"
                var sup: [String] = []
                for raw in [0, 1, 2, 3, 4, 5, 9, 11, 13, 14] {
                    if let s = CWSecurity(rawValue: raw), n.supportsSecurity(s) { sup.append("\(raw)") }
                }
                print("网络 #\(i)  rssi=\(n.rssiValue) ch=\(n.wlanChannel?.channelNumber ?? 0)")
                print("  IE 长度: \(ie?.count ?? -1)")
                print("  IE 前 48B: \(hex)")
                print("  supportsSecurity 命中 rawValue: [\(sup.joined(separator: ","))]")
                print("  本解析器判定: \(WiFiEngine.securityGuess(n))")
                print("")
            }
            print("当前连接 security().rawValue = \(iface.security().rawValue)")
        } catch { print("扫描失败 \(error)") }
    }
}
