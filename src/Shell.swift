import Foundation

struct ShellResult {
    let code: Int32
    let out: String
    let err: String
    var ok: Bool { code == 0 }
    var combined: String { out.isEmpty ? err : (err.isEmpty ? out : out + "\n" + err) }
}

/// 可取消的子进程令牌
final class ProcessToken: @unchecked Sendable {
    private let lock = NSLock()
    private var proc: Process?
    private var wasCancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return wasCancelled
    }

    func attach(_ p: Process) {
        lock.lock()
        let c = wasCancelled
        if !c { proc = p }
        lock.unlock()
        if c { p.terminate() }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let p = proc
        lock.unlock()
        p?.terminate()
    }
}

/// 统一的子进程执行器（GUI 应用 PATH 不含自定义目录，这里显式注入）
enum Shell {
    static let searchPath = "/usr/local/bin:/opt/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func locate(_ name: String) -> String? {
        let fm = FileManager.default
        if name.hasPrefix("/") { return fm.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchPath.split(separator: ":") {
            let p = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func run(_ launchPath: String, _ args: [String],
                    timeout: TimeInterval = 60, stdin: String? = nil,
                    token: ProcessToken? = nil) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let path = locate(launchPath) ?? launchPath
                guard FileManager.default.isExecutableFile(atPath: path) else {
                    cont.resume(returning: ShellResult(code: 127, out: "", err: "找不到可执行文件: \(launchPath)"))
                    return
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = searchPath
                env["LC_ALL"] = "C"
                env["LANG"] = "C"
                p.environment = env
                let op = Pipe(), ep = Pipe()
                p.standardOutput = op
                p.standardError = ep
                let ip = Pipe()
                if stdin != nil { p.standardInput = ip }
                do { try p.run() } catch {
                    cont.resume(returning: ShellResult(code: -1, out: "", err: "启动失败: \(error.localizedDescription)"))
                    return
                }
                token?.attach(p)
                if let s = stdin, let d = s.data(using: .utf8) {
                    ip.fileHandleForWriting.write(d)
                    try? ip.fileHandleForWriting.close()
                }
                let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let od = op.fileHandleForReading.readDataToEndOfFile()
                let ed = ep.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                watchdog.cancel()
                cont.resume(returning: ShellResult(code: p.terminationStatus,
                                                   out: String(data: od, encoding: .utf8) ?? "",
                                                   err: String(data: ed, encoding: .utf8) ?? ""))
            }
        }
    }

    /// 运行一段时间后强制终止并返回已采集的输出（用于 dns-sd 这类不会自行退出的命令）
    /// 注意：FileHandle.availableData 会阻塞等待数据，必须用 readabilityHandler 异步收集，
    /// 否则 seconds 超时永远不生效（曾导致局域网扫描永久挂起）。
    static func runAndStop(_ launchPath: String, _ args: [String], seconds: Double) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let path = locate(launchPath) ?? launchPath
                guard FileManager.default.isExecutableFile(atPath: path) else {
                    cont.resume(returning: ""); return
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = searchPath
                p.environment = env
                let op = Pipe()
                p.standardOutput = op
                p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: ""); return }

                let buf = DataBuffer()
                let fh = op.fileHandleForReading
                fh.readabilityHandler = { h in
                    let chunk = h.availableData
                    if chunk.isEmpty { h.readabilityHandler = nil; return }
                    buf.append(chunk)
                }
                // 等待指定时长（或进程自行退出）
                let deadline = Date().addingTimeInterval(seconds)
                while Date() < deadline && p.isRunning {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if p.isRunning { p.terminate() }
                fh.readabilityHandler = nil
                buf.append(fh.readDataToEndOfFile())
                let out = buf.string
                p.waitUntilExit()
                cont.resume(returning: out)
            }
        }
    }
}

/// 线程安全的字节缓冲：`readabilityHandler` 在其它队列上回调，
/// 不能用 `var data` 捕获（Swift 6 会报 "mutation of captured var in concurrently-executing code"）
private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
