import SwiftUI
import Charts
import AppKit

private let ink = Color(red: 0.10, green: 0.16, blue: 0.23)
private let accent = Color(red: 0.02, green: 0.49, blue: 0.43)
private let canvas = Color(red: 0.96, green: 0.97, blue: 0.985)
private let stroke = Color(red: 0.88, green: 0.91, blue: 0.94)

struct ContentView: View {
    @EnvironmentObject var store: MonitorStore
    @ViewState private var configSheet: ServerConfig?
    @ViewState private var passwordSheet: ServerConfig?
    @ViewState private var deleteConfig: ServerConfig?

    private var selected: ServerRuntime? { store.servers.first { $0.id.uuidString == store.selection } }
    private var title: String {
        if let selected { return selected.config.name }
        return store.selection == "idle" ? "空闲算力" : store.selection == "processes" ? "GPU 进程" : "算力总览"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Rectangle().fill(stroke).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if store.demoMode {
                            Banner(icon: "sparkles", text: "演示模式 · 所有数据均为模拟，未连接任何服务器", color: accent) {
                                Button("连接我的服务器") { store.setDemo(false); configSheet = ServerConfig(name: "", host: "") }.buttonStyle(.borderless)
                            }
                        }
                        if store.paused { Banner(icon: "pause.circle", text: "监控已暂停 · 下方保留最后一次采样", color: .orange) { EmptyView() } }
                        if let notice = store.notice {
                            Banner(icon: "exclamationmark.triangle", text: notice, color: .orange) { Button("关闭") { store.notice = nil } }
                        }
                        if let server = selected { detail(server) }
                        else if store.selection == "processes" { processesPage }
                        else if store.selection == "idle" { idlePage }
                        else { overview }
                    }
                    .padding(28)
                }
                .background(canvas)
                footer
            }
        }
        .foregroundStyle(ink)
        .tint(accent)
        .onChange(of: store.selection) { _, _ in store.search = "" }
        .sheet(item: $configSheet) { config in
            ServerForm(config: config) { config, password in store.add(config, password: password) }
        }
        .sheet(item: $passwordSheet) { config in
            PasswordForm(config: config) { password in store.connect(config.id, password: password) }
        }
        .alert("移除 \(deleteConfig?.name ?? "服务器")？", isPresented: Binding(get: { deleteConfig != nil }, set: { if !$0 { deleteConfig = nil } })) {
            Button("取消", role: .cancel) { deleteConfig = nil }
            Button("移除", role: .destructive) { if let config = deleteConfig { store.delete(config.id) }; deleteConfig = nil }
        } message: { Text("这会删除本机连接配置，并停止监控。") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(accent.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ComputeDock").font(.system(size: 16, weight: .bold))
                    Text("你的算力，尽在掌握").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.top, 42).padding(.horizontal, 18).padding(.bottom, 32)
            VStack(spacing: 5) {
                nav("overview", "算力总览", "square.grid.2x2", count: store.servers.count)
                nav("idle", "空闲算力", "bolt", count: idleGPUs.count)
                nav("processes", "GPU 进程", "list.bullet.rectangle", count: store.processCount)
            }.padding(.horizontal, 12)
            HStack {
                Text("服务器").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.activeServers.count)/\(store.servers.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.servers) { server in
                        Button { store.selection = server.id.uuidString } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Circle().fill(stateColor(server.state)).frame(width: 6, height: 6).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(server.config.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(server.state == .online || server.state == .demo ? "\(server.snapshot?.gpus.count ?? 0) GPU · CPU \(percent(server.snapshot?.cpuPercent))" : server.state.label)
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(store.selection == server.id.uuidString ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .contextMenu {
                                if !store.demoMode {
                                    Button("编辑连接") { configSheet = server.config }
                                    Button("重新连接") { reconnect(server.config) }
                                    Divider()
                                    Button("移除服务器", role: .destructive) { deleteConfig = server.config }
                                }
                            }
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 10)
            Divider().padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 14) {
                Button { configSheet = ServerConfig(name: "", host: "") } label: { Label("添加服务器", systemImage: "plus.circle") }.buttonStyle(.plain)
                Button { store.setDemo(!store.demoMode) } label: { Label(store.demoMode ? "使用真实服务器" : "试用演示模式", systemImage: store.demoMode ? "network" : "play.rectangle") }.buttonStyle(.plain)
                Text("MAC NATIVE / v0.1").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
            }.font(.system(size: 12)).padding(20)
        }.background(Color(red: 0.945, green: 0.956, blue: 0.966))
    }

    private func nav(_ key: String, _ label: String, _ icon: String, count: Int) -> some View {
        Button { store.selection = key } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(count)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(store.selection == key ? accent : .secondary)
            }.padding(.horizontal, 12).padding(.vertical, 11)
                .foregroundStyle(store.selection == key ? accent : ink)
                .background(store.selection == key ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("INFRASTRUCTURE / \(selected == nil ? "OVERVIEW" : "SERVER")").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                Text(title).font(.system(size: 25, weight: .bold))
            }
            Spacer()
            if selected == nil {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(store.selection == "processes" ? "搜索进程、用户、服务器" : "搜索服务器", text: $store.search).textFieldStyle(.plain)
                }.font(.system(size: 12)).padding(9).frame(width: 205).background(canvas, in: RoundedRectangle(cornerRadius: 8))
            }
            Menu {
                ForEach([1, 3, 5, 10], id: \.self) { value in Button("每 \(value) 秒") { store.setInterval(value) } }
            } label: { Label("\(store.interval) 秒刷新", systemImage: "clock") }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10)
            Button { store.togglePause() } label: { Image(systemName: store.paused ? "play.fill" : "pause.fill").frame(width: 25, height: 25) }.help(store.paused ? "继续监控" : "暂停监控")
            if let selected, !store.demoMode {
                Button { reconnect(selected.config) } label: { Image(systemName: "arrow.clockwise").frame(width: 25, height: 25) }.help("重新连接")
                Button { configSheet = selected.config } label: { Image(systemName: "slider.horizontal.3").frame(width: 25, height: 25) }.help("编辑连接")
            }
        }.padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 23).background(.white)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(store.paused ? .orange : store.demoMode ? .orange : accent).frame(width: 5, height: 5)
            Text(store.paused ? "采样已暂停" : store.demoMode ? "模拟数据" : "通过 SSH 采集 · 只读监控").font(.system(size: 10))
            Spacer()
            Text("CPU / VRAM / GPU PROCESSES").font(.system(size: 9, design: .monospaced)).tracking(0.8)
        }.foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 11).background(.white)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                MetricCard(label: store.paused ? "保留采样服务器" : "\(store.demoMode ? "演示" : "在线")服务器", value: "\(store.summaryServers.count)", unit: "/ \(store.servers.count)", icon: "server.rack", color: accent)
                MetricCard(label: "GPU 总数", value: "\(store.gpuCount)", unit: "张", icon: "cpu", color: .blue)
                MetricCard(label: "可用显存", value: gib(store.freeMemory), unit: "GiB", icon: "memorychip", color: accent)
                MetricCard(label: "平均 CPU", value: percent(store.averageCPU), unit: "", icon: "waveform.path", color: .indigo)
            }
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("服务器概览").font(.system(size: 16, weight: .semibold))
                    Text("查看每张卡的负载，找到下一份任务的落点。") .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Label(store.paused ? "PAUSED" : store.demoMode ? "DEMO" : "LIVE", systemImage: "dot.radiowaves.left.and.right").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(accent)
            }
            if store.servers.isEmpty { emptyState }
            else if store.visibleServers.isEmpty { Text("没有匹配的服务器").foregroundStyle(.secondary).padding(30) }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 370), spacing: 18, alignment: .top)], spacing: 18) {
                    ForEach(store.visibleServers) { server in
                        ServerCard(server: server) { store.selection = server.id.uuidString }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "server.rack").font(.system(size: 44, weight: .light)).foregroundStyle(accent)
            Text("连接第一台服务器").font(.system(size: 21, weight: .semibold))
            Text("使用 SSH 别名或主机地址，开始查看 CPU、显存与 GPU 进程。\n远端需要 Linux、Python 3；GPU 指标需要 nvidia-smi。")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button("添加服务器") { configSheet = ServerConfig(name: "", host: "") }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(.vertical, 85).card()
    }

    private func detail(_ server: ServerRuntime) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                StatusPill(state: server.state)
                Text(server.config.target).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                SampleTime(date: server.receivedAt)
            }
            if let error = server.error {
                VStack(alignment: .leading, spacing: 12) {
                    Label("连接需要处理", systemImage: "exclamationmark.triangle").font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
                    Text(error).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Text("首次连接请先在终端登录并核验服务器指纹。密码错误时可重新输入；App 不会自动接受未知或已变化的指纹。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("复制终端登录命令") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(server.config.verificationCommand, forType: .string) }
                        Button(server.config.authentication == "password" ? "输入密码连接" : "重新连接") { reconnect(server.config) }.buttonStyle(.borderedProminent)
                    }
                }.padding(20).card()
            }
            if let snapshot = server.snapshot {
                if server.state == .offline || server.state == .connecting {
                    Banner(icon: "clock.arrow.circlepath", text: "下方为上次成功采样，当前数据未更新", color: .orange) { EmptyView() }
                }
                HStack(spacing: 14) {
                    MetricCard(label: "CPU 利用率", value: percent(snapshot.cpuPercent), unit: "\(snapshot.cpuCores) 核", icon: "waveform.path", color: .blue)
                    MetricCard(label: "系统内存", value: gib(snapshot.memoryUsed), unit: "/ \(gib(snapshot.memoryTotal)) GiB", icon: "memorychip", color: accent)
                    MetricCard(label: "GPU 数量", value: "\(snapshot.gpus.count)", unit: "张", icon: "cpu", color: .indigo)
                    MetricCard(label: "GPU 进程", value: "\(snapshot.processes.count)", unit: "条", icon: "terminal", color: accent)
                }
                ForEach(snapshot.warnings, id: \.self) { warning in Banner(icon: "exclamationmark.triangle", text: warning, color: .orange) { EmptyView() } }
                TrendCard(history: server.history)
                HStack { Text("GPU 详情").font(.system(size: 16, weight: .semibold)); Spacer(); Text("利用率与显存分别显示").font(.system(size: 11)).foregroundStyle(.secondary) }
                if snapshot.gpus.isEmpty { Text("本次采样未获得 GPU 数据。").foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity, alignment: .leading).card() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), spacing: 16)], spacing: 16) {
                    ForEach(snapshot.gpus) { gpu in GPUDetailCard(gpu: gpu, processCount: snapshot.processes.filter { $0.gpuUUID == gpu.uuid }.count) }
                }
                ProcessTable(rows: snapshot.processes.map { ProcessRow(process: $0, serverID: server.id, serverName: server.config.name) }, showServer: false)
            } else if server.state == .connecting {
                VStack(spacing: 16) { ProgressView(); Text("正在建立 SSH 连接并等待首次采样…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(80).card()
            }
        }
    }

    private var processesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("GPU 进程来自当前在线服务器，包含计算与图形进程。CPU 按单核 100% 计，多线程进程可以超过 100%。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if store.paused { Text("暂停期间显示保留数据。").font(.system(size: 12)).foregroundStyle(.orange) }
            ProcessTable(rows: processRows, showServer: true)
        }
    }

    private var processRows: [ProcessRow] {
        store.servers.filter { $0.state == .online || $0.state == .demo || $0.state == .paused }.flatMap { server in
            (server.snapshot?.processes ?? []).map { ProcessRow(process: $0, serverID: server.id, serverName: server.config.name) }
        }.filter { row in
            store.search.isEmpty || "\(row.serverName) \(row.process.command) \(row.process.name) \(row.process.user) \(row.process.pid)".localizedCaseInsensitiveContains(store.search)
        }
    }

    private var idleGPUs: [IdleGPU] {
        store.activeServers.flatMap { server in
            (server.snapshot?.gpus ?? []).filter { gpu in
                guard let util = gpu.utilization, let mem = gpu.memoryPercent else { return false }
                return util < 10 && mem < 10 && !(server.snapshot?.processes.contains { $0.gpuUUID == gpu.uuid } ?? true)
            }.map { IdleGPU(server: server, gpu: $0) }
        }.filter { store.selection != "idle" || store.search.isEmpty || $0.server.config.name.localizedCaseInsensitiveContains(store.search) || $0.server.config.host.localizedCaseInsensitiveContains(store.search) }
    }

    private var idlePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("筛选：GPU 利用率 < 10% · 显存占用 < 10% · 没有 GPU 进程。基于最近采样，分配任务前请再次确认。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if idleGPUs.isEmpty { Text("当前没有符合条件的 GPU。").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(65).card() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 350), spacing: 16)], spacing: 16) {
                ForEach(idleGPUs) { item in
                    VStack(alignment: .leading, spacing: 13) {
                        Button(item.server.config.name) { store.selection = item.server.id.uuidString }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 14, weight: .semibold))
                        GPUDetailCard(gpu: item.gpu, processCount: 0)
                    }
                }
            }
        }
    }

    private func reconnect(_ config: ServerConfig) {
        if config.authentication == "password" { passwordSheet = config }
        else { store.connect(config.id) }
    }
}

