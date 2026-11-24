# ScanInbox

[繁體中文](README.md) | **English**

ScanInbox is a macOS menu bar app that receives scanned documents from printers. Currently, scan reception is supported only for compatible SHARP multifunction printers. Configure each printer's IP address, alias, and output folder, then scan from the printer's control panel to save documents directly to the selected folder and review reception results in the app.

This is an independently developed project, not an official SHARP product. Original project code is provided under the [Personal Noncommercial Use License](LICENSE_EN), which permits personal use only and prohibits commercial and organizational use. Third-party packages retain their own licenses.

## Features

- Multiple printers, each with its own source IP address, alias, and output folder.
- Automatic detection of IPv4 addresses across multiple Mac network interfaces, with reception on multiple interfaces simultaneously.
- Menu bar operation, Dock and Command+Tab access while a window is open, per-printer pause, service controls, and optional launch at login.
- Scan history, filename and alias search, Finder reveal, and error details.
- Connections accepted only from enabled printer IP addresses; downloads and overwriting existing files are blocked.

## Requirements

| Component | Requirement |
|---|---|
| Mac | Apple Silicon, macOS 27 or later |
| Python | Homebrew Python 3.13 or 3.14 |
| Printer | A SHARP multifunction printer with compatible FTP / Scan to Desktop capabilities; other brands are not currently supported |
| Network | The Mac and printer must be able to establish control and data connections with each other |
| Building from source | Xcode and development tools with the macOS 27 SDK |

Python is not currently embedded in the app. Install it even if you use a packaged app:

```sh
brew install python@3.13
```

The receiver packages are included. You do not need to run pip separately to use the app.

## Third-party dependencies and runtime

