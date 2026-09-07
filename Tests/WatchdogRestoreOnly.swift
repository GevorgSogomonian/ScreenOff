import AppKit
import Darwin

/// Opt-in IPC integration against the actual helper. The built-in must already
/// be active; this executable has no disable transaction anywhere in its path.
@main
enum WatchdogRestoreOnly {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                let hardware = DisplayHardware()
                guard try hardware.snapshot().builtInIsRestored else { throw DisplayFailure.verification }
                for trigger in ["command", "EOF", "restore-argument"] {
                    try await run(trigger: trigger, hardware: hardware)
                }
                exit(0)
            } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        app.run()
    }

    @MainActor static func run(trigger: String, hardware: DisplayHardware) async throws {
        let child = Process()
        let commands = Pipe(), replies = Pipe()
        for fd in [commands.fileHandleForWriting.fileDescriptor, replies.fileHandleForReading.fileDescriptor] {
            _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
        }
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        child.arguments = ["--watch", String(getpid())] + (trigger == "restore-argument" ? ["--restore"] : [])
        child.standardInput = commands
        child.standardOutput = replies
        try child.run()
        commands.fileHandleForReading.closeFile()
        replies.fileHandleForWriting.closeFile()
        defer {
            try? commands.fileHandleForWriting.close()
            try? replies.fileHandleForReading.close()
        }
        var fd = pollfd(fd: replies.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&fd, 1, 3000) > 0,
              String(data: replies.fileHandleForReading.availableData, encoding: .utf8) == "READY\n"
        else { throw DisplayFailure.watchdog }
        if trigger == "EOF" { try commands.fileHandleForWriting.close() }
        if trigger == "command" {
            var command: UInt8 = 2
            guard Darwin.write(commands.fileHandleForWriting.fileDescriptor, &command, 1) == 1
            else { throw DisplayFailure.watchdog }
        }
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 200_000_000)
            if !child.isRunning {
                guard child.terminationStatus == 0 else { throw DisplayFailure.watchdog }
                guard try hardware.snapshot().builtInIsRestored else { throw DisplayFailure.verification }
                print("PASS: helper \(trigger) recovery verified; built-in active, no disable requested")
                return
            }
            if trigger != "EOF" {
                var heartbeat: UInt8 = 1
                _ = Darwin.write(commands.fileHandleForWriting.fileDescriptor, &heartbeat, 1)
            }
        }
        throw DisplayFailure.verification
    }
}
