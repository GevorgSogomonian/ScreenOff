ScreenOff 1.3.0 makes the app and current project English-only.

- Translated the settings window, display status, error messages, login instructions, tooltips and accessibility labels.
- Declared English as the app's only supported localization.
- Translated the README, installation guide, contribution instructions, issue forms, pull request template and release notes. Updated the settings screenshot.
- Build and packaging scripts now create fresh bundles and staging folders, preventing obsolete language files from carrying into a new release.

The single display preference, background operation, absence of menu bar and Dock icons, window dismissal, display recovery and resource-use fixes are unchanged. Existing preferences are preserved.

Validation: all 330 policy/controller/recovery checks and all 15 native interface checks passed. These checks use simulated hardware or isolated preview windows and issue no physical display transactions. The translated interface was also visually inspected. Earlier physical cable-removal and lock/unlock results remain documented in Docs/Verification.md; this translation update does not claim new physical validation.

To update, quit the old ScreenOff using the power button in settings, open **ScreenOff-1.3.0-arm64.dmg**, replace **ScreenOff.app** in **Applications**, and reopen it through Spotlight or Finder.

Assets include the DMG, app ZIP, source ZIP and SHA256SUMS.txt. Built for Apple Silicon and macOS 13+, ad-hoc signed without Apple notarization. If Gatekeeper blocks launch, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable system security.

English app downloads start with this release. Previously published binaries, source archives and Git history retain their original contents; the current documentation and release-page descriptions are in English.
