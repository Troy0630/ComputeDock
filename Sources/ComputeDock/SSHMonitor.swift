import Foundation

@MainActor
final class SSHMonitor {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var broker: PasswordBroker?
    private var buffer = Data()
    private var errors = Data()
    private var timeoutTask: Task<Void, Never>?
    private var lastReceived = Date()
    private var stopped = false
    private let onSnapshot: (Snapshot) -> Void
    private let onError: (String) -> Void

    init(onSnapshot: @escaping (Snapshot) -> Void, onError: @escaping (String) -> Void) {
        self.onSnapshot = onSnapshot
        self.onError = onError
    }

    func start(config: ServerConfig, interval: Int, password: String?) {
        do {
            guard config.validationError == nil else { throw MonitorError.message(config.validationError!) }
            guard let resource = Bundle.module.url(forResource: "collector", withExtension: "py"), let script = try? Data(contentsOf: resource) else { throw MonitorError.message("采集器资源缺失，请重新打包 App。") }
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            // Only base64 data and a bounded integer enter the remote shell command.
            let command = "python3 -u -c 'import base64;exec(compile(base64.b64decode(\"\(script.base64EncodedString())\"),\"<ComputeDock>\",\"exec\"))' --interval \(min(60, max(1, interval)))"
            runner.arguments = config.sshArguments + [command]
            runner.standardInput = FileHandle.nullDevice
            if config.authentication == "password" {
                guard let password, !password.isEmpty, password.utf8.count <= 4096, !password.contains("\n") else { throw MonitorError.message("请输入本次连接的密码。") }
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ComputeDockAskPass").path
                let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ComputeDockAskPass").path
                let executable = FileManager.default.isExecutableFile(atPath: helper) ? helper : sibling
                guard FileManager.default.isExecutableFile(atPath: executable) else { throw MonitorError.message("密码登录组件缺失，请运行完整的 App 或先执行 swift build。") }
                broker = try PasswordBroker(password: password)
                var environment = ProcessInfo.processInfo.environment
                environment["SSH_ASKPASS"] = executable
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["DISPLAY"] = "ComputeDock"
                environment["COMPUTEDOCK_AUTH_SOCKET"] = broker!.path
                runner.environment = environment
            }
            let out = Pipe(), err = Pipe()
            outputPipe = out; errorPipe = err
            runner.standardOutput = out; runner.standardError = err
            out.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                Task { @MainActor [weak self] in self?.consume(data) }
            }
            err.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                Task { @MainActor [weak self] in
                    guard let self, !self.stopped else { return }
                    self.errors.append(data)
                    if self.errors.count > 8192 { self.errors = self.errors.suffix(8192) }
                }
            }
            runner.terminationHandler = { [weak self] runner in
                let status = runner.terminationStatus
                Task { @MainActor [weak self] in
                    // Let pending pipe reads reach the main actor before displaying diagnostics.
                    try? await Task.sleep(for: .milliseconds(150))
                    guard let self, !self.stopped else { return }
                    let message = String(data: self.errors, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.fail(message.isEmpty ? "SSH 连接已结束（状态 \(status)）。请检查服务器上的 python3 和连接配置。" : message)
                }
            }
            process = runner
            try runner.run()
            broker?.authorize(processID: runner.processIdentifier)
            timeoutTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    guard let self, !self.stopped else { return }
                    if Date().timeIntervalSince(self.lastReceived) > Double(max(22, interval + 14)) {
                        let message = String(data: self.errors, encoding: .utf8) ?? ""
                        self.fail(message.isEmpty ? "采集超时。请检查网络，以及远端 python3 和 nvidia-smi 是否可运行。" : message)
                        return
                    }
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    private func consume(_ data: Data) {
        guard !stopped else { return }
        buffer.append(data)
        if buffer.count > 4 * 1024 * 1024 { fail("服务器返回的数据过大，已停止采集。"); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            guard !line.isEmpty else { continue }
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: line)
                lastReceived = Date()
                onSnapshot(snapshot)
            } catch {
                // Shell startup banners are not JSON. Do not mistake them for samples.
                if line.first == 123 { fail("采样数据格式不兼容：" + error.localizedDescription); return }
            }
        }
    }

    private func fail(_ message: String) {
        guard !stopped else { return }
        stop()
        onError(message)
    }

    func stop() {
        stopped = true
        timeoutTask?.cancel(); timeoutTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        broker?.stop(); broker = nil
        process = nil
    }
}

enum MonitorError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
