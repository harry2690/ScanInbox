# 第三方套件維護

**繁體中文** | [English](DEPENDENCIES_EN.md)

## 套件清單與依據

| 套件 | 固定版本 | 匯入名稱 | 上游 | 授權位置 |
|---|---|---|---|---|
| pyftpdlib | 2.1.0 | pyftpdlib | https://github.com/giampaolo/pyftpdlib | Receiver/vendor/pyftpdlib-2.1.0.dist-info/licenses/LICENSE |
| pyasyncore | 1.0.5 | asyncore | https://github.com/simonrob/pyasyncore | Receiver/vendor/pyasyncore-1.0.5.dist-info/licenses/LICENSE |
| pyasynchat | 1.0.5 | asynchat | https://github.com/simonrob/pyasynchat | Receiver/vendor/pyasynchat-1.0.5.dist-info/licenses/LICENSE |

依據為專案的 requirements.txt 與隨附套件的 METADATA，並非宣稱上述版本是最新版。目前沒有另行宣告其他 Python 執行依賴；上游 METADATA 列出的開發、測試及 TLS 額外套件，不代表本 App 已安裝或使用。

在本專案支援的 Python 3.13／3.14 環境中，pyftpdlib 的 METADATA 要求 pyasyncore 與 pyasynchat；pyasynchat 又要求 pyasyncore >= 1.0.2。更新時須一起確認相容性，不能將三個固定版本視為互不相關。

```text
ScanInbox（SwiftUI App）
  → 外部 Homebrew Python 3.13／3.14
    → Receiver/bootstrap.py
      → Receiver/vendor/pyftpdlib 2.1.0
        → pyasyncore 1.0.5 提供 asyncore
        → pyasynchat 1.0.5 提供 asynchat
          → pyasyncore >= 1.0.2
```

SQLite 使用 Python 標準函式庫 sqlite3，不是另外安裝的 pip 套件。SwiftUI、AppKit、Combine、Foundation、ServiceManagement、SystemConfiguration 則是 Apple 系統框架。

## 實際載入與打包方式

Model.swift 優先尋找 Homebrew Python 3.13，其次為 3.14，並以隔離模式啟動。Receiver/bootstrap.py 禁止產生 bytecode，將相鄰 vendor 目錄置於匯入搜尋路徑前方，再執行 receiver.py。Scripts/build.py 會把 Receiver 複製到 App 的 Contents/Resources/Receiver。

因此，只修改 requirements.txt，或在其他環境執行 pip install，都不會更新已打包 App。不要直接修改已簽署 App 內的 vendor；必須更新原始碼副本後重新建置及簽署，並保留禁止快取寫入的行為。

## 更新流程

1. 查閱上游版本說明、Python 需求、安全公告、相依套件與授權變更，選擇相容版本；不要直接取消固定版本或假設最新版必然相容。
2. 修改 requirements.txt 中所有受影響的固定版本。在專案根目錄準備全新的候選目錄，不覆蓋現有 vendor；將 NEW_DIRECTORY 替換為 .build 下尚未使用的目錄名稱：

   ```sh
   /opt/homebrew/bin/python3.13 -m pip install --no-compile --target .build/NEW_DIRECTORY -r requirements.txt
   ```

   此維護命令會連線套件來源，一般使用 App 不需要執行。讓 pip 解決套件宣告的相依關係，再檢查所有安裝結果與中繼資料；如新增其他執行套件，必須補上固定版本與文件。
3. 確認候選版本與 requirements.txt 一致，且相容於兩個支援的 Python 版本。保留中繼資料及完整授權，排除本機路徑、快取、憑證及無關產物；不能為縮小體積而刪除授權。
4. 將已審查的候選套件整組替換 Receiver/vendor，移除過期的套件及 dist-info，避免新舊版本並存。不要碰觸使用者設定、紀錄及掃描文件。
5. 同步更新中英文 README 的套件表、兩份維護指南、THIRD_PARTY_NOTICES.md 與帶版本的授權連結；如有 Python 或 SDK 需求變更，也要一起更新。
6. 在各支援版本執行接收與打包測試：

   ```sh
   /opt/homebrew/bin/python3.13 -m unittest discover -s Tests -v
   /opt/homebrew/bin/python3.14 -m unittest discover -s Tests -v
   zsh build.command
   codesign --verify --deep --strict dist/ScanInbox.app
   ```

7. 使用實際支援的 SHARP 設備驗證匿名登入、設備支援的主動／被動資料路徑、來源分流、檔名、不覆寫、中斷清理及紀錄。依下節確認自訂掛鉤，並在 App 執行後再次驗證簽章。
8. 依 docs/RELEASING.md 打包，清楚記錄已測與未測的設備及環境。單元測試不能取代公證或實機相容性證據。

## 更新時特別檢查

- DummyAuthorizer 權限及每條連線各自選擇的授權根目錄。
- FTPHandler.proto_cmds 與 DELE、STOR、APPE、REST、STOU 的自訂處理。
- AbstractedFS.open 的排他建立行為，以及回傳檔案物件的 name 是否仍為路徑。
- on_file_received、on_incomplete_file_received、on_disconnect 的回呼順序。
- 主動／被動資料連線、其他主機連線限制及特權埠限制。
- stdout 結構化事件、stderr 診斷、密碼遮蔽及 SQLite 保存。

## 回復與範圍

需要回復時，將 requirements.txt、Receiver/vendor、中繼資料與文件整組回復後重新建置及簽署，不要混用舊版固定清單與新版套件。保留使用者設定、SQLite 與掃描文件；若未來更新涉及資料庫遷移，部署前須另外設計及測試回復流程。

這是維護流程說明，不代表已執行套件升級或對每個上游版本完成稽核。第三方元件保留原有授權，不由專案的個人非商業授權取代。
