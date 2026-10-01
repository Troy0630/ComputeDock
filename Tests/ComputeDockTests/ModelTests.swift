import XCTest
@testable import ComputeDock

final class ModelTests: XCTestCase {
    func testHostValidationRejectsShellAndSSHOptionInjection() {
        for host in ["-oProxyCommand=evil", "server;touch /tmp/test", "$(id)", "user@server", "host name", "host\nname", ""] {
            XCTAssertNotNil(ServerConfig(name: "Test", host: host).validationError, host)
        }
        for host in ["gpu-cluster", "10.0.0.5", "gpu.example.org", "2001:db8::1"] {
            XCTAssertNil(ServerConfig(name: "Test", host: host).validationError, host)
        }
    }

    func testSSHArgumentsPreserveAliasDefaultsAndVerifyHostKeys() {
        var config = ServerConfig(name: "Test", host: "gpu-cluster")
        XCTAssertFalse(config.sshArguments.contains("-p"))
        XCTAssertFalse(config.sshArguments.contains("-l"))
        XCTAssertTrue(config.sshArguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertEqual(config.sshArguments.suffix(2), ["--", "gpu-cluster"])
        config.port = "2200"; config.user = "troy"; config.authentication = "password"
        XCTAssertTrue(config.sshArguments.contains("BatchMode=no"))
        XCTAssertTrue(config.sshArguments.contains("PreferredAuthentications=password,keyboard-interactive"))
        XCTAssertEqual(config.sshArguments.suffix(2), ["--", "troy@gpu-cluster"])
    }

    func testPortValidation() {
        for port in ["0", "65536", "bad", "22 -o option"] { XCTAssertNotNil(ServerConfig(name: "Test", host: "gpu", port: port).validationError) }
        XCTAssertNil(ServerConfig(name: "Test", host: "gpu", port: "65535").validationError)
    }

    func testNullMetricsAreUnavailableRatherThanIdle() throws {
        let json = #"{"timestamp":1,"hostname":"gpu","cpuPercent":null,"cpuCores":32,"memoryUsed":1024,"memoryTotal":2048,"loadAverage":[1,2,3],"gpus":[{"index":0,"uuid":"GPU-1","name":"A100","utilization":null,"memoryUsed":null,"memoryTotal":81920,"temperature":null,"powerDraw":null,"powerLimit":null}],"processes":[],"warnings":["unavailable"]}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.gpus[0].memoryPercent)
        XCTAssertNil(snapshot.cpuPercent)
        XCTAssertEqual(percent(snapshot.gpus[0].utilization), "—")
        XCTAssertEqual(snapshot.memoryPercent, 50)
    }

    func testConfigNeverContainsSessionPassword() throws {
        let config = ServerConfig(name: "Test", host: "gpu", authentication: "password")
        let json = String(data: try JSONEncoder().encode(config), encoding: .utf8)!
        XCTAssertFalse(json.contains("loginPassword"))
        XCTAssertFalse(json.contains("secret"))
    }

    func testBrokerRoundTripWithAskPassExecutable() async throws {
        let broker = try PasswordBroker(password: "test-秘密-'$`-123")
        broker.authorize(processID: ProcessInfo.processInfo.processIdentifier)
        defer { broker.stop() }
        let runner = Process()
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ComputeDockAskPass")
        runner.executableURL = executable
        runner.arguments = ["troy@gpu's password: "]
        runner.environment = ["COMPUTEDOCK_AUTH_SOCKET": broker.path]
        let output = Pipe(); runner.standardOutput = output
        try runner.run()
        runner.waitUntilExit()
        XCTAssertEqual(runner.terminationStatus, 0)
        XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "test-秘密-'$`-123\n")
        let rejected = Process(); rejected.executableURL = executable; rejected.arguments = ["Are you sure you want to continue connecting?"]
        rejected.environment = ["COMPUTEDOCK_AUTH_SOCKET": broker.path]; rejected.standardOutput = FileHandle.nullDevice
        try rejected.run(); rejected.waitUntilExit()
        XCTAssertEqual(rejected.terminationStatus, 1)
        let wrongParent = try PasswordBroker(password: "must-not-leak")
        defer { wrongParent.stop() }
        wrongParent.authorize(processID: ProcessInfo.processInfo.processIdentifier + 9999)
        let blocked = Process(); blocked.executableURL = executable; blocked.arguments = ["jump@gateway's password:"]
        blocked.environment = ["COMPUTEDOCK_AUTH_SOCKET": wrongParent.path]
        let blockedOutput = Pipe(); blocked.standardOutput = blockedOutput
        try blocked.run(); blocked.waitUntilExit()
        XCTAssertEqual(blocked.terminationStatus, 1)
        XCTAssertTrue(blockedOutput.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }
}
