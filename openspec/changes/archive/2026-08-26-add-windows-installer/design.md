## Context

本 repo 為 earendil-works/pi 的 fork（f97214/mypi），尚未發佈任何 GitHub Release。上游的 curl 安裝器（install.sh，託管於 pi.dev）只支援 Linux/macOS；Windows 使用者目前只能透過 npm 全域安裝。scripts/build-binaries.sh 已能在本機產出 pi-windows-x64.zip（內容在 zip 根層：pi.exe、theme/、assets/、node_modules/、native/ 等 runtime assets）與解壓後的 windows-x64/ 目錄，但不產生 checksum 檔；.github/workflows/build-binaries.yml 在 push tag 時會產生 release assets（含 SHA256SUMS）。目標使用者環境多為 Windows PowerShell 5.1（非 pwsh 7）。

## Goals / Non-Goals

**Goals:**

- 提供單一 scripts/install.ps1，同時支援參數模式（自動化）與互動選單模式（人工）
- 支援三種安裝來源：GitHub Releases（最新／指定版本）、本機 zip、本機目錄
- 遠端來源做 SHA256 驗證；所有來源驗證內容含 pi.exe
- 安裝後自動將 InstallDir 加入使用者 PATH（可跳過）
- 文件補齊 Quick Start 與 Windows 安裝路徑

**Non-Goals:**

- 不修改 build-binaries.sh 或 build-binaries.yml
- 不做 -Uninstall、不偵測 npm/pnpm/yarn/bun 安裝
- 不改動上游 install.sh 的內容或託管

## Decisions

### 參數與互動共用同一條解析管線

參數（-Version/-LocalPath/-InstallDir）先解析成「安裝計畫」（來源型別＋位置＋版本）；互動選單只是另一個產生安裝計畫的輸入方式。兩者收斂到同一組函式（Resolve-Source、Install-Content、Set-UserPath）。理由：避免兩套流程行為漂移；規格中的每個場景只需驗證一份實作。替代方案（互動與參數各自獨立流程）被否決，因為重複邏輯會讓錯誤處理不一致。

### 本機來源以「zip 或目錄」二擇一辨識

-LocalPath 以副檔名 .zip 判定為壓縮檔，否則視為目錄並檢查其下有 pi.exe。zip 解壓後同樣驗證 InstallDir 內有 pi.exe 才算成功（zip 可能損毀或缺檔）。理由：build-binaries.sh 只會產出這兩種形態，不需更通用的探測。路徑無效時錯誤訊息附上建置指令 scripts/build-binaries.sh --platform windows-x64。

### SHA256 驗證僅用於遠端來源

遠端模式下載 pi-windows-<arch>.zip 與同名 release asset 的 SHA256SUMS，以 Get-FileHash 計算後比對對應條目；不符即刪除下載檔並中止，不寫入 InstallDir。本機來源自建自用，且 build-binaries.sh 不產 checksum，故跳過雜湊驗證（規格已明定）。架構偵測以 $env:PROCESSOR_ARCHITECTURE（AMD64→x64、ARM64→arm64），不支援的架構直接報錯。

### 版本解析走 GitHub API，asset 下載走 releases/download 固定 URL

最新版號以 GET https://api.github.com/repos/f97214/mypi/releases/latest 的 tag_name 取得（去掉開頭 v）；zip 與 SHA256SUMS 自 https://github.com/f97214/mypi/releases/download/v<version>/ 下載。API 回應 404 或缺 Windows asset 時，錯誤訊息說明 fork 尚未有可用 release assets，並指向 npm 與本機安裝。替代方案（全走 API 取 asset 清單）較複雜且無額外好處。

### PATH 寫入採 User 範圍且冪等

讀取 [Environment]::GetEnvironmentVariable('Path','User')，若已包含 InstallDir 則完全不寫入；否則附加一筆並以 SetEnvironmentVariable('Path',…,'User') 寫回。-NoPath 時完全不讀不寫。寫入後印出「新開殼層生效」提示，因目前程序與已開啟的殼層不會自動更新。

