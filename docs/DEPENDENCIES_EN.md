# Dependency maintenance

[繁體中文](DEPENDENCIES.md) | **English**

## Inventory and source of truth

| Package | Pinned version | Import name | Upstream | License file |
|---|---|---|---|---|
| pyftpdlib | 2.1.0 | pyftpdlib | https://github.com/giampaolo/pyftpdlib | Receiver/vendor/pyftpdlib-2.1.0.dist-info/licenses/LICENSE |
| pyasyncore | 1.0.5 | asyncore | https://github.com/simonrob/pyasyncore | Receiver/vendor/pyasyncore-1.0.5.dist-info/licenses/LICENSE |
| pyasynchat | 1.0.5 | asynchat | https://github.com/simonrob/pyasynchat | Receiver/vendor/pyasynchat-1.0.5.dist-info/licenses/LICENSE |

This inventory is based on the repository's requirements.txt and vendored distribution METADATA, not a claim that these versions are the latest. The project does not currently declare additional Python runtime dependencies. Upstream development, test, and TLS extras are not installed merely because their names appear in upstream METADATA.

For the supported Python 3.13/3.14 runtime, pyftpdlib's METADATA requires both pyasyncore and pyasynchat. pyasynchat in turn requires pyasyncore >= 1.0.2. Keep the dependency set compatible rather than treating the three pins as unrelated packages.

```text
ScanInbox (SwiftUI app)
  -> Homebrew Python 3.13 or 3.14 (external runtime)
     -> Receiver/bootstrap.py
        -> Receiver/vendor/pyftpdlib 2.1.0
           -> asyncore provided by pyasyncore 1.0.5
           -> asynchat provided by pyasynchat 1.0.5
              -> pyasyncore >= 1.0.2
```

SQLite is accessed through Python's standard-library sqlite3 module; it is not an extra pip package. SwiftUI, AppKit, Combine, Foundation, ServiceManagement, and SystemConfiguration are Apple frameworks, not vendored Python dependencies.

## How the app loads dependencies

Model.swift locates Homebrew Python 3.13, then 3.14. The subprocess runs in isolated mode. Receiver/bootstrap.py disables bytecode generation and inserts its adjacent vendor directory before importing receiver.py. Scripts/build.py copies Receiver into Contents/Resources/Receiver when building the app.

Consequently, neither a requirements.txt edit nor pip install in an unrelated environment changes a built app. Do not patch an already signed app's vendor directory; rebuild and sign it after updating the source tree. Preserve the no-bytecode behavior so runtime cache writes do not invalidate the signature.

## Upgrade procedure

1. Review the upstream release notes, Python requirements, security notices, dependency metadata, and license changes. Select compatible versions; do not blindly remove pins or assume the newest release is compatible with the FTP hooks used here.
2. Update all affected pins in requirements.txt. Prepare a fresh candidate directory, never install over the current vendor tree. Run this from the repository root, replacing NEW_DIRECTORY with a new unused path under .build:

   ```sh
   /opt/homebrew/bin/python3.13 -m pip install --no-compile --target .build/NEW_DIRECTORY -r requirements.txt
   ```

   This maintenance command accesses the package registry. It is not required for ordinary app use. Let pip resolve declared dependencies, then inspect every resulting package and its distribution metadata. If the set expands, pin and document the new runtime packages before proceeding.
3. Check that candidate versions match requirements.txt and are compatible with both supported Python versions. Preserve distribution metadata and all licenses. Remove local paths, bytecode caches, credentials, and unrelated build artifacts; do not discard license files to reduce size.
4. Replace Receiver/vendor with the reviewed candidate as a coherent set. Remove obsolete package and dist-info directories so two versions do not coexist. Do not delete the user's configuration, history, or scan output folders.
5. Update both README dependency tables, both dependency guides, THIRD_PARTY_NOTICES.md, and any version-specific license links. Include changes to Python or Apple SDK requirements where applicable.
6. Run the receiver and packaging tests under each supported Python runtime:

   ```sh
   /opt/homebrew/bin/python3.13 -m unittest discover -s Tests -v
   /opt/homebrew/bin/python3.14 -m unittest discover -s Tests -v
   zsh build.command
   codesign --verify --deep --strict dist/ScanInbox.app
   ```

7. Validate the app against real supported SHARP devices: anonymous login, active and passive data paths when supported by the device, per-source routing, filenames, overwrite rejection, interrupted transfer cleanup, and history. Check the custom pyftpdlib integration points listed below, and recheck the signature after running the app.
8. Package and distribute using docs/RELEASING.md. Record what was tested and which models/runtime versions were not tested. Do not claim notarization or device compatibility from unit tests alone.

## Integration points to review

- DummyAuthorizer permission behavior and the per-connection authorizer selection.
- FTPHandler.proto_cmds and the custom DELE, STOR, APPE, REST, and STOU handlers.
- AbstractedFS.open and exclusive file creation; the returned file object's name must remain a filesystem path for callbacks.
- on_file_received, on_incomplete_file_received, and on_disconnect callback order.
- Active/passive connections, foreign-host restrictions, and privileged-port restrictions.
- Structured stdout events, separate diagnostic stderr, password redaction, and SQLite history persistence.

## Rollback and scope

Revert the complete dependency update together: requirements.txt, Receiver/vendor, metadata, and documentation. Rebuild and sign the app; do not mix an old pin file with new vendor contents. Keep user settings, the SQLite history database, and scanned documents untouched. If a future change also migrates the database, plan and test rollback separately before deployment.

This guide defines the maintenance workflow. It does not mean an upgrade has been performed or that every upstream version has been audited. Third-party components retain their original licenses; the project's custom personal noncommercial license does not replace them.
