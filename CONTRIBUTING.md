# Contributing to ScreenOff

Bug reports, suggestions and pull requests are welcome. Please use English for reports, discussions, code comments and documentation.

## Reporting an issue

Use [Issues](https://github.com/GevorgSogomonian/ScreenOff/issues/new/choose). For a bug, include the ScreenOff version, Mac model, macOS version, monitor/dock connection, the switch setting and steps to reproduce. Describe what you expected and what happened. Remove private information from screenshots and logs.

For a security vulnerability, follow [SECURITY.md](SECURITY.md).

## Sending a change

1. Fork the repository and create a branch in your fork.
2. Make a focused change. Discuss larger changes in an issue first.
3. Run the relevant checks below and describe their results.
4. Open a pull request against `main`. The maintainer, [@GevorgSogomonian](https://github.com/GevorgSogomonian), reviews and merges contributions.

Public access permits reading, downloading and forking. It does not grant write, merge or release-publishing access to this repository. Contributions are submitted under the existing [MIT license](LICENSE).

## Development and checks

Use a Mac with Xcode Command Line Tools installed. The distributed app targets Apple Silicon and macOS 13 or later. Intel display control has not been validated.

```sh
bash Scripts/test.sh
bash Scripts/build.sh
```

`test.sh` exercises the display policy and recovery controller using simulated hardware. `build.sh` compiles and signs the app locally; it does not launch it. For changes to the window or launch behavior, also run:

```sh
bash Scripts/test-interface.sh
```

The interface check opens isolated test windows and transfers focus between them. It does not control physical displays or change ScreenOff preferences. Physical display tests are separate opt-in commands documented in the [README](README.md); state explicitly whether you performed them.

Display-control changes must preserve recovery when the external display disconnects, avoid disabling the only usable display, and keep the independent watchdog working. See [Architecture](Docs/Architecture.md) and [Verification](Docs/Verification.md).

## Review and CI

Changes to `main` require a pull request, maintainer code-owner approval, a passing `build` check and resolved review conversations. New commits dismiss stale approvals. External fork workflows wait for maintainer approval before they run. Workflow tokens are read-only and cannot approve pull requests.

The maintainer performs the final merge; automatic merging is disabled. Pull requests are squash-merged and merged branches in this repository are deleted automatically. The repository owner retains administrative access, including GitHub's owner override for exceptional maintenance and owner-authored changes.

## Maintainer releases

Run the checks, update the app version and installation notes, and package with `bash Scripts/package.sh`. Publish the DMG, app ZIP, source archive and checksums in a GitHub Release. Downloadable releases are published by the maintainer; pull-request CI artifacts are test builds.