### PowerShell 5.1 相容性約束

全程使用 Windows PowerShell 5.1 可用的 API：Expand-Archive（5.0+）、Get-FileHash、Invoke-WebRequest、[Environment] 方法；不用 pwsh 7 專屬語法（如 ?? 運算子、Join-String）。TLS 設定在腳本開頭指定 [Net.SecurityProtocolType]::Tls12，避免 5.1 預設協定過舊導致 GitHub 下載失敗。

### PowerShell 原生建置流程

互動選單新增選項 [5]「從本機原始碼建置並安裝」，由 install.ps1 內的 Build-FromSource 直接以 PowerShell 執行建置，不呼叫 build-binaries.sh（其依賴 bash 與 zip/unzip，Git Bash 通常缺 zip）。流程：前置檢查（node、npm、bun 經 Get-Command，缺一即報錯並附安裝提示，bun 指向 bun.sh）→ repo 根目錄解析（腳本位於 repo 內時以 PSScriptRoot 的上一層為預設，驗證根層 package.json 與 packages/coding-agent/ 存在，否則提示輸入並循環驗證）→ node_modules 缺失時執行 npm ci --ignore-scripts → npm run build:offline（使用 repo 已提交的 model 資料，不需網路）→ 在 packages/coding-agent 執行 bun build --compile --no-compile-autoload-bunfig --target bun-windows-<arch>（x64 加 -baseline baseline 後綴）產出 pi.exe 到 binaries/windows-<arch>/ → stage runtime assets（package.json、README.md、CHANGELOG.md、photon wasm、theme/、assets/、dist/core/export-html、docs、examples、@mariozechner/clipboard 含 win32 native .node、tui 的 win32-console-mode.node），布局與 build-binaries.sh 的 windows 輸出一致 → 建置完成後直接以現有 Install-FromDirectory 安裝該目錄，不再追問來源路徑。本機 Windows 機器建 Windows 產物時，npm ci 的 optional deps 已含當前平台 native sidecar，省略 build-binaries.sh 的跨平台 native deps 安裝步驟。替代方案（呼叫 build-binaries.sh）被否決：Windows 相容性脆弱。Trade-off：staging 邏輯與 build-binaries.sh 重複，可能隨上游漂移——以 staging 布局測試與此決策紀錄作為緩解，上游變更 staging 內容時需同步。

### 右鍵選單註冊走 HKCU per-user

「用 MYPI 開啟」寫入 HKCU\Software\Classes\Directory\shell\mypi（右鍵資料夾，目錄參數 %1）與 HKCU\Software\Classes\Directory\Background\shell\mypi（資料夾內空白處，參數 %V），不需管理員權限。指令樣板："<shell> -NoLogo -NoExit -Command "Set-Location -LiteralPath '<目錄>'; & '<InstallDir>\pi.exe'"，shell 於註冊當下偵測：pwsh.exe（Get-Command，PowerShell 7）優先，否則 System32 的 Windows PowerShell powershell.exe；路徑 bake 進登錄檔，使用者搬移安裝目錄後需重新註冊。登錄檔讀寫函式以可注入的根路徑（預設 HKCU:\Software\Classes）設計，測試可指向暫存機碼。替代方案（HKLM 全機註冊）被否決：需管理員權限且影響其他使用者。已知限制：Windows 11 新版右鍵選單需 MSIX 封裝與 IExplorerCommand COM 實作，超出範圍，本項目出現在傳統選單（「顯示更多選項」/Shift+F10），註冊成功訊息會附此說明。參數模式以 -ContextMenu opt-in、-RemoveContextMenu 移除（兩者互斥）；互動模式於安裝成功後追問，Enter 預設註冊。

## Implementation Contract

