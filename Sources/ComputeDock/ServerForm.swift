import SwiftUI
import AppKit

struct ServerForm: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState var config: ServerConfig
    @ViewState private var password = ""
    var onSave: (ServerConfig, String) -> Void

    private var error: String? {
        if config.name.trimmingCharacters(in: .whitespaces).isEmpty { return "请输入一个便于识别的服务器名称。" }
        if let error = config.validationError { return error }
        if config.authentication == "password" && password.isEmpty { return "请输入登录密码（只保存在本次会话）。" }
        if password.utf8.count > 4096 || password.contains("\n") { return "密码长度超出限制或含有换行。" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "server.rack").font(.title2).foregroundStyle(.teal); Text("服务器连接").font(.title2.bold()); Spacer() }
            Text("通过 SSH 读取资源；兼容 ~/.ssh/config 和 ProxyJump。") .font(.system(size: 12)).foregroundStyle(.secondary)
            Form {
                TextField("显示名称", text: $config.name, prompt: Text("例如：实验室 A100"))
                HStack {
                    TextField("主机 / SSH 别名", text: $config.host, prompt: Text("gpu-server 或 192.168.1.100"))
                    if !sshAliases.isEmpty {
                        Menu("SSH 别名") { ForEach(sshAliases, id: \.self) { alias in Button(alias) { config.host = alias; if config.name.isEmpty { config.name = alias } } } }.fixedSize()
                    }
                }
                TextField("登录用户", text: $config.user, prompt: Text("留空沿用 SSH 配置"))
                TextField("端口", text: $config.port, prompt: Text("留空沿用 SSH 配置，通常为 22"))
                Picker("认证方式", selection: $config.authentication) {
                    Text("SSH 密钥 / Agent").tag("key")
                    Text("密码登录").tag("password")
                }.pickerStyle(.segmented)
                if config.authentication == "password" {
                    SecureField("登录密码", text: $password)
                    Text("密码仅保存在内存中，退出 App 后需要重新输入。暂不支持需要验证码的多步认证。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    HStack {
                        TextField("私钥文件", text: $config.identityFile, prompt: Text("可选；默认使用 SSH Config / Agent"))
                        Button("选择…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
                            if panel.runModal() == .OK, let url = panel.url { config.identityFile = url.path }
                        }
                    }
                    Text("加密私钥请先在终端通过 ssh-add 加入 Agent。") .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            VStack(alignment: .leading, spacing: 8) {
                Label("首次连接", systemImage: "key.horizontal").font(.system(size: 12, weight: .semibold))
                Text("请先在终端登录并核验服务器指纹，再回到 App 连接。远端需要 Linux + Python 3；NVIDIA GPU 需要可运行的 nvidia-smi。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("复制终端登录命令") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(config.verificationCommand, forType: .string)
                }.disabled(config.validationError != nil)
            }.padding(14).background(Color.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存并连接") {
                    config.name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(config, password); dismiss()
                }.buttonStyle(.borderedProminent).tint(.teal).disabled(error != nil).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 580)
    }

    private var sshAliases: [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var aliases: Set<String> = []
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].split(whereSeparator: { $0.isWhitespace || $0 == "=" })
            if fields.first?.lowercased() == "host" {
                for field in fields.dropFirst() where !field.contains("*") && !field.contains("?") && !field.hasPrefix("!") { aliases.insert(String(field)) }
            }
        }
        return aliases.sorted()
    }
}

struct PasswordForm: View {
    @Environment(\.dismiss) private var dismiss
    var config: ServerConfig
    var onConnect: (String) -> Void
    @ViewState private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("输入密码连接").font(.title2.bold())
            Text(config.target).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            SecureField("登录密码", text: $password).textFieldStyle(.roundedBorder)
            Text("密码仅保存在本次 App 会话内。") .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("连接") { onConnect(password); dismiss() }.buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || password.utf8.count > 4096 || password.contains("\n"))
            }
        }.padding(28).frame(width: 420)
    }
}
