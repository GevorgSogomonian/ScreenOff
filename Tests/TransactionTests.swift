import Foundation
import Darwin

@main @MainActor enum TransactionTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }
    static func wait(_ worker: DisplayTransaction) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while worker.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        expect(!worker.isRunning, "worker must be reaped within a bounded time")
    }
    static func main() async throws {
        signal(SIGPIPE, SIG_IGN)
        let worker = DisplayTransaction(executable: URL(fileURLWithPath: CommandLine.arguments[1]), timeout: 0.5)
        var result: DisplayTransactionResult?
        let before = ProcessInfo.processInfo.systemUptime
        try worker.start(DisplayTransactionRequest(on: false, lastKnownBuiltIn: nil)) { result = $0 }
        do {
            try worker.start(DisplayTransactionRequest(on: true, lastKnownBuiltIn: nil)) { _ in }
            fatalError("overlapping transaction accepted")
        } catch { checks += 1 }
        await wait(worker)
        expect(result == .timedOut, "hung native subprocess reports timeout")
        expect(ProcessInfo.processInfo.systemUptime - before < 3, "timeout does not wait for blocked call")
        result = nil
        try worker.start(DisplayTransactionRequest(on: true, lastKnownBuiltIn: nil)) { result = $0 }
        await wait(worker)
        expect(result == .completed, "recovery can run after a stuck predecessor is killed and reaped")
        result = nil
        try worker.start(DisplayTransactionRequest(on: false, lastKnownBuiltIn: nil)) { result = $0 }
        worker.cancel()
        expect(worker.isRunning, "cancellation retains ownership until reaping")
        await wait(worker)
        expect(result == .cancelled, "sleep cancellation is distinct from API success")
        let seed = DisplayInfo(id: 1, identity: "fixture", builtIn: true, online: false, active: false, mirrored: false)
        try worker.start(DisplayTransactionRequest(on: true, lastKnownBuiltIn: seed)) { result = $0 }
        await wait(worker)
        expect(result == .deferred, "worker preflight sleep response survives the process boundary")
        print("PASS: \(checks) real subprocess timeout, cancellation, serialization and restart checks (no display changes)")
    }
}