private struct IdleGPU: Identifiable {
    var server: ServerRuntime
    var gpu: GPUInfo
    var id: String { server.id.uuidString + gpu.uuid }
}

struct MetricCard: View {
    var label: String
    var value: String
    var unit: String
    var icon: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(label).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(color).font(.system(size: 14)) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct ServerCard: View {
    var server: ServerRuntime
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                HStack {
                    Image(systemName: "server.rack").font(.system(size: 17)).foregroundStyle(accent).frame(width: 34, height: 34).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.config.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                        Text(server.config.target).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    StatusPill(state: server.state)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(18)
            }.buttonStyle(.plain)
            Divider().overlay(stroke)
            if let snapshot = server.snapshot {
                HStack(spacing: 12) {
                    Text("CPU").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Text(percent(snapshot.cpuPercent)).font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 43, alignment: .leading)
                    Meter(value: snapshot.cpuPercent, color: .blue)
                    Text("\(snapshot.cpuCores) 核").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.vertical, 16)
                HStack {
                    Text("GPU / 显存"); Spacer(); Text("GPU 利用率")
                }.font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 8)
                VStack(spacing: 8) {
                    ForEach(snapshot.gpus) { gpu in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text("GPU \(gpu.index)").font(.system(size: 10, weight: .semibold, design: .monospaced)); Spacer(); Text("\(gib(gpu.memoryUsed)) / \(gib(gpu.memoryTotal)) GiB").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
                                Meter(value: gpu.memoryPercent, color: usageColor(gpu.memoryPercent))
                                Text(gpu.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(percent(gpu.utilization)).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(usageColor(gpu.utilization)).frame(width: 48, alignment: .trailing)
                        }.padding(11).background(canvas, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.horizontal, 18)
                if snapshot.gpus.isEmpty { Text(snapshot.warnings.first ?? "无 GPU 数据").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18) }
                HStack {
                    Label("\(snapshot.processes.count) 个 GPU 进程", systemImage: "terminal")
                    Spacer()
                    SampleTime(date: server.receivedAt)
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(18)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if server.state == .connecting { ProgressView().controlSize(.small) }
                    Text(server.error ?? "等待采样…").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                    Button("查看连接详情", action: action).buttonStyle(.borderless)
                }.padding(18).frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
            }
        }.card().opacity(server.state == .offline ? 0.7 : 1)
    }
}

