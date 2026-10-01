import Foundation
import Darwin

// SSH_ASKPASS gets the session password over a private, same-user Unix socket.
// The password never enters argv, environment variables, a file, or saved config.
final class PasswordBroker {
    let path: String
    private let source: DispatchSourceRead
    private let descriptor: Int32
    private let password: String
    private var started = false

    init(password: String) throws {
        self.password = password
        let directory = "/tmp/cdock-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        path = directory + "/auth.sock"
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        self.descriptor = descriptor
        guard descriptor >= 0 else { try? FileManager.default.removeItem(atPath: directory); throw CocoaError(.fileWriteUnknown) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let socketPath = path
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in socketPath.utf8.enumerated() { buffer[index] = byte }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, listen(descriptor, 4) == 0 else {
            close(descriptor); try? FileManager.default.removeItem(atPath: directory); throw CocoaError(.fileWriteUnknown)
        }
        chmod(path, 0o600)
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "ComputeDock.password"))
        source.setCancelHandler {
            close(descriptor)
            try? FileManager.default.removeItem(atPath: directory)
        }
    }

    func authorize(processID: pid_t) {
        guard !started else { return }
        started = true
        let descriptor = self.descriptor
        let password = self.password
        // ProxyJump runs another SSH process. Its AskPass child must not receive
        // the destination server's password; only this SSH session is authorized.
        source.setEventHandler {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            var user: uid_t = 0
            var group: gid_t = 0
            guard getpeereid(client, &user, &group) == 0, user == getuid() else { return }
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var request = [UInt8](repeating: 0, count: 64)
            let count = read(client, &request, request.count)
            guard count > 0, String(bytes: request.prefix(count), encoding: .utf8) == "password:\(processID)" else { return }
            let data = Data(password.utf8)
            data.withUnsafeBytes { buffer in
                var sent = 0
                while sent < buffer.count {
                    let count = write(client, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
                    if count <= 0 { break }
                    sent += count
                }
            }
        }
        source.resume()
    }

    func stop() {
        if !started { started = true; source.resume() }
        source.cancel()
    }
    deinit { stop() }
}
