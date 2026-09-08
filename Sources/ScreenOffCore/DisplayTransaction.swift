import Foundation
import Darwin

/// Only this short-lived child may call the private configuration API. The
/// supervisor's run loop must never enter a synchronous WindowServer change.
struct DisplayTransactionRequest: Codable {
    let on: Bool
    let lastKnownBuiltIn: DisplayInfo?
}

enum DisplayTransactionResult: Equatable {
    case completed, failed, deferred, timedOut, cancelled
}

@MainActor
protocol DisplayTransactionRunning: AnyObject {
    var isRunning: Bool { get }
    func start(_ request: DisplayTransactionRequest,
               completion: @escaping (DisplayTransactionResult) -> Void) throws
    func cancel()
}

@MainActor
final class DisplayTransaction: DisplayTransactionRunning {
    private var process: Process?
    private var outcome: DisplayTransactionResult?
    var isRunning: Bool { process != nil }
    private let executable: URL
    private let timeout: TimeInterval

    init(executable: URL, timeout: TimeInterval = 3) {
        self.executable = executable
        self.timeout = timeout
    }

    func start(_ request: DisplayTransactionRequest,
               completion: @escaping (DisplayTransactionResult) -> Void) throws {
        guard process == nil else { throw DisplayFailure.watchdog }
        let child = Process()
        let input = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
        child.executableURL = executable
        child.arguments = ["--transaction", String(getpid())]
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                let result = self.outcome ?? (finished.terminationReason == .exit && finished.terminationStatus == 0
                    ? .completed : (finished.terminationStatus == 75 ? .deferred : .failed))
                self.process = nil
                self.outcome = nil
                completion(result)
            }
        }
        let data = try JSONEncoder().encode(request)
        try child.run()
        process = child
        outcome = nil
        input.fileHandleForReading.closeFile()
        try? input.fileHandleForWriting.write(contentsOf: data)
        try? input.fileHandleForWriting.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self, weak child] in
            guard let self, let child, self.process === child else { return }
            self.endWorker(as: .timedOut)
        }
    }

    func cancel() { endWorker(as: .cancelled) }

    private func endWorker(as result: DisplayTransactionResult) {
        guard let process, process.isRunning, outcome == nil else { return }
        outcome = result
        // Kill only our disposable transaction child, never the durable rescue
        // supervisor. Keep ownership until Process reaps the child; no overlap.
        _ = kill(process.processIdentifier, SIGKILL)
    }
}