struct GPUDetailCard: View {
    var gpu: GPUInfo
    var processCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GPU \(gpu.index)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(accent)
                    Text(gpu.name).font(.system(size: 16, weight: .semibold))
                }
                Spacer()
                Text("\(processCount) 进程").font(.system(size: 10)).foregroundStyle(.secondary).padding(6).background(canvas, in: Capsule())
            }
            VStack(spacing: 14) {
                meterRow("GPU 利用率", value: gpu.utilization, detail: percent(gpu.utilization), color: .blue)
                meterRow("显存占用", value: gpu.memoryPercent, detail: "\(gib(gpu.memoryUsed)) / \(gib(gpu.memoryTotal)) GiB", color: usageColor(gpu.memoryPercent))
            }
            Divider()
            HStack {
                Label(gpu.temperature.map { String(format: "%.0f°C", $0) } ?? "—", systemImage: "thermometer.medium")
                Spacer()
                Label(gpu.powerDraw.map { String(format: "%.0f W", $0) } ?? "—", systemImage: "bolt")
                if let limit = gpu.powerLimit { Text(String(format: "/ %.0f W", limit)).foregroundStyle(.tertiary) }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).card()
    }

    private func meterRow(_ label: String, value: Double?, detail: String, color: Color) -> some View {
        VStack(spacing: 7) {
            HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(detail).monospacedDigit().fontWeight(.medium) }.font(.system(size: 11))
            Meter(value: value, color: color)
        }
    }
}

