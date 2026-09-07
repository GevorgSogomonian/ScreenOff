import Foundation
import AppKit
import Darwin

// Private pipe handles are inherited only by this child. No sockets, files,
// elevated helper, launch daemon or persistent background registration.
guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--watch",
      let parent = Int32(CommandLine.arguments[2]), parent > 1,
      getppid() == parent else { exit(64) }

signal(SIGPIPE, SIG_IGN)
// AppKit establishes a live WindowServer client. The run loop in recover()
// lets configuration changes settle before the helper checks their result.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let hardware = DisplayHardware()
guard hardware.supported else { exit(69) }
var lastHeartbeat = ProcessInfo.processInfo.systemUptime
var pipeOpen = true
var recovering = false
let reader = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
func checkLease() {
    guard !recovering else { return }
    let state = try? hardware.snapshot()
    // An unreadable topology is not evidence of a usable external display.
    if WatchdogRules.shouldRecover(parentAlive: getppid() == parent && kill(parent, 0) == 0,
                                   pipeOpen: pipeOpen,
                                   heartbeatAge: ProcessInfo.processInfo.systemUptime - lastHeartbeat,
                                   externalCount: state?.externalDisplays.count ?? 0) {
        recovering = true
        reader.cancel()
        fputs("ScreenOffWatchdog: restoring (built-in online: \(state?.builtInIsOn == true)).\n", stderr)
        let restored = hardware.recover()
        if !restored { fputs("ScreenOffWatchdog: display recovery was not confirmed.\n", stderr) }
        exit(restored ? 0 : 1)
    }
}
reader.setEventHandler {
    var bytes = [UInt8](repeating: 0, count: 128)
    let count = read(STDIN_FILENO, &bytes, bytes.count)
    if count > 0 { lastHeartbeat = ProcessInfo.processInfo.systemUptime }
    else if count == 0 || errno != EINTR { pipeOpen = false }
    checkLease()
}
reader.resume()
let timer = Timer(timeInterval: 0.75, repeats: true) { _ in checkLease() }
RunLoop.main.add(timer, forMode: .common)
FileHandle.standardOutput.write(Data("READY\n".utf8))
app.run()
