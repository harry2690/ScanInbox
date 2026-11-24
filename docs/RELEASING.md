# 建置、簽署與打包

本文件提供可重複執行的發佈流程。Apple 帳號、應用程式專用密碼、私鑰與公證憑證應留在本機鑰匙圈或發佈環境的機密儲存空間，不寫入原始碼或公開設定。

## 1. 準備環境

- Apple Silicon Mac、macOS 27 以上。
- 含 macOS 27 SDK 的 Xcode；`xcrun --show-sdk-version` 應顯示 27 或以上。
- Homebrew Python 3.13 或 3.14。
- 要提供一般下載安裝的 Developer ID 發佈版本，需備有 Apple Developer Program 的 Developer ID Application 憑證及對應私鑰。

套件已包含在 Receiver/vendor。App 未內嵌 Python，因此下載者也必須準備 README 列出的 Python 執行環境。簽署或公證不會自動消除此相依性。

## 2. 先測試與本機建置

```sh
/opt/homebrew/bin/python3.13 -m unittest discover -s Tests -v
zsh build.command
```

產物：`dist/ScanInbox.app`。沒有指定發佈設定時，建置工具使用本機執行用的 ad hoc 簽章；不需 Apple 帳號。此模式與提供他人一般下載安裝的發佈簽署不同。

## 3. 建立僅限本機的簽署設定

```sh
cp config/release.example.json config/release.local.json
security find-identity -v -p codesigning
```

在 `config/release.local.json` 的 `signingIdentity` 填入 Developer ID Application 憑證的 40 字元 SHA-1 識別碼，或完整的 Developer ID Application 識別名稱。使用識別碼可以避免將姓名直接寫入設定，但不會隱藏已簽署 App 內的憑證身分。

`notaryProfile` 是下一步建立的鑰匙圈設定檔名稱。此 JSON 不需要 Apple ID、密碼、私鑰內容或 .p12 檔。`release.local.json` 已加入 `.gitignore`，只提交空白的 `release.example.json`。

若只要建置並做發佈簽署：

```sh
/opt/homebrew/bin/python3.13 Scripts/build.py --release-config config/release.local.json
```

發佈簽署會啟用 Hardened Runtime 與安全時間戳，簽署結束後驗證 App。程式會將專案及第三方授權聲明放入 App，並使用路徑對映減少二進位內的本機原始碼絕對路徑。

## 4. 將公證憑證存入鑰匙圈

```sh
xcrun notarytool store-credentials "ScanInbox-Notary"
```

依工具的互動提示完成驗證。若使用 Apple ID，請依 Apple 要求準備應用程式專用密碼；不要把它貼進 README、JSON、版本控制或公開終端機記錄。

若採用其他鑰匙圈設定檔名稱，更新本機 JSON 的 `notaryProfile`。工具透過 `--keychain-profile` 取用憑證；打包腳本不讀取或保存 Apple ID 密碼。

## 5. 打包與公證

僅簽署及建立 ZIP，不向 Apple 提交：

```sh
/opt/homebrew/bin/python3.13 Scripts/release.py --config config/release.local.json
```

簽署、提交 Apple 公證並等待結果：

```sh
/opt/homebrew/bin/python3.13 Scripts/release.py --config config/release.local.json --notarize
```

只有加上 `--notarize` 才會上傳 App 至 Apple。腳本會：

1. 建置及 Developer ID 簽署 App。
2. 使用 ditto 建立 ZIP，保留 App 結構與資源。
3. 以鑰匙圈設定檔提交公證並等待結果。
4. 確認 Apple 回報 Accepted，將 ticket 附加到 App，執行 staple、簽章及 Gatekeeper 驗證。
5. 重新打包已附加 ticket 的 App。

產物為 `dist/ScanInbox-macOS-arm64.zip`。公證結果存於 `.build/notary-result.json`；未回報 Accepted 或驗證失敗時，腳本會中止，不會宣稱已完成公證。

本次專案整理只驗證本機建置、打包程式與測試流程，沒有使用發佈者憑證實際提交 Apple。正式公證結果應以發佈者自己的執行結果為準。

## 6. 發佈前驗收

在乾淨的測試環境解壓縮 ZIP，確認 App 可啟動，且沒有預填私人 IP、印表機別名或個人資料夾。安裝 Python 後新增測試印表機，確認接收、輸出目錄、紀錄、登入選項與版本資訊。

原始碼儲存庫不提交 dist 或 .build；若要提供下載，只將已檢查的 ZIP 放入發佈附件。不要把 settings.json、SQLite、掃描文件、日誌或封包附在發佈包裡。更多檢查項目見 [公開前檢查](PUBLICATION.md)。

## 簽署後可公開與不可公開的資料

簽署憑證是公開金鑰身分的一部分。已簽署 App 通常可查到憑證持有人名稱、Team ID、憑證鏈與時間戳；不能一面保留有效 Developer ID 簽章、一面承諾完全隱藏發佈者身分。這不表示 App 包含私鑰或 Apple ID 密碼。

私鑰、憑證匯出檔、應用程式專用密碼、API 私鑰及鑰匙圈資料庫不可隨原始碼或下載包公開。公開前仍需檢查實際簽章與憑證內容，不應只依檔名判斷。

## Apple 官方文件

- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)
