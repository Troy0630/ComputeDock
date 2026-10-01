import Foundation

struct ServerConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var host: String
    var user: String = ""
    var port: String = ""
    var identityFile: String = ""
    var authentication: String = "key"

    var target: String { user.isEmpty ? host : "\(user)@\(host)" }
    var validationError: String? {
        let validHost = !host.isEmpty && !host.hasPrefix("-") && host.range(of: #"^[a-zA-Z0-9_.:\-]+$"#, options: .regularExpression) != nil
        guard validHost else { return "请输入有效的 SSH 别名、IP 或主机名（不要包含 user@）。" }
        if !user.isEmpty && user.range(of: #"^[a-zA-Z0-9_.\-]+$"#, options: .regularExpression) == nil { return "登录用户不能包含空格或特殊字符。" }
        if !port.isEmpty && !(Int(port).map { (1...65535).contains($0) } ?? false) { return "端口应为 1–65535，留空则沿用 SSH 配置。" }
        if !identityFile.isEmpty && !FileManager.default.fileExists(atPath: NSString(string: identityFile).expandingTildeInPath) { return "密钥文件不存在。" }
        return nil
    }

    var sshArguments: [String] {
        var args = ["-T", "-o", "BatchMode=\(authentication == "password" ? "no" : "yes")", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8", "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "-o", "ControlMaster=no", "-o", "ControlPath=none"]
        if authentication == "password" { args += ["-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "NumberOfPasswordPrompts=1"] }
        if !port.isEmpty { args += ["-p", port] }
        if !identityFile.isEmpty { args += ["-i", NSString(string: identityFile).expandingTildeInPath] }
        return args + ["--", target]
    }

    var verificationCommand: String {
        var args = ["ssh"]
        if !port.isEmpty { args += ["-p", port] }
        if !identityFile.isEmpty { args += ["-i", NSString(string: identityFile).expandingTildeInPath] }
        args += ["--", target]
        return args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }
}

struct GPUProcess: Codable, Identifiable {
    var gpuUUID: String
    var gpuIndex: Int
    var pid: Int
    var user: String
    var name: String
    var command: String
    var type: String
    var memoryUsed: Double?
    var cpuPercent: Double?
    var id: String { "\(gpuUUID)-\(pid)" }
}

struct GPUInfo: Codable, Identifiable {
    var index: Int
    var uuid: String
    var name: String
    var utilization: Double?
    var memoryUsed: Double?
    var memoryTotal: Double?
    var temperature: Double?
    var powerDraw: Double?
    var powerLimit: Double?
    var id: String { uuid }
    var memoryPercent: Double? {
        guard let used = memoryUsed, let total = memoryTotal, total > 0 else { return nil }
        return min(100, max(0, used / total * 100))
    }
}

struct Snapshot: Codable {
    var timestamp: Double
    var hostname: String
    var cpuPercent: Double?
    var cpuCores: Int
    var memoryUsed: Double
    var memoryTotal: Double
    var loadAverage: [Double]
    var gpus: [GPUInfo]
    var processes: [GPUProcess]
    var warnings: [String]
    var memoryPercent: Double { memoryTotal > 0 ? memoryUsed / memoryTotal * 100 : 0 }
}

struct HistoryPoint: Identifiable {
    let id = UUID()
    var date: Date
    var cpu: Double?
    var gpu: Double?
    var vram: Double?
}

enum ConnectionState: Equatable {
    case connecting, online, offline, paused, demo
    var label: String {
        switch self {
        case .connecting: return "连接中"
        case .online: return "在线"
        case .offline: return "离线"
        case .paused: return "已暂停"
        case .demo: return "演示"
        }
    }
}

struct ServerRuntime: Identifiable {
    var config: ServerConfig
    var state: ConnectionState = .connecting
    var snapshot: Snapshot?
    var receivedAt: Date?
    var error: String?
    var history: [HistoryPoint] = []
    var id: UUID { config.id }
    mutating func receive(_ value: Snapshot, demo: Bool = false) {
        snapshot = value
        receivedAt = Date()
        state = demo ? .demo : .online
        error = nil
        let utils = value.gpus.compactMap(\.utilization)
        let used = value.gpus.compactMap(\.memoryUsed).reduce(0, +)
        let total = value.gpus.compactMap(\.memoryTotal).reduce(0, +)
        history.append(HistoryPoint(date: Date(), cpu: value.cpuPercent, gpu: utils.isEmpty ? nil : utils.reduce(0, +) / Double(utils.count), vram: total > 0 ? used / total * 100 : nil))
        if history.count > 120 { history.removeFirst(history.count - 120) }
    }
}

func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
func gib(_ mib: Double?) -> String { mib.map { String(format: "%.1f", $0 / 1024) } ?? "—" }
