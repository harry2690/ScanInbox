#!/usr/bin/env python3
"""建立 arm64 App；發佈簽署由未追蹤的 JSON 設定指定。"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent

def load_release_config(path):
    data = json.loads(Path(path).read_text())
    identity = data.get("signingIdentity", "").strip()
    if not identity or identity == "-":
        raise ValueError("請在本機 release 設定填入 Developer ID Application 憑證 SHA-1 或完整識別名稱")
    if not (re.fullmatch(r"[0-9a-fA-F]{40}", identity) or identity.startswith("Developer ID Application: ")):
        raise ValueError("signingIdentity 必須是憑證 SHA-1 或 Developer ID Application 識別名稱")
    return data

def sign_arguments(identity, app):
    args = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        args += ["--options", "runtime", "--timestamp"]
    return args + [str(app)]

def build_icon(root, destination):
    source = root / "Assets/AppIcon.png"
    iconset = root / ".build/AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            suffix = "@2x" if scale == 2 else ""
            output = iconset / f"icon_{points}x{points}{suffix}.png"
            subprocess.run(["sips", "-z", str(pixels), str(pixels), str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(destination)], check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-config", type=Path, help="使用本機 JSON 指定發佈簽署身分")
    options = parser.parse_args()
    identity = load_release_config(options.release_config)["signingIdentity"].strip() if options.release_config else "-"
    app = ROOT / "dist/ScanInbox.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)
    cache = ROOT / ".build/module-cache"
    cache.mkdir(parents=True, exist_ok=True)
    args = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-target", "arm64-apple-macosx27.0", "-module-cache-path", str(cache), "-file-prefix-map", str(ROOT) + "=.", "-debug-prefix-map", str(ROOT) + "=.", "-framework", "AppKit", "-framework", "ServiceManagement", "-framework", "SystemConfiguration"]
    args += [str(p) for p in sorted((ROOT / "Sources/ScanInbox").glob("*.swift"))]
    args += ["-o", str(contents / "MacOS/ScanInbox")]
    subprocess.run(args, check=True)
    # Remove only the obsolete generated executable when rebuilding an older bundle.
    legacy_executable = contents / "MacOS/SharpScanner"
    if legacy_executable.exists():
        legacy_executable.unlink()
    resources = contents / "Resources/Receiver"
    if resources.exists():
        shutil.rmtree(resources)
    shutil.copytree(ROOT / "Receiver", resources, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for name in ("LICENSE", "LICENSE_EN", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(ROOT / name, contents / "Resources" / name)
    build_icon(ROOT, contents / "Resources/AppIcon.icns")
    info = {
        "CFBundleExecutable": "ScanInbox", "CFBundleIdentifier": "tw.local.SharpScanner",
        "CFBundleName": "ScanInbox", "CFBundleDisplayName": "ScanInbox",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.3.2", "CFBundleVersion": "32",
        "CFBundleIconFile": "AppIcon.icns",
        "LSMinimumSystemVersion": "27.0", "LSUIElement": True, "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "ScanInbox 採個人非商業使用授權。SHARP 商標屬其權利人；本軟體非官方產品。",
        "NSLocalNetworkUsageDescription": "接收您設定的印表機所傳送的掃描文件，並在主動模式連回印表機。",
        "NSDocumentsFolderUsageDescription": "將掃描文件儲存到您選擇的輸出資料夾。",
        "NSDesktopFolderUsageDescription": "將掃描文件儲存到您選擇的桌面資料夾。",
        "NSDownloadsFolderUsageDescription": "將掃描文件儲存到您選擇的下載資料夾。",
    }
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(sign_arguments(identity, app), check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    print("完成：", app)

if __name__ == "__main__":
    main()
