#!/usr/bin/env python3
"""簽署並封裝；只有明確指定 --notarize 才向 Apple 提交。"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from build import load_release_config

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "config/release.local.json")
    parser.add_argument("--notarize", action="store_true", help="提交 Apple 公證，成功後 staple 並重新封裝")
    args = parser.parse_args()
    config = load_release_config(args.config)
    profile = config.get("notaryProfile", "").strip()
    if args.notarize and not profile:
        parser.error("公證需在本機設定指定 notaryProfile（鑰匙圈設定檔名稱）")
    subprocess.run([sys.executable, str(ROOT / "Scripts/build.py"), "--release-config", str(args.config.resolve())], check=True)
    app = ROOT / "dist/ScanInbox.app"
    archive = ROOT / "dist/ScanInbox-macOS-arm64.zip"
    def package():
        if archive.exists():
            archive.unlink()
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
    package()
    if args.notarize:
        result = subprocess.run(["xcrun", "notarytool", "submit", str(archive), "--keychain-profile", profile, "--wait", "--output-format", "json"], check=True, capture_output=True, text=True)
        report = json.loads(result.stdout)
        report_dir = ROOT / ".build"
        report_dir.mkdir(exist_ok=True)
        (report_dir / "notary-result.json").write_text(json.dumps(report, indent=2))
        if report.get("status") != "Accepted":
            raise SystemExit("Apple 尚未接受公證；結果已寫入 .build/notary-result.json，不應視為發佈完成")
        subprocess.run(["xcrun", "stapler", "staple", str(app)], check=True)
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], check=True)
        package()
    print("封裝完成：", archive)

if __name__ == "__main__":
    main()
