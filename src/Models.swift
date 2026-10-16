import Foundation

// MARK: - 测速

enum SpeedPhase: String {
    case idle = "待命"
    case ping = "测量延迟"
    case download = "测试下行"
    case upload = "测试上行"
    case done = "完成"
    case failed = "失败"
}

struct SpeedRun: Identifiable {
    let id = UUID()
    var engine: String = ""
    var node: String = ""
    var downMbps: Double = 0
    var upMbps: Double = 0
    var pingMs: Double = 0
    var jitterMs: Double = 0
    var lossPct: Double = 0
    var exitIP: String = ""
    var isp: String = ""
    var date: Date = Date()
    var note: String = ""
}

// MARK: - 节点

enum NodeKind: String {
    case cloud = "云镜像"
    case edu = "教育网"
    case isp = "运营商"
}

struct SpeedNode: Identifiable {
    let id = UUID()
    var name: String          // 显示名，如「腾讯云 · 深圳」
    var region: String        // 地区
    var isp: String           // 运营商/线路
    var base: String          // 基础 URL（用于解析测速文件）
    var kind: NodeKind
    var directURL: String? = nil   // 已知直链（免解析）
    var ooklaID: String? = nil     // 该节点是 Ookla 服务器：用 speedtest 二进制测量
    // 运行期字段
    var fileURL: String? = nil
    var fileSizeMB: Double = 0
    var latencyMs: Double = 0
    var mbps: Double = 0
    var status: String = "待测"
    var why: String = ""           // 失败归因
    var ok: Bool? = nil
}

struct OoklaServer: Identifiable {
    var id: String
    var name: String
    var sponsor: String
    var cc: String
    var distanceKm: Double
    var latencyMs: Double
}

/// 节点测速文件解析结果
struct ResolvedNode {
    var url: String
    var sizeMB: Double
    var rangeOK: Bool
    var reason: String = ""      // 失败归因：节点不可达 / 重定向异常 / 无可用测速文件
    var finalURL: String = ""    // 跟随重定向后的真实地址
}

// MARK: - 局域网

struct LANHost: Identifiable {
    let id = UUID()
    var ip: String
    var mac: String = ""
    var vendor: String = ""
    var hostname: String = ""
    var openPorts: [Int] = []
    var kind: String = ""
    var isSelf: Bool = false
    var isGateway: Bool = false
    var mdnsName: String = ""
}

// MARK: - Wi-Fi

struct WiFiLink: Sendable {
    var ifName: String = ""
    var ssid: String = ""
    var bssid: String = ""
    var rssi: Int = 0
    var noise: Int = 0
    var snr: Int { rssi - noise }
    var txRate: Double = 0
    var channel: Int = 0
    var widthMHz: Int = 0
    var band: String = ""
    var phy: String = ""
    var security: String = ""
    var country: String = ""
    var powerOn: Bool = false

    static func qualityLabel(rssi: Int) -> (String, String) {
        switch rssi {
        case let r where r >= -50: return ("极佳", "green")
        case -60 ..< -50: return ("优秀", "green")
        case -70 ..< -60: return ("良好", "yellow")
        case -80 ..< -70: return ("偏弱", "orange")
        default: return ("很差", "red")
        }
    }

    static func score(rssi: Int) -> Int {
        // 分段线性打分：-45dBm 以上视为满分，-90dBm 接近 0
        // （旧版用线性式 (rssi+90)/60 会把「-47dBm 极佳」误判成 71 分而报「可优化」）
        let table: [(Int, Int)] = [(-45, 100), (-55, 90), (-65, 75), (-75, 55), (-85, 30), (-95, 10)]
        if rssi >= table[0].0 { return 100 }
        for i in 0 ..< (table.count - 1) {
            let (x1, y1) = table[i]
            let (x2, y2) = table[i + 1]
            if rssi <= x1 && rssi >= x2 {
                let t = Double(rssi - x1) / Double(x2 - x1)
                return max(0, min(100, Int((Double(y1) + t * Double(y2 - y1)).rounded())))
            }
        }
        return 5
    }
}

struct WiFiNeighbor: Identifiable, Sendable {
    let id = UUID()
    var ssid: String
    var bssid: String
    var rssi: Int
    var noise: Int
    var channel: Int
    var widthMHz: Int
    var band: String
    var security: String
    var hidden: Bool
}

// MARK: - 网络信息

struct NetInterface: Identifiable {
    let id = UUID()
    var name: String
    var kind: String
    var ipv4: String = ""
    var ipv6: String = ""
    var mac: String = ""
    var isUp: Bool = false
}

struct LatencyProbe: Identifiable {
    let id = UUID()
    var target: String
    var label: String
    var group: String
    var avgMs: Double = 0
    var minMs: Double = 0
    var maxMs: Double = 0
    var stddevMs: Double = 0
    var lossPct: Double = 0
    var ok: Bool { lossPct < 100 }
}

struct ExitSample: Identifiable {
    let id = UUID()
    var ip: String
    var region: String
    var isp: String
    var source: String
}

struct NetProfile {
    var interfaces: [NetInterface] = []
    var gateway: String = ""
    var dns: [String] = []
    var proxyInfo: String = ""
    var vpnInterfaces: [String] = []
    var exitSamples: [ExitSample] = []
    var exitIPList: [String] = []
}
