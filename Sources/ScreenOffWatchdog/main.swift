import Foundation
import AppKit
import CoreGraphics
import Darwin

// Private pipe handles are inherited only by this child. No sockets, files,
// elevated helper, launch daemon or persistent background registration.
let arguments = CommandLine.arguments
guard (arguments.count == 3 || (arguments.count == 4 && arguments[3] == "--restore")),
      arguments[1] == "--watch",
      let parent = Int32(arguments[2]), parent > 1,
      getppid() == parent else { exit(64) }

signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let hardware = DisplayHardware()
guard hardware.supported else { exit(69) }
// Capture the actual safety displays BEFORE replying READY and allowing off.
// A placeholder created later for a headless session cannot renew this lease.
let initial = try? hardware.snapshot()
let protectedIdentities = initial?.externalIdentities ?? []
let protectedIDs = Set(initial?.externalDisplays.map(\.id) ?? [])
var lastHeartbeat = ProcessInfo.processInfo.systemUptime
var pipeOpen = true
var recovery = WatchdogRecovery()
var lastRecoveryState: String?
if arguments.count == 4 { recovery.request() }
let reader = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)

func checkLease() {
    let state = try? hardware.snapshot()
    let remaining = protectedIdentities.intersection(state?.externalIdentities ?? [])
    if WatchdogRules.shouldRecover(parentAlive: getppid() == parent && kill(parent, 0) == 0,
                                   pipeOpen: pipeOpen,
                                   heartbeatAge: ProcessInfo.processInfo.systemUptime - lastHeartbeat,
                                   externalCount: remaining.count,
                                   lidClosed: state?.lidClosed ?? false) {
        recovery.request()
    }
    // No recovery timeout: the panel may reappear only after waking or opening
    // the lid. Keep this independent process alive until it is active again.
    if recovery.requested {
        let description = "panel=\(state?.builtIn?.id.description ?? "missing") online=\(state?.builtInIsOn == true) active=\(state?.builtIn?.active == true) lidClosed=\(state?.lidClosed == true)"
        if lastRecoveryState != description {
            fputs("ScreenOffWatchdog: recovering; \(description)\n", stderr)
            lastRecoveryState = description
        }
    }
    if recovery.step(using: hardware) {
        fputs("ScreenOffWatchdog: recovery confirmed.\n", stderr)
        exit(0)
    }
}

let displayChanged: CGDisplayReconfigurationCallBack = { displayID, flags, _ in
    guard !flags.contains(.beginConfigurationFlag),
          !flags.intersection([.removeFlag, .disabledFlag]).isEmpty else { return }
    DispatchQueue.main.async {
        if protectedIDs.contains(displayID) { recovery.request() }
    }
}
_ = CGDisplayRegisterReconfigurationCallback(displayChanged, nil)

reader.setEventHandler {
    var bytes = [UInt8](repeating: 0, count: 128)
    let count = read(STDIN_FILENO, &bytes, bytes.count)
    if count > 0 {
        lastHeartbeat = ProcessInfo.processInfo.systemUptime
        if bytes.prefix(count).contains(2) { recovery.request() }
    } else if count == 0 || errno != EINTR {
        pipeOpen = false
        reader.cancel() // EOF must not spin the main queue; the timer retries.
    }
    // Timer-only attempts separate confirmation observations by a real
    // run-loop interval, even with frequent heartbeats.
    if !pipeOpen { recovery.request() }
}
reader.resume()
let timer = Timer(timeInterval: 0.75, repeats: true) { _ in checkLease() }
timer.tolerance = 0.1
RunLoop.main.add(timer, forMode: .common)
FileHandle.standardOutput.write(Data("READY\n".utf8))
app.run()
