import Foundation
import Darwin

@MainActor
protocol RecoveryGuarding: AnyObject {
    var isRunning: Bool { get }
    func start(restoring: Bool) throws
    func requestRestore()
    func stop()
}

@MainActor
final class RecoveryGuard: RecoveryGuarding {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var heartbeat: Timer?
    private var retiring: [Process] = []

    var isRunning: Bool { process?.isRunning == true }

    func start(restoring: Bool = false) throws {
        if isRunning {
            if restoring { requestRestore() }
            return
        }
        stop()
        retiring.removeAll { !$0.isRunning }
        // Do not race a still-restoring predecessor with a new disable.
        guard retiring.isEmpty else { throw DisplayFailure.watchdog }
        guard let executable = Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent("ScreenOffWatchdog"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DisplayFailure.watchdog
        }
        let child = Process()
        let commands = Pipe()
        let replies = Pipe()
        // A child must not inherit its own heartbeat writer: that would keep
        // stdin open forever after the parent closes it.
        for fd in [commands.fileHandleForWriting.fileDescriptor, replies.fileHandleForReading.fileDescriptor] {
            _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
        }
        child.executableURL = executable
        child.arguments = ["--watch", String(getpid())] + (restoring ? ["--restore"] : [])
        child.standardInput = commands
        child.standardOutput = replies
        child.standardError = FileHandle.nullDevice
        try child.run()
        commands.fileHandleForReading.closeFile()
        replies.fileHandleForWriting.closeFile()
        process = child
        input = commands.fileHandleForWriting
        output = replies.fileHandleForReading
        var fd = pollfd(fd: replies.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        // Do not disconnect unless the independent rescue process is ready.
        guard poll(&fd, 1, 2000) > 0,
              String(data: replies.fileHandleForReading.availableData, encoding: .utf8) == "READY\n",
              child.isRunning else {
            stop()
            throw DisplayFailure.watchdog
        }
        beat()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        timer.tolerance = 0.2
        heartbeat = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func beat() {
        guard isRunning, let input else { return }
        // A dead child must not deliver SIGPIPE to the menu bar application.
        var byte: UInt8 = 1
        _ = Darwin.write(input.fileDescriptor, &byte, 1)
    }

    func requestRestore() {
        guard isRunning, let input else { return }
        var command: UInt8 = 2
        _ = Darwin.write(input.fileDescriptor, &command, 1)
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        // EOF instructs the helper to restore before it exits. Never terminate
        // it forcibly: it may still be rescuing the panel after an app failure.
        if let process, process.isRunning { retiring.append(process) }
        process = nil
    }
}