- Behavior: 使用者在 Windows 上執行 scripts/install.ps1 後，於 %LOCALAPPDATA%\Programs\pi 得到完整可執行的 pi 安裝（pi.exe 加 runtime assets），並可在新殼層直接執行 pi。
- Interface:
  - 參數：-Version <string>、-LocalPath <path>、-InstallDir <path>（預設 $env:LOCALAPPDATA\Programs\pi）、-NoPath（switch）、-ContextMenu（switch，註冊右鍵選單）、-RemoveContextMenu（switch，移除右鍵選單）
  - 退出碼：成功 0；參數衝突、來源不存在、雜湊不符、缺 pi.exe、PATH 寫入失敗均為非零，並輸出中文錯誤訊息
  - 成功輸出結尾固定包含：安裝目錄、如何開始（cd 到專案目錄執行 pi）、如何認證（/login 或 API key 環境變數）；註冊右鍵選單時附 Win11 傳統選單說明
- Failure modes: 所有失敗都必須在寫入 InstallDir 或 PATH 之前發生（fail-fast 驗證順序：參數 → 來源存在性 → 內容驗證 → 下載與雜湊）；唯一例外是 zip 在解壓途中失敗，此時須清除已解壓的部分內容再報錯。安裝前若 InstallDir 已存在舊版內容，直接覆蓋同名檔案，不做版本備份。建置來源（ingest 新增）：node/npm/bun 缺失、repo 結構無效、npm/bun 建置失敗時，皆在安裝步驟前以非零退出並附工具安裝提示；建置產物輸出到 repo 內 packages/coding-agent/binaries/windows-<arch>/，不寫入 InstallDir。
- Acceptance criteria:
  - 以 parser 檢查 install.ps1 語法（PowerShell 解析無錯）
  - 臨時目錄實測：-LocalPath 吃 zip、吃目錄皆成功且 InstallDir 出現 pi.exe；空目錄回報建置指令錯誤；-Version 與 -LocalPath 同給時非零退出
  - -NoPath 時使用者 PATH 讀值前後不變
  - 文件中出現的一行安裝指令與參數說明和實際腳本一致
  - 建置來源（ingest 新增）：假 repo 結構實測路徑驗證與缺 bun 錯誤；假 dist 結構實測 staging 布局；在本 repo 實機執行一次完整建置並安裝，確認 pi.exe 可啟動
- Scope boundaries:
  - In scope: scripts/install.ps1 新增；README.md、packages/coding-agent/docs/quickstart.md、packages/coding-agent/docs/index.md、packages/coding-agent/README.md 的安裝相關段落修訂；install.ps1 內的 PowerShell 原生建置流程（選單選項 [5]）；「用 MYPI 開啟」右鍵選單的 HKCU 註冊與移除
  - Out of scope: 建 CI workflow 變更、上游文件同步回饋（PR 到 earendil-works/pi）、npm 安裝流程本身、修改 build-binaries.sh、跨平台（非 Windows）建置、Windows 11 新版右鍵選單（MSIX/IExplorerCommand）、HKLM 全機註冊

## Risks / Trade-offs

- [fork 尚無 Release，遠端模式現階段不可測] → 錯誤訊息明確指向 npm 與本機安裝；待首次 push tag 觸發 build-binaries.yml 後以真實 assets 驗證
- [PowerShell 執行原則可能阻擋腳本] → 文件提供 irm … | iex 一行指令（不受 ExecutionPolicy 影響下載的遠端內容），本機檔案執行則附 -ExecutionPolicy Bypass 說明
- [使用者 PATH 很長，寫回有截斷風險] → SetEnvironmentVariable 寫 User 範圍字串上限約 32K，超限時報錯而非靜默截斷；不使用 setx（1024 字元截斷）
- [GitHub API 未認證請求速率限制] → 僅在需要「最新版號」時打一次 API；指定 -Version 時完全不打 API
