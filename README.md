# ScanInbox

**繁體中文** | [English](README_EN.md)

ScanInbox 是在 Mac 接收印表機掃描文件的選單列 App，目前僅支援 SHARP 事務機的掃描接收。為每台印表機設定 IP、別名與輸出資料夾後，就能從印表機面板掃描，將文件直接存入指定資料夾，並在 App 查看接收結果。

本專案為獨立開發，非 SHARP 官方產品。原創程式碼採 [個人非商業使用授權](LICENSE)，僅供個人使用，禁止商業及組織用途；第三方套件另依其原有授權。

## 功能

- 多台印表機，各自設定來源 IP、別名與輸出資料夾。
- 自動列出 Mac 的多張網卡 IPv4 位址，同時接收不同介面的連線。
- 選單列常駐、視窗開啟時支援 Dock 與 Command+Tab、單台暫停、整體啟停與可選的登入後自動啟動。
- 掃描紀錄、檔名及別名搜尋、Finder 定位與錯誤資訊。
- 僅接受已啟用的印表機 IP，拒絕下載與覆寫既有檔案。

## 系統需求

| 項目 | 需求 |
|---|---|
| Mac | Apple Silicon，macOS 27 以上 |
| Python | Homebrew Python 3.13 或 3.14 |
| 印表機 | 具備相容 FTP／Scan to Desktop 功能的 SHARP 事務機；其他品牌目前不在支援範圍 |
| 網路 | Mac 與印表機可互相建立控制及資料連線 |
| 從原始碼建置 | 含 macOS 27 SDK 的 Xcode 與開發工具 |

目前 App 尚未內嵌 Python。即使使用已打包的 App，仍需先安裝 Python：

```sh
brew install python@3.13
```

接收套件已隨附，使用 App 不需要另外執行 pip。

## 第三方套件與執行環境

