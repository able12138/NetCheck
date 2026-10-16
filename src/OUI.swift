import Foundation

/// IEEE OUI 厂商库（随 App 打包，离线查询）
///
/// 并发说明：`map` 首次查询时惰性构建、之后只读；用锁保护，故标记 `@unchecked Sendable`。
final class OUIDB: @unchecked Sendable {
    static let shared = OUIDB()
    private var map: [String: String] = [:]
    private let lock = NSLock()

    private init() {}

    private func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard map.isEmpty else { return }
        var candidates: [URL] = []
        if let u = Bundle.main.url(forResource: "ieee-oui", withExtension: "txt") { candidates.append(u) }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("ieee-oui.txt"))
        candidates.append(exeDir.appendingPathComponent("../Resources/ieee-oui.txt"))
        var text: String?
        for c in candidates {
            if let t = try? String(contentsOf: c, encoding: .utf8), !t.isEmpty { text = t; break }
        }
        guard let content = text else { return }
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let key = parts[0].uppercased()
            guard key.count == 6 || key.count == 7 || key.count == 9 else { continue }
            let vendor = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            map[key] = vendor
        }
    }

    func vendor(for mac: String) -> String? {
        loadIfNeeded()
        let hex = mac.uppercased().replacingOccurrences(of: ":", with: "")
        guard hex.count >= 6 else { return nil }
        lock.lock(); defer { lock.unlock() }
        if hex.count >= 9, let v = map[String(hex.prefix(9))] { return v }
        if hex.count >= 7, let v = map[String(hex.prefix(7))] { return v }
        return map[String(hex.prefix(6))]
    }

    /// 是否为「本地管理地址」（即随机化 MAC，iPhone/Android/Win10+ 隐私保护会这么干）
    static func isRandomMAC(_ mac: String) -> Bool {
        let hex = mac.uppercased().replacingOccurrences(of: ":", with: "")
        guard hex.count >= 2, let v = UInt8(String(hex.prefix(2)), radix: 16) else { return false }
        return (v & 0x02) != 0
    }

    /// 面向国内的厂商中文名精简
    static func friendlyVendor(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "未知厂商" }
        let rules: [(String, String)] = [
            ("Xiaomi", "小米"), ("Beijing Xiaomi", "小米"), ("Huami", "华米"),
            ("Huawei", "华为"), ("HONOR", "荣耀"), ("Shenzhen", "深圳厂商"),
            ("TP-LINK", "TP-LINK"), ("Tp-link", "TP-LINK"), ("Mercury", "水星"),
            ("Tenda", "腾达"), ("H3C", "新华三"), ("Ruijie", "锐捷"),
            ("ZTE", "中兴"), ("Fiberhome", "烽火"), ("China Mobile", "中国移动"),
            ("China Telecom", "中国电信"), ("China Unicom", "中国联通"),
            ("Apple", "Apple"), ("Samsung", "三星"), ("OPPO", "OPPO"), ("vivo", "vivo"),
            ("OnePlus", "一加"), ("Realme", "真我"), ("Meizu", "魅族"),
            ("Intel", "Intel"), ("Broadcom", "Broadcom"), ("Qualcomm", "高通"),
            ("ESPRESSIF", "乐鑫（智能硬件）"), ("Tuya", "涂鸦智能"),
            ("Synology", "群晖"), ("QNAP", "威联通"), ("Seagate", "希捷"),
            ("Western Digital", "西部数据"), ("Raspberry", "树莓派"),
            ("Sonos", "Sonos"), ("Amazon", "亚马逊"), ("Google", "Google"),
            ("Netgear", "网件"), ("NETGEAR", "网件"), ("ASUS", "华硕"),
            ("Phicomm", "斐讯"), ("Ubiquiti", "优倍快"), ("Ecobee", "Ecobee"),
            ("Hangzhou", "杭州厂商"), ("Dongguan", "东莞厂商"),
            ("Hon Hai", "富士康"), ("Foxconn", "富士康"),
        ]
        for (k, v) in rules where r.localizedCaseInsensitiveContains(k) { return "\(v)｜\(r)" }
        return r
    }
}
