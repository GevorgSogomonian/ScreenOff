ScreenOff 1.2.2

Fixes the settings window remaining on screen when switching Stage Manager groups.

Switching to another application now automatically hides ScreenOff's window. This also applies to ordinary focus changes outside Stage Manager. Display control continues in the background; reopen ScreenOff through Spotlight or Applications to bring settings back.

The app still has no menu bar or Dock icon. The saved display preference is unchanged. This uses native AppKit behavior and adds no background timers.

All 15 native interface checks passed, including focus handoff to a separate test application, window dismissal and reopening in the same process.

Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. To update, quit the old version with the power button in settings and replace ScreenOff.app in Applications using the DMG.
