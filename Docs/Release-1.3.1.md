ScreenOff 1.3.1 fixes overlapping display-recovery calls that could cause excessive CPU and energy use.

A system report from the affected Mac showed both the app and its recovery helper inside macOS display-configuration calls. The app's log contained roughly 195,000 messages about waiting for a previous reconfiguration to finish.

- The recovery helper owns restoration. The main app observes its result instead of issuing competing enable commands, including during failure handling and quit.
- Closed-lid recovery sends no display-configuration commands. It keeps protection armed and resumes after the lid opens.
- Reopening the lid reapplies the saved display preference after recovery and settling, even if the Mac never slept.
- Repeated restore requests are coalesced. A retiring helper finishes before another recovery owner starts.
- Manual command-line recovery waits for an existing app/helper instead of issuing another competing configuration.

Validation: 357 policy/controller/recovery checks, 15 native interface checks, a physical guarded disable/enable test, and three helper IPC/restore-only checks passed. The simulated eight-hour closed-lid scenario sends no enable commands. These bounded checks do not constitute a full overnight energy measurement. Details are in Docs/Verification.md.

Physical follow-up in the installed app: with the lid closed and the external monitor connected and active, both processes used 0.14 CPU seconds over 108.60 seconds, about 0.129% of one CPU. No previous reconfiguration-wait messages were found. Reopening the lid reapplied the saved external-monitor-only mode. This short check is distinct from overnight use with a sleeping external display.

Your saved preference, single-switch interface, English text and absence of menu bar and Dock icons are preserved. To update, quit the previous ScreenOff with its power button, replace ScreenOff.app in Applications using **ScreenOff-1.3.1-arm64.dmg**, and reopen it.

Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**.

Activity Monitor's “12 hr Power” reflects historical average impact and will not reset immediately after this update. Check current Energy Impact and CPU use while assessing the fix.
