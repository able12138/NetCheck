import Foundation
import CoreWLAN
import CoreLocation

/// Wi-Fi 检测与分析引擎（CoreWLAN 原生，macOS 15 上 airport 已失效）
///
/// 性能约束（实测）：`scanForNetworks` 单次耗时 **1.6–3.6 秒**，
/// 早期版本在主线程直接调用 → 界面冻结 1.67 秒（主线程最大排队 1670ms）。
/// 因此所有 CoreWLAN 调用一律放进 `Task.detached`，主线程只接收结果。
@MainActor
final class WiFiEngine: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var link = WiFiLink()
    @Published var neighbors: [WiFiNeighbor] = []
    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var note: String = ""
    @Published var monitoring = false
    @Published var history: [(Date, Int)] = []
    @Published var lastScan = Date.distantPast
    @Published var scanning = false

    private let locMgr = CLLocationManager()

    override init() {
        super.init()
        locMgr.delegate = self
        authStatus = locMgr.authorizationStatus
    }

    // MARK: 定位权限（macOS 14+ 读取 SSID/BSSID 必需）

    func requestLocationPermission() {
        if authStatus == .notDetermined { locMgr.requestWhenInUseAuthorization() }
        authStatus = locMgr.authorizationStatus
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.authStatus = s
            if s == .authorized || s == .authorizedAlways {
                self.note = "已获得定位权限，可显示网络名称"
                await self.refresh()
                await self.scanNeighbors()
            }
        }
    }

    var ssidVisible: Bool { authStatus == .authorized || authStatus == .authorizedAlways }

    // MARK: 读取（CoreWLAN 一律在后台线程执行）

    func refresh() async {
        let (l, msg) = await Task.detached(priority: .userInitiated) {
            WiFiEngine.readLink()
        }.value
        link = l
        if !msg.isEmpty { note = msg }
    }

    func scanNeighbors() async {
        guard !scanning else { return }
        scanning = true
        let (list, msg) = await Task.detached(priority: .userInitiated) {
            WiFiEngine.readNeighbors()
        }.value
        neighbors = list
        note = msg
        lastScan = Date()
        scanning = false
    }

    /// 数据超过 30 秒才重新扫描（页面切回来时用，避免每次都等 2 秒）
    func scanIfStale(seconds: TimeInterval = 30) async {
        if Date().timeIntervalSince(lastScan) > seconds { await scanNeighbors() }
    }

    // MARK: 后台线程里的实际读取

    nonisolated static func readLink() -> (WiFiLink, String) {
        guard let iface = CWWiFiClient.shared().interface() else {
            return (WiFiLink(), "未找到 Wi-Fi 网卡（本机可能未安装无线网卡，或已被禁用）")
        }
        var l = WiFiLink()
        l.ifName = iface.interfaceName ?? "en?"
        l.powerOn = iface.powerOn()
        l.ssid = iface.ssid() ?? ""
        l.bssid = iface.bssid() ?? ""
        l.rssi = iface.rssiValue()
        l.noise = iface.noiseMeasurement()
        l.txRate = iface.transmitRate()
        if let ch = iface.wlanChannel() {
            l.channel = ch.channelNumber
            l.widthMHz = widthMHz(ch.channelWidth.rawValue)
            l.band = bandName(ch.channelBand.rawValue)
        }
        l.phy = phyName(iface.activePHYMode().rawValue)
        l.security = securityName(iface.security().rawValue)
        l.country = iface.countryCode() ?? ""
        return (l, "")
    }

    nonisolated static func readNeighbors() -> ([WiFiNeighbor], String) {
        guard let iface = CWWiFiClient.shared().interface() else {
            return ([], "未找到 Wi-Fi 网卡")
        }
        do {
            let set = try iface.scanForNetworks(withSSID: nil)
            var list: [WiFiNeighbor] = []
            for n in set {
                var nb = WiFiNeighbor(ssid: n.ssid ?? "", bssid: n.bssid ?? "",
                                      rssi: n.rssiValue, noise: n.noiseMeasurement,
                                      channel: n.wlanChannel?.channelNumber ?? 0,
                                      widthMHz: widthMHz(n.wlanChannel?.channelWidth.rawValue ?? 0),
                                      band: bandName(n.wlanChannel?.channelBand.rawValue ?? 0),
                                      security: "", hidden: (n.ssid ?? "").isEmpty)
                nb.security = securityGuess(n)
                list.append(nb)
            }
            let sorted = list.sorted { $0.rssi > $1.rssi }
            let auth = CLLocationManager().authorizationStatus == .authorized
                || CLLocationManager().authorizationStatus == .authorizedAlways
            let msg = (auth || sorted.isEmpty)
                ? "共扫描到 \(sorted.count) 个网络"
                : "系统已隐藏周边网络名称（需授予定位权限）；信号、信道等数据仍然有效"
            return (sorted, msg)
        } catch {
            return ([], "扫描失败：\(error.localizedDescription)")
        }
    }

    // MARK: 实时信号监视

    func startMonitoring(interval: Double = 1.0) {
        monitoring = true
        history.removeAll()
        Task {
            while monitoring {
                await refresh()
                history.append((Date(), link.rssi))
                if history.count > 300 { history.removeFirst() }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() { monitoring = false }

    // MARK: 信道分析

    /// 每个信道的邻居网络数与其平均信号（仅统计能干扰到的）
    func channelLoad(band: String) -> [(channel: Int, count: Int, avgRSSI: Int, strongest: Int)] {
        let filtered = neighbors.filter { $0.band == band && $0.channel > 0 }
        var dict: [Int: [Int]] = [:]
        for n in filtered { dict[n.channel, default: []].append(n.rssi) }
        return dict.map { (ch, rssis) in
            (ch, rssis.count, rssis.reduce(0, +) / max(rssis.count, 1), rssis.max() ?? -100)
        }.sorted { $0.channel < $1.channel }
    }

    /// 2.4G 上 1/6/11 三个非重叠信道中被占用最少的
    func best24Channel() -> Int? {
        let load = channelLoad(band: "2.4 GHz")
        var best: (Int, Int)? = nil
        for t in [1, 6, 11] {
            let overlapping: Set<Int>
            switch t {
            case 1: overlapping = [1, 2, 3, 4, 5]
            case 6: overlapping = [3, 4, 5, 6, 7, 8, 9]
            default: overlapping = [7, 8, 9, 10, 11, 12, 13]
            }
            let score = load.filter { overlapping.contains($0.channel) }.reduce(0) { $0 + $1.count }
            if best == nil || score < best!.1 { best = (t, score) }
        }
        return best?.0
    }

    func best5GChannel() -> Int? {
        let candidates = [36, 40, 44, 48, 149, 153, 157, 161, 165]
        let load = channelLoad(band: "5 GHz")
        var best: (Int, Int, Int) = (0, Int.max, 0)
        for c in candidates {
            let near = load.filter { abs($0.channel - c) <= 4 }
            let cnt = near.reduce(0) { $0 + $1.count }
            let strong = near.map { $0.strongest }.max() ?? -100
            if cnt < best.1 || (cnt == best.1 && strong > best.2) { best = (c, cnt, strong) }
        }
        return best.1 == Int.max ? nil : best.0
    }

    // MARK: 中文建议

    func advice() -> [String] {
        guard link.powerOn, link.channel > 0 else {
            return ["Wi-Fi 未连接或已关闭。若使用网线，请忽略本页；无线使用请检查 Wi-Fi 是否开启。"]
        }
        var out: [String] = []
        let (label, _) = WiFiLink.qualityLabel(rssi: link.rssi)
        out.append("当前信号 \(link.rssi) dBm（\(label)），噪声 \(link.noise) dBm，信噪比 \(link.snr) dB。"
                   + (link.snr >= 40 ? "信噪比充足，链路余量健康。" : link.snr >= 25 ? "信噪比可用，但已不宽裕。" : "信噪比偏低，容易出现速率下降与丢包。"))

        if link.rssi <= -70 {
            out.append("信号偏弱：建议靠近路由器、减少承重墙阻隔，或把路由器移出弱电箱/金属遮挡。")
        } else if link.rssi >= -55 && link.txRate < 400 && link.band == "5 GHz" {
            out.append("信号很好（\(link.rssi) dBm）但协商速率仅 \(Int(link.txRate)) Mbps，说明瓶颈不在信号强度，而在信道宽度/干扰或路由器规格。")
        }

        if link.band == "2.4 GHz" {
            let n = neighbors.filter { $0.band == "2.4 GHz" }.count
            out.append("当前使用 2.4 GHz（同频可见 \(n) 个网络）。国内 2.4G 干扰普遍严重，若路由器支持 5G 且终端在近处，建议改用 5 GHz 频段。")
            if let w = best24Channel(), link.channel != w {
                out.append("2.4G 信道建议：周边以 \(link.channel) 信道最拥挤，\(w) 信道（1/6/11 三者中最干净者）相对空闲，可在路由器中固定尝试。")
            }
        }

        if link.band == "5 GHz" && link.widthMHz <= 40 {
            out.append("5 GHz 当前带宽仅 \(link.widthMHz) MHz，可在路由器把带宽设为 80 MHz 以提升近场速率（远场或干扰大时 40 MHz 反而更稳）。")
        }

        if link.band == "5 GHz" {
            let load = channelLoad(band: "5 GHz")
            if let mine = load.first(where: { $0.channel == link.channel }), mine.count >= 3 {
                out.append("当前 5G 信道 \(link.channel) 上还有 \(mine.count - 1) 个邻近 AP，若出现掉速可尝试切换到 149/157/161 等高频段（国内 5G 高频段通常更空闲）。")
            }
            if let b = best5GChannel(), b != link.channel {
                out.append("从占用度看，5G 中 \(b) 信道目前相对空闲。")
            }
        }

        if !link.phy.isEmpty && !link.phy.contains("ax") && neighbors.contains(where: { $0.band == "5 GHz" && $0.rssi > -60 }) {
            out.append("周边已有 Wi-Fi 6（802.11ax）网络，而本机无线网卡为 \(link.phy)。即使换用 Wi-Fi 6 路由器，本机速率上限仍受网卡限制（可考虑 USB/雷电有线网卡或新机型）。")
        }

        if link.security.contains("WEP") || link.security.contains("无") {
            out.append("⚠️ 当前网络加密方式为 \(link.security)，存在安全风险；建议在路由器改用以 WPA2/WPA3 个人版加密。")
        }

        out.append("提示：Wi-Fi 只是第一跳。若信号良好但外网仍慢，请到「本机测速」验证宽带侧是否存在瓶颈。")
        return out
    }

    // MARK: 映射（nonisolated，供后台线程调用）

    nonisolated static func widthMHz(_ raw: Int) -> Int {
        switch raw {
        case 1: return 20
        case 2: return 40
        case 3: return 80
        case 4: return 160
        default: return 0
        }
    }

    nonisolated static func bandName(_ raw: Int) -> String {
        switch raw {
        case 1: return "2.4 GHz"
        case 2: return "5 GHz"
        case 3: return "6 GHz"
        default: return "未知"
        }
    }

    nonisolated static func phyName(_ raw: Int) -> String {
        switch raw {
        case 1: return "802.11a"
        case 2: return "802.11b"
        case 3: return "802.11g"
        case 4: return "802.11n"
        case 5: return "802.11ac"
        case 6: return "802.11ax"
        default: return ""
        }
    }

    nonisolated static func securityName(_ raw: Int) -> String {
        switch raw {
        case 0: return "开放（无密码）"
        case 1: return "WEP"
        case 2: return "WPA 个人版"
        case 3: return "WPA/WPA2 混合"
        case 4: return "WPA2 个人版"
        case 5: return "WPA/WPA2 个人版"
        case 6: return "动态 WEP"
        case 7: return "WPA 企业版"
        case 8: return "WPA 企业版混合"
        case 9: return "WPA2 企业版"
        case 10: return "WPA/WPA2 企业版"
        case 11: return "WPA3 个人版"
        case 12: return "WPA3 企业版"
        case 13: return "WPA3/WPA2 过渡"
        case 14: return "OWE（增强开放）"
        case 15: return "OWE 过渡"
        default: return "未知"
        }
    }

    /// 邻区加密判定
    /// 实测（macOS 15）：未授权定位时 informationElementData 恒为 nil，
    /// 且 supportsSecurity 对 rawValue 2/3/4/5/13 一律返回 true（无法区分具体加密类型）；
    /// 但 rawValue 0（开放）与 1（WEP）判断可靠 —— 因此只报能确定的部分，其余如实说明。
    nonisolated static func securityGuess(_ n: CWNetwork) -> String {
        if let ie = n.informationElementData, ie.count > 4 {
            return securityFromIE(ie)
        }
        func sup(_ raw: Int) -> Bool {
            guard let s = CWSecurity(rawValue: raw) else { return false }
            return n.supportsSecurity(s)
        }
        if sup(0) { return "开放（无密码）" }
        if sup(1) { return "WEP（推测）" }
        return "已加密·需定位权限"
    }

    /// 解析 802.11 信息元素判定加密方式
    /// （CWNetwork.supportsSecurity 在 macOS 15 上会大量误判，改为解析 RSN/WPA IE）
    nonisolated static func securityFromIE(_ data: Data?) -> String {
        guard let d = data, d.count > 4 else { return "开放（无密码）" }
        var i = 0
        var hasRSN = false, hasWPA = false, privacy = false
        var sae = false, psk = false, dot1x = false, owe = false
        while i + 2 <= d.count {
            let id = d[i]
            let len = Int(d[i + 1])
            let start = i + 2
            guard start + len <= d.count else { break }
            let body = d.subdata(in: start ..< (start + len))

            if id == 45, len >= 2 {                       // Capability Information
                let cap = UInt16(body[0]) | (UInt16(body[1]) << 8)
                privacy = (cap & 0x0010) != 0
            } else if id == 48, len >= 8 {                // RSN (WPA2/WPA3)
                hasRSN = true
                var p = 2 + 4
                let pc = Int(body[p]) | (Int(body[p + 1]) << 8)
                p += 2 + pc * 4
                if p + 2 <= body.count {
                    let ac = Int(body[p]) | (Int(body[p + 1]) << 8)
                    p += 2
                    for _ in 0 ..< ac where p + 4 <= body.count {
                        let t = body[p + 3]
                        switch t {
                        case 1: dot1x = true
                        case 2: psk = true
                        case 8: sae = true
                        case 18: owe = true
                        default: break
                        }
                        p += 4
                    }
                }
            } else if id == 221, len >= 4 {               // WPA 专用 IE
                if body[0] == 0x00, body[1] == 0x50, body[2] == 0xF2, body[3] == 0x01 { hasWPA = true }
            }
            i = start + len
        }
        if sae && psk { return "WPA3/WPA2 过渡" }
        if sae { return "WPA3 个人版" }
        if hasRSN && psk { return "WPA2 个人版" }
        if hasRSN && dot1x { return "WPA2 企业版" }
        if hasRSN { return "WPA2/WPA3" }
        if hasWPA { return "WPA 个人版" }
        if owe { return "OWE（增强开放）" }
        if privacy { return "WEP / 加密" }
        return "开放（无密码）"
    }
}