struct TrendCard: View {
    var history: [HistoryPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("资源趋势").font(.system(size: 15, weight: .semibold))
                Text("最近 \(history.count) 次采样").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                legend("CPU", .blue); legend("GPU 均值", accent); legend("显存占用", .indigo)
            }
            if history.count < 2 { Text("等待第二次采样后显示趋势…").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 150) }
            else {
                Chart(history) { point in
                    if let value = point.cpu { LineMark(x: .value("时间", point.date), y: .value("利用率", value), series: .value("指标", "CPU")).foregroundStyle(.blue).interpolationMethod(.linear) }
                    if let value = point.gpu { LineMark(x: .value("时间", point.date), y: .value("利用率", value), series: .value("指标", "GPU")).foregroundStyle(accent).interpolationMethod(.linear) }
                    if let value = point.vram { LineMark(x: .value("时间", point.date), y: .value("利用率", value), series: .value("指标", "显存")).foregroundStyle(.indigo.opacity(0.65)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(stroke); AxisValueLabel { if let value = value.as(Int.self) { Text("\(value)%").font(.system(size: 9)) } } } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.hour().minute().second()).font(.system(size: 9)) } }
                .frame(height: 155)
            }
        }.padding(20).card()
    }
    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(label).font(.system(size: 10)).foregroundStyle(.secondary) }
    }
}

