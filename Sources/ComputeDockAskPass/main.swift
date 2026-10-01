import Foundation
import Darwin

func answerPassword() -> Bool {
    let prompt = CommandLine.arguments.dropFirst().joined(separator: " ").lowercased()
    guard prompt.contains("password") || prompt.contains("passphrase"),
          let path = ProcessInfo.processInfo.environment["COMPUTEDOCK_AUTH_SOCKET"],
          path.hasPrefix("/tmp/cdock-"), path.utf8.count < 104 else { return false }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for (index, byte) in path.utf8.enumerated() { buffer[index] = byte }
    }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0 else { return false }
    var user: uid_t = 0
    var group: gid_t = 0
    guard getpeereid(descriptor, &user, &group) == 0, user == getuid() else { return false }
    let request = Array("password:\(getppid())".utf8)
    guard request.withUnsafeBytes({ write(descriptor, $0.baseAddress, $0.count) }) == request.count else { return false }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while true {
        let count = read(descriptor, &buffer, buffer.count)
        if count < 0 { return false }
        if count == 0 { break }
        response.append(contentsOf: buffer.prefix(count))
        if response.count > 4096 { return false }
    }
    guard !response.isEmpty else { return false }
    response.append(10)
    FileHandle.standardOutput.write(response)
    return true
}

exit(answerPassword() ? 0 : 1)
