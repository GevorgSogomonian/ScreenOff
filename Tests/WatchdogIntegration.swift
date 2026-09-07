import Foundation
import AppKit
import Darwin

/// Opt-in hardware test. Closing the heartbeat pipe simulates lost contact
/// while this parent remains alive, proving restoration comes from the helper
/// rather than relying solely on WindowServer's application-exit rollback.
@main
enum WatchdogIntegration {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        signal(SIGPIPE, SIG_IGN)
        setbuf(stdout, nil)
        let hardware = DisplayHardware()
        let before = try hardware.snapshot()
        guard before.builtInIsOn && before.canDisable else { throw DisplayFailure.noExternal }
        let child = Process()
        let input = Pipe(), output = Pipe()
        for fd in [input.fileHandleForWriting.fileDescriptor, output.fileHandleForReading.fileDescriptor] {
            _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
        }
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        child.arguments = ["--watch", String(getpid())]
        child.standardInput = input
        child.standardOutput = output
        try child.run()
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        defer {
            _ = hardware.recover()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 3000) > 0,
              String(data: output.fileHandleForReading.availableData, encoding: .utf8) == "READY\n"
        else { throw DisplayFailure.watchdog }
        try hardware.setBuiltIn(on: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        guard try !hardware.snapshot().builtInIsOn else { throw DisplayFailure.verification }
        print("PASS: panel disabled with independent helper ready")
        try input.fileHandleForWriting.close()
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 200_000_000)
            if try hardware.snapshot().builtInIsOn {
                print("PASS: helper independently restored panel after pipe EOF while parent stayed alive")
                return
            }
        }
        throw DisplayFailure.verification
    }
}