| 套件／環境 | 版本或需求 | 用途 | 提供方式／授權 |
|---|---|---|---|
| [pyftpdlib](https://github.com/giampaolo/pyftpdlib) | 2.1.0 | FTP 接收核心、主動／被動資料連線、權限與檔案系統介面 | 隨 App 附帶；MIT |
| [pyasyncore](https://github.com/simonrob/pyasyncore) | 1.0.5 | 為接收核心提供 asyncore 相容事件迴圈 | 隨 App 附帶；PSF License v2，完整聲明以原檔為準 |
| [pyasynchat](https://github.com/simonrob/pyasynchat) | 1.0.5 | 為接收核心提供 asynchat 非同步通訊相容層，依賴 pyasyncore | 隨 App 附帶；PSF License v2，完整聲明以原檔為準 |
| Python | Homebrew 3.13 或 3.14 | 執行接收核心；sqlite3、json 等使用標準函式庫 | 使用者另外安裝，未內嵌 |
| Apple 系統框架 | macOS 27 SDK／執行系統 | SwiftUI、AppKit、Combine、Foundation、ServiceManagement、SystemConfiguration | 由 Apple SDK 與 macOS 提供，非 pip 套件 |

Python 套件版本固定於 `requirements.txt`，實際使用的副本在 `Receiver/vendor`。App 透過 bootstrap 優先載入這份副本，**只修改 requirements.txt 或升級電腦上的 pip 套件不會更新 App 內的接收核心**。維護時必須同步套件版本、副本及授權資料，重新測試與打包。

完整相依關係、更新與回復步驟見 [套件維護指南](docs/DEPENDENCIES.md)；原始授權見 [第三方聲明](THIRD_PARTY_NOTICES.md)。

## 安裝與第一次掃描

1. 取得 ScanInbox App，或依下方步驟從原始碼建置，放到固定的應用程式位置後開啟。
2. 按工具列「＋」，填寫印表機 IP、方便辨識的別名，並選擇掃描輸出資料夾。
3. 開啟「共用設定」，查看 App 自動偵測的 Mac 網路位址及接收連接埠，預設為 TCP 4687。不需要手動輸入 Mac IP。
4. 在印表機建立一筆指向 Mac 的掃描目的地，填入可連通的 Mac 位址與相同連接埠。若使用一般 FTP，接收方式為匿名 FTP；若使用「桌面」，請依該機型介面設定相容的目的地。本 App 不會自動建立或改寫印表機通訊錄。
5. 回到 App 按「開始接收服務」，確認顯示「接收服務運作中」，再從印表機面板選擇剛設定的目的地掃描。
6. 在掃描紀錄確認結果，並開啟輸出文件檢查頁數與內容。

首次啟動不會內建任何印表機或個人網路位址。macOS 若要求區域網路或所選資料夾權限，須允許 App 才能正常接收。

### 印表機目的地設定

| 設定 | 填寫方式 |
|---|---|
| 接收主機 | 共用設定列出的、印表機可連通的其中一個 Mac IPv4 位址 |
| 接收埠 | 與 App 相同，預設 4687 |
| 登入 | 匿名 FTP；若介面要求帳號，可填 anonymous |
| 處理目錄 | 留空或根目錄；需要子目錄時須先建立 |
| SSL／TLS | 本版使用一般 FTP，不啟用 TLS |

一般 FTP 與「桌面」目的地的欄位與註冊方式可能因機型而不同。目前支援範圍限定為 SHARP 事務機；作者已回報新、舊機種均能正常接收，已知測試機型包含 BP-70C55。這不代表所有 SHARP 機型皆已驗證，其他品牌目前尚未提供支援。

## 日常使用

| 操作 | 結果 |
|---|---|
| 切換左側印表機 | 顯示該台設定、狀態與紀錄 |
| 全部掃描紀錄 | 顯示所有印表機的結果 |
| 單台暫停／啟用 | 調整該台能否上傳 |
| 停止接收服務 | 暫停全部來源，保留設定 |
| 關閉最後一個 App 視窗 | 隱藏 Dock 圖示，保留選單列與背景接收 |
| 移除印表機 | 只移除設定，不刪除已掃描文件與歷史紀錄 |
| 在 Finder 中顯示 | 定位已成功接收、仍存在的檔案 |

App 有開啟視窗時會顯示 Dock 圖示，可用 Command+Tab 切回；縮小視窗仍保留此能力。關閉最後一個視窗後隱藏 Dock 圖示，可從選單列重新開啟管理視窗。

「待命」表示接收端已準備好，不代表印表機在線。傳輸中會暫時禁止套用需要重啟的設定；儲存按鈕也會在資料未變更或輸入不完整時停用。

共用設定可調整登入啟動、自動接收、接收埠、紀錄保留期間與診斷記錄。Mac 休眠、登出或 App 結束時無法接收。詳細網路與錯誤排查見 [操作說明](docs/USAGE.md)。

## 從原始碼建置

在專案根目錄執行：

```sh
zsh build.command
open dist/ScanInbox.app
```

App 產出於 `dist/ScanInbox.app`。預設建置供本機執行，不需要登入 Apple 帳號；要簽署並打包提供他人下載，請依 [簽署與發佈指南](docs/RELEASING.md) 操作。

測試：

```sh
/opt/homebrew/bin/python3.13 -m unittest discover -s Tests -v
```

## 專案結構

| 位置 | 用途 |
|---|---|
| Sources/ScanInbox | SwiftUI 介面、設定、網卡偵測與接收程序管理 |
| Receiver/receiver.py | FTP 接收、依來源分流、檔案限制及掃描紀錄 |
| Receiver/bootstrap.py | 隔離載入隨附的 Python 套件，禁止在 App 內寫入快取 |
| Receiver/vendor | 固定版本第三方套件及原始授權 |
| Assets/AppIcon.png | App 圖示原始圖，建置時自動產生各尺寸與 ICNS |
| Scripts/build.py | 編譯及簽署 App |
| Scripts/release.py | 建立發佈 ZIP，可選擇提交 Apple 公證 |
| Tests | 本機接收與發佈工具測試 |
| config/*.example.json | 可公開的設定格式範例，不含個人設定 |
| AGENTS.md | 給開發者與 Agent 的修改及驗證規則 |

使用者設定與紀錄存於 `~/Library/Application Support/SharpScanner/`，不放在程式碼內；各台掃描文件存於使用者選擇的資料夾。發佈者自己的設定放在 `config/release.local.json`，已加入 `.gitignore`。

## 名稱與設定相容性

App、執行檔及開發目錄統一使用 ScanInbox（`Sources/ScanInbox`）。為保留既有使用者資料，Bundle ID `tw.local.SharpScanner`、Application Support 資料夾與登入排程識別碼沿用相容性名稱，不需重新新增印表機或搬移紀錄。這些識別碼不代表產品名稱；專案根目錄也可依需要自行命名。

## 授權與商標

原創程式碼及文件採 [ScanInbox 個人非商業使用授權](LICENSE)。這不是 MIT 授權，亦不宣稱為符合 OSI 定義的開放原始碼授權；允許的個人使用、修改及免費分享方式，以授權全文為準。

SHARP、Sharp 名稱及相關商標屬 Sharp Corporation 及／或其關係企業或其他合法權利人所有。本專案僅為辨識相容設備而提及這些名稱，非 SHARP 官方產品，未獲其認證、贊助或背書。完整聲明及第三方套件授權見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
