import Foundation
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {
    @Published var servers: [ServerRuntime] = []
    @Published var selection = "overview"
    @Published var search = ""
    @Published var demoMode: Bool
    @Published var paused = false
    @Published var interval: Int
    @Published var notice: String?
    private var saved: [ServerConfig] = []
    private var sessions: [UUID: SSHMonitor] = [:]
    private var passwords: [UUID: String] = [:]
    private var demoTask: Task<Void, Never>?
    private var demoTick = 0.0
    private let configURL: URL

    init() {
        configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ComputeDock/servers.json")
        let persistedInterval = UserDefaults.standard.integer(forKey: "ComputeDock.interval")
        interval = [1, 3, 5, 10].contains(persistedInterval) ? persistedInterval : 3
        if FileManager.default.fileExists(atPath: configURL.path) {
            do { saved = try JSONDecoder().decode([ServerConfig].self, from: Data(contentsOf: configURL)) }
            catch { notice = "服务器配置读取失败；原文件保留在 \(configURL.path)。\(error.localizedDescription)" }
        }
        demoMode = saved.isEmpty
    }

    var visibleServers: [ServerRuntime] {
        servers.filter { search.isEmpty || $0.config.name.localizedCaseInsensitiveContains(search) || $0.config.target.localizedCaseInsensitiveContains(search) }
    }
    var activeServers: [ServerRuntime] { servers.filter { $0.state == .online || $0.state == .demo } }
    var summaryServers: [ServerRuntime] { paused ? servers.filter { $0.snapshot != nil } : activeServers }
    var gpuCount: Int { summaryServers.reduce(0) { $0 + ($1.snapshot?.gpus.count ?? 0) } }
    var freeMemory: Double { summaryServers.flatMap { $0.snapshot?.gpus ?? [] }.reduce(0) { $0 + max(0, ($1.memoryTotal ?? 0) - ($1.memoryUsed ?? $1.memoryTotal ?? 0)) } }
    var averageCPU: Double? {
        let values = summaryServers.compactMap { $0.snapshot?.cpuPercent }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    var processCount: Int { summaryServers.reduce(0) { $0 + ($1.snapshot?.processes.count ?? 0) } }

    func start() { rebuild() }
    func shutdown() {
        demoTask?.cancel(); demoTask = nil
        sessions.values.forEach { $0.stop() }; sessions.removeAll()
    }

    func setDemo(_ value: Bool) {
        demoMode = value; paused = false; selection = "overview"; rebuild()
    }

    private func rebuild() {
        shutdown()
        if demoMode {
            servers = Self.demoConfigs.map { ServerRuntime(config: $0, state: .demo) }
            for _ in 0..<30 { updateDemo() }
            // Give seeded history a real time axis; the synthetic past is demo only.
            for i in servers.indices {
                let count = servers[i].history.count
                for j in 0..<count { servers[i].history[j].date = Date().addingTimeInterval(Double(j - count + 1) * Double(interval)) }
            }
            runDemo()
        } else {
            servers = saved.map { ServerRuntime(config: $0) }
            for config in saved { connect(config.id) }
        }
    }

    func setInterval(_ value: Int) {
        interval = value; UserDefaults.standard.set(value, forKey: "ComputeDock.interval")
        if paused { return }
        if demoMode { demoTask?.cancel(); runDemo() }
        else { for config in saved { connect(config.id) } }
    }

    func togglePause() {
        paused.toggle()
        if paused {
            shutdown()
            for i in servers.indices { servers[i].state = .paused }
        } else if demoMode { updateDemo(); runDemo() }
        else { for config in saved { connect(config.id) } }
    }

    func add(_ config: ServerConfig, password: String) {
        if let index = saved.firstIndex(where: { $0.id == config.id }) { saved[index] = config }
        else { saved.append(config) }
        if config.authentication == "password" { passwords[config.id] = password }
        else { passwords.removeValue(forKey: config.id) }
        persist()
        if demoMode { setDemo(false) }
        else {
            if let i = servers.firstIndex(where: { $0.id == config.id }) { servers[i].config = config }
            else { servers.append(ServerRuntime(config: config)) }
            if !paused { connect(config.id) }
        }
        selection = config.id.uuidString
    }

    func delete(_ id: UUID) {
        sessions.removeValue(forKey: id)?.stop()
        passwords.removeValue(forKey: id)
        saved.removeAll { $0.id == id }; servers.removeAll { $0.id == id }
        selection = "overview"; persist()
    }

    func connect(_ id: UUID, password: String? = nil) {
        guard !demoMode, !paused, let i = servers.firstIndex(where: { $0.id == id }) else { return }
        let config = servers[i].config
        if let password { passwords[id] = password }
        sessions.removeValue(forKey: id)?.stop()
        if config.authentication == "password", passwords[id]?.isEmpty != false {
            servers[i].state = .offline; servers[i].error = "密码只保存在当前会话中。点击“输入密码连接”开始监控。"; return
        }
        servers[i].state = .connecting; servers[i].error = nil
        let monitor = SSHMonitor(onSnapshot: { [weak self] snapshot in
            guard let self, let index = self.servers.firstIndex(where: { $0.id == id }) else { return }
            self.servers[index].receive(snapshot)
        }, onError: { [weak self] message in
            guard let self, let index = self.servers.firstIndex(where: { $0.id == id }) else { return }
            self.servers[index].state = .offline; self.servers[index].error = message
        })
        sessions[id] = monitor
        monitor.start(config: config, interval: interval, password: passwords[id])
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(saved).write(to: configURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        } catch { notice = "配置保存失败：\(error.localizedDescription)" }
    }

    private func runDemo() {
        demoTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.interval else { return }
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                self?.updateDemo()
            }
        }
    }

    private func updateDemo() {
        demoTick += 0.28
        for i in servers.indices {
            let cards = [4, 2, 1][i]
            let model = ["NVIDIA A100 80GB", "NVIDIA RTX 4090", "NVIDIA RTX 3090"][i]
            let capacity = [81920.0, 24576.0, 24576.0][i]
            var gpus: [GPUInfo] = []
            var processes: [GPUProcess] = []
            for j in 0..<cards {
                let free = (i == 0 && j == 3) || (i == 1 && j == 1)
                let wave = sin(demoTick + Double(j) + Double(i))
                let util = free ? 0 : max(0, min(100, 78 + wave * 19))
                let used = free ? 220.0 : capacity * (0.61 + Double(j) * 0.06 + wave * 0.04)
                let uuid = "demo-\(i)-\(j)"
                gpus.append(GPUInfo(index: j, uuid: uuid, name: model, utilization: util, memoryUsed: used, memoryTotal: capacity, temperature: free ? 34 : 60 + wave * 9, powerDraw: free ? 25 : 260 + wave * 35, powerLimit: i == 0 ? 400 : 450))
                if !free {
                    processes.append(GPUProcess(gpuUUID: uuid, gpuIndex: j, pid: 28410 + i * 3100 + j, user: i == 0 ? "troy" : "research", name: "python", command: i == 0 ? "python train.py --model llama --dataset medical --device \(j)" : "python -m torch.distributed.run finetune.py --epochs 100", type: "C", memoryUsed: used - 430, cpuPercent: 140 + wave * 70))
                }
            }
            let snapshot = Snapshot(timestamp: Date().timeIntervalSince1970, hostname: servers[i].config.host, cpuPercent: [42.0, 24.0, 67.0][i] + sin(demoTick + Double(i)) * 9, cpuCores: [64, 32, 24][i], memoryUsed: [112640.0, 45056.0, 77824.0][i], memoryTotal: [262144.0, 131072.0, 131072.0][i], loadAverage: [8.6, 7.9, 7.2], gpus: gpus, processes: processes, warnings: [])
            servers[i].receive(snapshot, demo: true)
        }
    }

    static let demoConfigs = [
        ServerConfig(name: "Atlas · 训练集群", host: "atlas-a100", user: "troy"),
        ServerConfig(name: "Nova · 实验节点", host: "nova-4090", user: "research"),
        ServerConfig(name: "Orbit · 推理服务", host: "orbit-3090", user: "research")
    ]
}
