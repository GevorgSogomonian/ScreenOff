import Foundation

@main
enum PolicyTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String,
                       file: StaticString = #file, line: UInt = #line) {
        checks += 1
        guard value() else { fatalError("FAIL: \(message)", file: file, line: line) }
    }

    static func topology(on: Bool = true, externals: [String] = ["desk"],
                         lid: Bool = false, mirrored: Bool = false,
                         builtInPresent: Bool = true, externalActive: Bool = true) -> DisplaySnapshot {
        var displays = builtInPresent ? [DisplayInfo(id: 1, identity: "builtin", builtIn: true,
                                                     online: on, active: on, mirrored: mirrored)] : []
        displays += externals.enumerated().map { index, identity in
            DisplayInfo(id: UInt32(index + 2), identity: identity, builtIn: false,
                        online: true, active: externalActive, mirrored: mirrored)
        }
        return DisplaySnapshot(displays: displays, lidClosed: lid)
    }

    static func main() {
        var policy = DisplayPolicy()
        expect(policy.wantsBuiltInOn(for: topology()), "manual mode starts enabled")
        policy.setManual(on: false)
        expect(!policy.wantsBuiltInOn(for: topology()), "manual off")
        expect(!policy.wantsBuiltInOn(for: topology(on: false)), "self-induced display removal preserves intent")
        expect(policy.wantsBuiltInOn(for: topology(on: false, externals: [])), "unplug restores")
        expect(policy.wantsBuiltInOn(for: topology()), "manual off is not retained across reconnect")

        policy.setAutomatic(true)
        expect(!policy.wantsBuiltInOn(for: topology()), "automatic mode applies immediately")
        policy.setManual(on: true)
        expect(policy.wantsBuiltInOn(for: topology(on: false)), "manual on overrides automatic")
        expect(policy.wantsBuiltInOn(for: topology(on: true)), "own callback preserves manual override")
        expect(!policy.wantsBuiltInOn(for: topology(externals: ["office"])), "new monitor clears override")
        policy.setAutomatic(false)
        expect(policy.wantsBuiltInOn(for: topology()), "disabling automatic restores")

        policy.setAutomatic(true)
        expect(policy.wantsBuiltInOn(for: topology(externals: [])), "automatic never disables only screen")
        expect(policy.wantsBuiltInOn(for: topology(externalActive: false)), "inactive external is not a safety screen")
        expect(policy.wantsBuiltInOn(for: topology(lid: true)), "closed lid forbids disabling")
        expect(policy.wantsBuiltInOn(for: topology(mirrored: true)), "mirroring refuses instead of changing layout")
        expect(policy.wantsBuiltInOn(for: topology(builtInPresent: false)), "absent built-in is handled")

        _ = policy.wantsBuiltInOn(for: topology())
        policy.stopAfterFailure()
        expect(policy.wantsBuiltInOn(for: topology(on: false)), "failure demands rollback")
        expect(policy.wantsBuiltInOn(for: topology()), "failure prevents automatic retry loop")
        policy.setManual(on: false)
        expect(!policy.wantsBuiltInOn(for: topology()), "explicit retry clears inhibition")
        policy.stopAfterFailure()
        expect(!policy.wantsBuiltInOn(for: topology(externals: ["new"])), "reconnect permits another attempt")

        policy.setManual(on: true)
        expect(policy.wantsBuiltInOn(for: topology(externals: ["new"])), "manual on held")
        expect(!policy.wantsBuiltInOn(for: topology(externals: ["new", "second"])), "adding a second external reapplies automatic")
        policy.setManual(on: true)
        expect(policy.wantsBuiltInOn(for: topology(externals: ["second", "new"])), "enumeration order is not a topology change")

        let offline = DisplayInfo(id: 99, identity: "ghost", builtIn: false, online: false, active: true, mirrored: false)
        var state = topology(externals: [])
        state.displays.append(offline)
        expect(state.externalDisplays.isEmpty, "offline external never counts even if active flag is stale")
        expect(!state.canDisable, "offline external cannot authorize disabling")

        // Exhaustive invariant: with no usable external, any combination of
        // automatic/manual/failure state must request a visible built-in panel.
        for automatic in [false, true] {
            for manual in [Optional<Bool>.none, true, false] {
                for failed in [false, true] {
                    for on in [false, true] {
                        var p = DisplayPolicy(automatic: automatic)
                        _ = p.wantsBuiltInOn(for: topology())
                        if let manual { p.setManual(on: manual) }
                        if failed { p.stopAfterFailure() }
                        expect(p.wantsBuiltInOn(for: topology(on: on, externals: [])), "last-display invariant")
                    }
                }
            }
        }

        expect(!WatchdogRules.shouldRecover(parentAlive: true, pipeOpen: true, heartbeatAge: 1, externalCount: 1), "healthy lease stays idle")
        expect(WatchdogRules.shouldRecover(parentAlive: false, pipeOpen: true, heartbeatAge: 0, externalCount: 1), "parent crash restores")
        expect(WatchdogRules.shouldRecover(parentAlive: true, pipeOpen: false, heartbeatAge: 0, externalCount: 1), "EOF restores")
        expect(WatchdogRules.shouldRecover(parentAlive: true, pipeOpen: true, heartbeatAge: 9, externalCount: 1), "UI hang restores")
        expect(WatchdogRules.shouldRecover(parentAlive: true, pipeOpen: true, heartbeatAge: 0, externalCount: 0), "last external unplug restores independently")
        expect(!WatchdogRules.shouldRecover(parentAlive: true, pipeOpen: true, heartbeatAge: 8, externalCount: 2), "timeout boundary")
        print("PASS: \(checks) policy and watchdog checks")
    }
}
