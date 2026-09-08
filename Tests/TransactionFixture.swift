import Foundation
import Darwin

// No CoreGraphics or AppKit: fault injection never changes a physical display.
@main enum TransactionFixture {
    static func main() {
        guard let request = try? JSONDecoder().decode(DisplayTransactionRequest.self,
            from: FileHandle.standardInput.readDataToEndOfFile()) else { exit(64) }
        if request.on { exit(request.lastKnownBuiltIn == nil ? 0 : 75) }
        while true { pause() } // Simulate a system call that never returns.
    }
}
