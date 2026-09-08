ScreenOff for Apple Silicon MacBooks. Two menu bar switches control the built-in display and automatic disabling when an external monitor connects.

Installation: open **ScreenOff-1.0.0-arm64.dmg** and drag **ScreenOff.app** into **Applications**. A ZIP containing the same app is also available.

Automatic mode registers launch at login. A manual enable takes priority until the set of external monitors changes. Disconnecting the external monitor or quitting the app restores the built-in display. An independent helper monitors its connection to the main app and can restore the display on its own.

Tested on a MacBook Pro M1 with macOS 27.0 beta (26A5425a): actual panel disabling/enabling and independent recovery after loss of communication. All 54 automated policy and recovery checks passed. Physical sleep, cable-removal and subsequent-login scenarios are listed for manual validation in Docs/Verification.md.

The app is ad-hoc signed and is not notarized by Apple. If Gatekeeper blocks it, attempt to launch it, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable system security.

ScreenOff uses a private macOS API, which operating system updates may change. Requires Apple Silicon, macOS 13+, an open lid and an active external monitor. Turn off display mirroring before disabling the panel.