| Package / environment | Version or requirement | Role | Delivery / license |
|---|---|---|---|
| [pyftpdlib](https://github.com/giampaolo/pyftpdlib) | 2.1.0 | FTP receiver, active/passive data connections, authorization, and filesystem hooks | Bundled; MIT |
| [pyasyncore](https://github.com/simonrob/pyasyncore) | 1.0.5 | asyncore-compatible event loop used by the receiver | Bundled; PSF License v2, subject to the complete original notices |
| [pyasynchat](https://github.com/simonrob/pyasynchat) | 1.0.5 | asynchat-compatible asynchronous communication layer; depends on pyasyncore | Bundled; PSF License v2, subject to the complete original notices |
| Python | Homebrew 3.13 or 3.14 | Runs the receiver; sqlite3, json, and similar modules come from the standard library | Installed separately; not embedded |
| Apple system frameworks | macOS 27 SDK / runtime | SwiftUI, AppKit, Combine, Foundation, ServiceManagement, and SystemConfiguration | Supplied by Apple's SDK and macOS; not pip packages |

Python versions are pinned in `requirements.txt`; the actual copies used by the app live in `Receiver/vendor`. The bootstrap prioritizes those copies. **Changing requirements.txt or upgrading system pip packages alone does not update the receiver bundled in the app.** Maintenance must update the pins, vendored files, and license metadata together, followed by testing and rebuilding.

See the [dependency maintenance guide](docs/DEPENDENCIES_EN.md) for the dependency graph, upgrade procedure, and rollback instructions, and [third-party notices](THIRD_PARTY_NOTICES.md) for the original licenses.

## Installation and your first scan

1. Obtain the ScanInbox app, or build it from source using the instructions below. Place it in a permanent application location and open it.
2. Click the toolbar “+” button. Enter the printer's IP address, choose a recognizable alias, and select an output folder.
3. Open Shared Settings (“共用設定”) to view the automatically detected Mac addresses and receiver port, which defaults to TCP 4687. You do not need to enter the Mac's IP address manually.
4. Create a scan destination on the printer that points to a reachable Mac address and the same port. For a standard FTP destination, use anonymous FTP. For a Desktop destination, configure a compatible destination using that model's interface. The app does not automatically create or modify the printer's address book.
5. In the app, select Start Receiver Service (“開始接收服務”). Once the status shows that the receiver service is running (“接收服務運作中”), select the new destination on the printer's control panel and scan.
6. Check the scan history for the result, then open the output document to verify its page count and contents.

A fresh installation has no preconfigured printers or personal network addresses. If macOS requests local network or output-folder access, grant the required permissions for reception to work.

### Printer destination settings

| Setting | Value |
|---|---|
| Receiver host | One of the Mac IPv4 addresses shown in Shared Settings that the printer can reach |
| Receiver port | The same port as the app; default: 4687 |
| Login | Anonymous FTP; use anonymous if the interface requires a username |
| Processing directory | Leave blank or use the root directory; create any required subdirectory in advance |
| SSL / TLS | This version uses plain FTP; do not enable TLS |

Standard FTP and Desktop destination fields and registration procedures may differ by model. Support is currently limited to SHARP multifunction printers. The author has reported successful reception from both newer and older models; the known tested models include the BP-70C55. This does not establish compatibility with every SHARP model. Other brands are not currently supported.

## Everyday use

| Action | Result |
|---|---|
| Select a printer in the sidebar | Show that printer's settings, status, and history |
| All Scan History | Show results from all printers |
| Pause / enable a printer | Control whether that printer may upload |
| Stop Receiver Service | Pause reception from all sources while retaining settings |
| Close the last app window | Hide the Dock icon while keeping menu bar reception running |
| Remove a printer | Remove only its configuration; keep scanned files and historical records |
| Show in Finder | Locate a successfully received file that still exists |

While an app window is open, ScanInbox appears in the Dock and Command+Tab switcher. Minimized windows remain accessible. Closing the last app window hides its Dock icon; reopen the management window from the menu bar.

“Ready” means the receiver is prepared to accept uploads, not that the printer has been detected online. Settings that require a service restart cannot be applied during a transfer. Save is also disabled when nothing has changed or required input is incomplete.

Shared Settings controls launch at login, automatic reception, the receiver port, history retention, and diagnostic logging. Reception is unavailable while the Mac is asleep, the user is logged out, or the app is closed. See the [usage guide](docs/USAGE.md) for network details and troubleshooting; that guide is currently in Traditional Chinese.

## Build from source

Run from the project root:

```sh
zsh build.command
open dist/ScanInbox.app
```

The output is `dist/ScanInbox.app`. The default build is intended for local execution and does not require an Apple account. To sign and package the app for distribution, follow the [signing and release guide](docs/RELEASING.md), currently in Traditional Chinese.

Run tests:

```sh
/opt/homebrew/bin/python3.13 -m unittest discover -s Tests -v
```

## Project structure

| Location | Purpose |
|---|---|
| Sources/ScanInbox | SwiftUI interface, settings, network detection, and receiver process management |
| Receiver/receiver.py | FTP reception, source-based routing, file restrictions, and scan history |
| Receiver/bootstrap.py | Isolated loading of bundled Python packages; prevents bytecode caches inside the app |
| Receiver/vendor | Pinned third-party packages and their original licenses |
| Assets/AppIcon.png | App icon source; the build generates all sizes and the ICNS file |
| Scripts/build.py | Compile and sign the app |
| Scripts/release.py | Create a release ZIP, with optional Apple notarization submission |
| Tests | Local receiver and release-tool tests |
| config/*.example.json | Public configuration examples without personal settings |
| AGENTS.md | Development and verification instructions for developers and agents |

User settings and history are stored in `~/Library/Application Support/SharpScanner/`, outside the source tree. Scanned files are stored in each printer's selected output folder. Publisher-specific configuration belongs in `config/release.local.json`, which is excluded by `.gitignore`.

## Naming and settings compatibility

The app, executable, and development directory use ScanInbox (`Sources/ScanInbox`). To preserve existing user data, the Bundle ID `tw.local.SharpScanner`, Application Support directory, and login-agent identifiers retain their compatibility names. You do not need to add printers again or move history. These identifiers are not the product name; the project root directory may also be named as needed.

## License and trademarks

Original code and documentation are provided under the [ScanInbox Personal Noncommercial Use License](LICENSE_EN). This is not the MIT License and is not represented as an open-source license meeting the OSI definition. Refer to the full license for the conditions governing personal use, modification, and free redistribution.

SHARP, the Sharp name, and related trademarks belong to Sharp Corporation and/or its affiliates or other lawful rights holders. These names are used only to identify compatible equipment. This project is not an official SHARP product and has not been certified, sponsored, or endorsed by SHARP. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the complete notices and third-party licenses; that document is currently in Traditional Chinese.

### Receipt bubbles

After a successful scan upload, a bubble below the menu bar icon shows the printer alias and file count. Consecutive uploads from the same printer update the count, and the bubble closes about five seconds after the last update. Other printers are shown in sequence. Only new successful uploads trigger bubbles; loading history does not. The count refers to files, not document pages.

### Working with scan history

Double-click a scan record to open its file with the default application. Right-click for Open File, Open Containing Folder, or Delete Record. Deleting records removes history only and keeps the actual files. When multiple records are selected, actions apply to the selection. If a file has been moved or deleted, the app asks whether to delete its history record. Choose Keep or Delete.

Click the Time, Filename, or Size column header to sort scan history; click again to reverse the order. The default is newest first. Filenames use natural ordering (for example, 2 before 10), and sizes are sorted by their byte counts. Search results and incoming records follow the current sort order.

### Hiding windows and quitting

Command+Q hides the management and shared settings windows and the Dock icon while background receiving continues. Unsaved settings remain in the hidden windows. Use Open Management Window or Shared Settings from the menu bar to show them again. To stop the background app, choose Quit ScanInbox from the menu bar; active transfers require confirmation before stopping.
