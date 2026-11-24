# ScanInbox Agent Guide

## Product and support scope

ScanInbox is a macOS menu bar app that receives scanned documents from printers. Current support is limited to compatible SHARP multifunction printers. Do not describe generic FTP support as support for every printer brand or claim that all SHARP models are verified.

Target platform: Apple Silicon, macOS 27 or later. The UI uses native SwiftUI and Liquid Glass controls. A Python subprocess runs pyftpdlib, routes uploads by source IPv4, and stores scan history in SQLite.

Read README.md for user-facing behavior, docs/USAGE.md for network and storage behavior, docs/RELEASING.md for packaging, and docs/PUBLICATION.md before preparing public source files. Keep this AGENTS.md in English. User-facing UI and existing Chinese documentation use Traditional Chinese with Taiwan terminology.

## Repository map

- Sources/ScanInbox: app entry point, settings, UI, network interfaces, and receiver process lifecycle.
- Receiver/receiver.py: FTP routing, filesystem restrictions, structured events, and scan history.
- Receiver/bootstrap.py: load the bundled vendor packages in isolation. Never generate Python bytecode inside a signed app bundle.
- Receiver/vendor: pinned third-party dependencies and their original licenses.
- Assets/AppIcon.png: approved app icon source; build.py generates icon sizes and AppIcon.icns.
- Scripts/build.py: compile, package resources, and sign the app.
- Scripts/release.py: create the release ZIP and optionally submit it for notarization.
- Tests: local receiver and packaging tests.
- config/*.example.json: public examples, without personal defaults.

## Dependency maintenance

The supported Python runtime uses three pinned, vendored distributions: pyftpdlib 2.1.0 (FTP core), pyasyncore 1.0.5 (asyncore compatibility), and pyasynchat 1.0.5 (asynchat compatibility). pyasynchat also requires pyasyncore >= 1.0.2. Use requirements.txt and Receiver/vendor/*.dist-info/METADATA as the source of truth. Python itself is external; sqlite3 is a standard-library module, and Apple frameworks are not pip dependencies.

Read docs/DEPENDENCIES_EN.md before dependency changes. Updating requirements.txt alone does not update the running app. Update the reviewed vendor snapshot and licenses together, remove obsolete versions, update both READMEs and dependency guides, run receiver/packaging tests on each supported Python version, rebuild, and verify the signed app after execution. Do not install into an already signed bundle or upgrade dependencies merely because a new version exists. Preserve a coherent rollback without touching user settings, history, or scanned files.

## Names and backward compatibility

Use ScanInbox for the product name, executable, app bundle filename, source directory, UI labels, and release artifacts.

The project root directory name is not part of the app's public identity. Preserve these existing runtime identifiers unless an explicit migration is requested and tested:

- Bundle ID: tw.local.SharpScanner
- User data: ~/Library/Application Support/SharpScanner/
- Login agent: tw.local.SharpScanner.login
- Old SharpScanner.app name in migration code

These are compatibility identifiers, not forgotten branding. Changing them without migration can lose access to settings or history and break login startup. Do not rename or overwrite the user's existing data or printer configuration during cosmetic cleanup.

## Data and privacy

- Fresh installs start with an empty printer list. Do not add real printer IPs, personal aliases, absolute home paths, Apple IDs, or credentials to source files.
- User settings and runtime history belong in Application Support, not in the repository.
- Keep personal development/release settings in ignored *.local.json files. Commit only sanitized *.example.json files.
- Keep private keys and passwords in Keychain or an appropriate secret store. Never print their values or include them in logs, screenshots, source, or release archives.
- Preserve the original licenses in Receiver/vendor. Original project code uses the custom personal noncommercial license in LICENSE, not MIT. Do not remove trademark notices or change licensing without authorization.

## Implementation constraints

- Use GlassSwitchStyle for every visible toggle. This user-approved custom style uses native glass materials with app-defined geometry; do not describe it as the standard macOS switch. Preserve its on, off, disabled, reduced-motion, keyboard, and accessibility behavior.
- Preserve the approved macOS 27 native design, including disabled states. Obtain user approval before materially changing layout or interaction patterns.
- Keep source IP restrictions, per-printer filesystem roots, exclusive file creation, and overwrite protection.
- Do not enable downloads, existing-file deletion, renaming, append/resume, foreign-host data connections, or privileged data ports to work around compatibility issues.
- Do not infer document integrity from FTP login or transfer success. Users must be able to inspect the actual file.
- Do not initialize Git, commit, push, publish, enable login startup, or submit software to Apple unless the current task authorizes it. Only --notarize may trigger notarization submission.

## Build and verification

Run from the repository root:

```sh
/opt/homebrew/bin/python3.13 -m unittest discover -s Tests -v
zsh build.command
```

The output is dist/ScanInbox.app. Use checks appropriate to the change. For packaging changes, verify codesign and confirm that running the app does not invalidate its signature. Do not replace device testing with compilation or loopback tests. Mocked notarization tests do not prove an actual Apple submission succeeded.

On 2026-11-24, the user reported successful receipt from both newer and older SHARP printers using the GUI app. The known model includes BP-70C55. Unspecified models, simultaneous multi-interface scans, login startup, and sleep recovery still need their own evidence.