struct ProcessRow: Identifiable {
    var process: GPUProcess
    var serverID: UUID
    var serverName: String
    var id: String { serverID.uuidString + process.id }
}

struct ProcessTable: View {
    var rows: [ProcessRow]
    var showServer: Bool
    @ViewState private var selection: String?
    @ViewState private var ordering = 0
    private var sorted: [ProcessRow] {
        rows.sorted { ordering == 1 ? $0.process.pid < $1.process.pid : ($0.process.memoryUsed ?? -1) > ($1.process.memoryUsed ?? -1) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("GPU 进程").font(.system(size: 15, weight: .semibold))
                Text("\(rows.count) 条记录").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Picker("排序", selection: $ordering) { Text("按显存").tag(0); Text("按 PID").tag(1) }.labelsHidden().frame(width: 110).controlSize(.small)
            }
            if rows.isEmpty {
                Text("没有匹配的 GPU 进程").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Table(sorted, selection: $selection) {
                    TableColumn("PID") { row in Text(String(row.process.pid)).monospaced() }.width(min: 55, ideal: 65, max: 85)
                    TableColumn("GPU") { row in Text("\(row.process.gpuIndex) · \(row.process.type)").monospaced() }.width(min: 45, ideal: 55, max: 75)
                    TableColumn("用户") { row in Text(row.process.user) }.width(min: 65, ideal: 80, max: 100)
                    TableColumn("显存") { row in Text("\(gib(row.process.memoryUsed)) GiB").monospacedDigit() }.width(min: 70, ideal: 85, max: 100)
                    TableColumn("CPU") { row in Text(percent(row.process.cpuPercent)).monospacedDigit() }.width(min: 45, ideal: 55, max: 75)
                    TableColumn(showServer ? "服务器 / 命令" : "命令") { row in
                        VStack(alignment: .leading, spacing: 3) {
                            if showServer { Text(row.serverName).font(.system(size: 10)).foregroundStyle(accent) }
                            Text(row.process.command.isEmpty ? row.process.name : row.process.command).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        }.help(row.process.command.isEmpty ? row.process.name : row.process.command)
                    }.width(min: 150, ideal: 320)
                }.font(.system(size: 11)).frame(height: showServer ? 350 : 230)
                if let row = rows.first(where: { $0.id == selection }) {
                    HStack(alignment: .top) {
                        Text(row.process.command.isEmpty ? row.process.name : row.process.command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.process.command.isEmpty ? row.process.name : row.process.command, forType: .string) } label: { Image(systemName: "doc.on.doc") }.help("复制命令")
                    }.padding(10).background(canvas, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text("C = 计算 · G = 图形 · 一进程跨多张 GPU 时按卡分别显示。权限不足的字段显示 —。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20).card()
    }
}

struct Meter: View {
    var value: Double?
    var color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(stroke.opacity(0.65))
                Capsule().fill(color).frame(width: geometry.size.width * CGFloat(min(100, max(0, value ?? 0))) / 100)
            }
        }.frame(height: 5).accessibilityLabel(value.map { percent($0) } ?? "不可用")
    }
}

struct StatusPill: View {
    var state: ConnectionState
    var body: some View {
        HStack(spacing: 4) { Circle().fill(stateColor(state)).frame(width: 4, height: 4); Text(state.label) }
            .font(.system(size: 9, weight: .medium)).foregroundStyle(stateColor(state)).padding(.horizontal, 7).padding(.vertical, 5).background(stateColor(state).opacity(0.08), in: Capsule())
    }
}

struct SampleTime: View {
    var date: Date?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(date.map { "\(max(0, Int(context.date.timeIntervalSince($0)))) 秒前采样" } ?? "尚无采样").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct Banner<Trailing: View>: View {
    var icon: String
    var text: String
    var color: Color
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }.font(.system(size: 11)).foregroundStyle(color).padding(12).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private func stateColor(_ state: ConnectionState) -> Color {
    switch state { case .online: return accent; case .demo, .paused: return .orange; case .connecting: return .blue; case .offline: return .gray }
}
private func usageColor(_ value: Double?) -> Color {
    guard let value else { return .gray }
    return value >= 90 ? Color(red: 0.85, green: 0.30, blue: 0.25) : value >= 70 ? .orange : accent
}
private extension View {
    func card() -> some View {
        self.background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke.opacity(0.8), lineWidth: 1)).shadow(color: ink.opacity(0.025), radius: 6, y: 3)
    }
}
