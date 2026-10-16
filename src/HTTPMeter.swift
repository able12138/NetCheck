import Foundation

/// 原生多连接 HTTP 测速器：下载（Range 分段并发）与上传（多连接 POST）
/// 不依赖任何第三方二进制，可实时回传进度。
final class HTTPMeter: NSObject, URLSessionDownloadDelegate, URLSessionDataDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var session: URLSession!
    private var tasks: [URLSessionTask] = []
    private var bytesByTask: [Int: Int64] = [:]
    private var total: Int64 = 0
    private var stopAt = Date()
    private var finisher: CheckedContinuation<Void, Never>?
    private var finished = false
    private var progressHandler: ((Int64) -> Void)?
    private var mode: Mode = .download
    private var useRange = true
    private var targetURL: URL?
    private var uploadBody: Data?
    private var lastEmit = Date.distantPast

    // 诊断信息（界面不显示，自检时打印）
    private(set) var errors: [String] = []
    private(set) var statusCodes: [Int] = []

    enum Mode { case download, upload }

    /// 同步临界区（避免在异步上下文中直接调用 NSLock）
    private func sync<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: 下载测速

    func measureDownload(url: URL, seconds: Double, connections: Int,
                         useRange: Bool = true,
                         progress: ((Int64) -> Void)? = nil) async -> (mbps: Double, bytes: Int64) {
        await measure(url: url, seconds: seconds, connections: connections,
                      mode: .download, useRange: useRange, progress: progress)
    }

    /// 带自动回退：Range 被拒（部分国内镜像会直接断开）时改用整段下载多连接
    func measureDownloadSmart(url: URL, seconds: Double, connections: Int,
                              rangeHint: Bool = true,
                              progress: ((Int64) -> Void)? = nil) async -> (mbps: Double, bytes: Int64) {
        let first = await measureDownload(url: url, seconds: seconds, connections: connections,
                                          useRange: rangeHint, progress: progress)
        if first.bytes > 0 || !rangeHint { return first }
        return await measureDownload(url: url, seconds: seconds, connections: connections,
                                     useRange: false, progress: progress)
    }

    // MARK: 上传测速

    func measureUpload(url: URL, seconds: Double, connections: Int,
                       bodyMB: Double = 4,
                       progress: ((Int64) -> Void)? = nil) async -> (mbps: Double, bytes: Int64) {
        uploadBody = Data(count: Int(bodyMB * 1024 * 1024))
        return await measure(url: url, seconds: seconds, connections: connections,
                             mode: .upload, useRange: false, progress: progress)
    }

    private func measure(url: URL, seconds: Double, connections: Int, mode: Mode,
                         useRange: Bool, progress: ((Int64) -> Void)?) async -> (mbps: Double, bytes: Int64) {
        self.mode = mode
        self.useRange = useRange
        self.targetURL = url
        self.progressHandler = progress
        sync {
            bytesByTask.removeAll()
            total = 0
            finished = false
            tasks.removeAll()
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = max(connections + 2, 4)
        cfg.timeoutIntervalForRequest = seconds + 10
        cfg.timeoutIntervalForResource = seconds + 20
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)

        let started = Date()
        stopAt = started.addingTimeInterval(seconds)

        var reqs: [URLRequest] = []
        let chunk: Int64 = 64 * 1024 * 1024
        for i in 0 ..< connections {
            var r = URLRequest(url: url)
            r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                       forHTTPHeaderField: "User-Agent")
            r.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if mode == .download && useRange {
                let off = Int64(i) * chunk
                r.setValue("bytes=\(off)-\(off + chunk - 1)", forHTTPHeaderField: "Range")
            } else if mode == .upload {
                r.httpMethod = "POST"
                r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                r.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            }
            reqs.append(r)
        }

        let toStart: [URLSessionTask] = sync {
            for r in reqs {
                if mode == .download {
                    tasks.append(session.downloadTask(with: r))
                } else {
                    tasks.append(session.uploadTask(with: r, from: uploadBody ?? Data(count: 1024)))
                }
            }
            return tasks
        }
        toStart.forEach { $0.resume() }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let alreadyDone = sync { () -> Bool in
                if finished { return true }
                finisher = c
                return false
            }
            if alreadyDone { c.resume(); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.stopAll()
            }
        }

        let elapsed = Date().timeIntervalSince(started)
        let b = sync { total }
        session.invalidateAndCancel()
        progressHandler = nil
        let mbps = Double(b) * 8 / 1_000_000 / max(elapsed, 0.6)
        return (mbps, b)
    }

    /// 外部中止（用于「停止测速」按钮）
    func abort() { stopAll() }

    private func stopAll() {
        let (ts, c): ([URLSessionTask], CheckedContinuation<Void, Never>?) = sync {
            if finished { return ([], nil) }
            finished = true
            let t = tasks
            let cc = finisher
            finisher = nil
            tasks.removeAll()
            return (t, cc)
        }
        ts.forEach { $0.cancel() }
        c?.resume()
    }

    private func addBytes(task: URLSessionTask, cumulative: Int64) {
        // 限频：URLSession 每秒可回调上百次，每次都跨线程更新 UI 会让界面发卡
        // （实测 8 连接时 53.5 次/秒 → 限到 5 次/秒）
        let now = Date()
        let (t, cb): (Int64, ((Int64) -> Void)?) = sync {
            bytesByTask[task.taskIdentifier] = cumulative
            let sum = bytesByTask.values.reduce(0, +)
            total = sum
            guard now.timeIntervalSince(lastEmit) >= 0.2 else { return (sum, nil) }
            lastEmit = now
            return (sum, progressHandler)
        }
        cb?(t)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        addBytes(task: downloadTask, cumulative: totalBytesWritten)
    }

    func urlSession(_ s: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        addBytes(task: task, cumulative: totalBytesSent)
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        try? FileManager.default.removeItem(at: location)
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let code = (task.response as? HTTPURLResponse)?.statusCode {
            sync { if !statusCodes.contains(code) { statusCodes.append(code) } }
        }
        if let e = error {
            let ns = e as NSError
            if ns.code != NSURLErrorCancelled {
                sync { errors.append("\(task.taskIdentifier): \(ns.domain)#\(ns.code) \(ns.localizedDescription)") }
                return
            }
        }
        guard mode == .upload || !useRange, error == nil, Date() < stopAt else { return }
        guard let url = targetURL else { return }
        let nt: URLSessionTask? = sync {
            if finished { return nil }
            var r = URLRequest(url: url)
            r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                       forHTTPHeaderField: "User-Agent")
            if mode == .download {
                // 整段下载模式下补发新任务，保持连接持续跑满带宽
                let t = session.downloadTask(with: r)
                tasks.append(t)
                return t
            }
            r.httpMethod = "POST"
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            r.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let t = session.uploadTask(with: r, from: uploadBody ?? Data(count: 1024))
            tasks.append(t)
            return t
        }
        nt?.resume()
    }
}
