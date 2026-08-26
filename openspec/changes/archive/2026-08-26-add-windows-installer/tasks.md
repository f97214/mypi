## 1. 安裝器骨架與參數模式

- [x] 1.1 在 scripts/install.ps1 實作 Dual-mode invocation 與「參數與互動共用同一條解析管線」決策：定義 -Version、-LocalPath、-InstallDir（預設 $env:LOCALAPPDATA\Programs\pi）、-NoPath 四個參數，將其解析為統一的「安裝計畫」結構；-Version 與 -LocalPath 同時給予時以非零退出碼輸出衝突參數名稱，且不做任何下載、複製或 PATH 變更。驗證：PowerShell parser 語法檢查通過，且以臨時呼叫實測參數互斥情境退出碼非零。
- [x] 1.2 落實 PowerShell 5.1 相容性約束：腳本開頭設定 [Net.SecurityProtocolType]::Tls12，僅使用 Windows PowerShell 5.1 可用的 API（Expand-Archive、Get-FileHash、Invoke-WebRequest、[Environment] 方法），不出現 pwsh 7 專屬語法。驗證：在 Windows PowerShell 5.1 下執行 parser 解析無錯誤。

## 2. 遠端安裝

- [x] 2.1 實作 Remote installation from GitHub Releases 與「版本解析走 GitHub API，asset 下載走 releases/download 固定 URL」決策：以 $env:PROCESSOR_ARCHITECTURE 偵測 x64/arm64 組出 pi-windows-<arch>.zip；最新版號經 GET api.github.com/repos/f97214/mypi/releases/latest 取得 tag_name（指定 -Version 時不打 API），asset 自 github.com/f97214/mypi/releases/download/v<version>/ 下載；遵循「SHA256 驗證僅用於遠端來源」決策——SHA256SUMS 驗證不符時刪除下載檔、非零退出、不寫入 InstallDir；release 或 Windows asset 不存在時輸出指向 npm 與本機安裝的錯誤。驗證：以假 zip 與偽造 SHA256SUMS 條目實測雜湊不符即中止且 InstallDir 無任何寫入（手動斷言）。

## 3. 本機安裝

- [x] 3.1 實作 Local installation from build output 與「本機來源以「zip 或目錄」二擇一辨識」決策：-LocalPath 以 .zip 副檔名分流——zip 解壓至 InstallDir 後驗證 pi.exe 存在、目錄先驗證其下有 pi.exe 再遞迴複製；內容缺 pi.exe 時錯誤訊息附上建置指令 scripts/build-binaries.sh --platform windows-x64；本機模式不做任何雜湊驗證。驗證：臨時目錄實測三情境——合法 zip 安裝後 InstallDir 出現 pi.exe、合法目錄遞迴複製成功、空目錄回報建置指令錯誤。

## 4. PATH 與完成輸出

- [x] 4.1 實作 User PATH registration 與「PATH 寫入採 User 範圍且冪等」決策：InstallDir 不在使用者 PATH 時附加一筆並以 SetEnvironmentVariable('Path',…,'User') 寫回，既有條目原樣保留；已存在時完全不寫入；-NoPath 時不讀不寫 PATH；寫入後印出新殼層生效提示。驗證：臨時使用者環境實測——新增情境 PATH 恰多一筆、重複執行讀值不變、-NoPath 執行前後讀值相同。
- [x] 4.2 實作 Post-install guidance：安裝成功時固定輸出安裝目錄、如何開始（cd 到專案目錄執行 pi）、如何認證（/login 或 API key 環境變數）。驗證：成功流程的輸出內容審查包含上述三項資訊。

## 5. 互動選單

- [x] 5.1 實作 Interactive menu flow：不帶參數時顯示四選項編號選單（最新 Release／指定版本／本機 zip／本機目錄），Enter 選最新版；本機來源追問路徑並在無效輸入時重新提示而非退出；最後顯示安裝目錄預設值供 Enter 確認。驗證：以模擬管線輸入逐一走過四個分支與無效路徑重問情境（手動斷言）。

## 6. 文件改善

- [x] 6.1 [P] 重整 packages/coding-agent/docs/quickstart.md 安裝動線：Uninstall 段落移至 Next steps 之前，Install 段新增 standalone binary 與 Windows 安裝器說明（含直接執行會出現互動選單的描述），使讀者由安裝到首次啟動的順序連續不中斷。驗證：通讀全文確認章節順序為 Install → Authenticate → First session → … → Uninstall，且 Windows 一行指令與 install.ps1 實際參數一致。
- [x] 6.2 [P] 在根目錄 README.md 新增 Quick Start 段落（置於套件列表之後）：npm 全域安裝一行指令、Windows 安裝器一行指令（irm … | iex）、連結 packages/coding-agent/docs/quickstart.md。驗證：內容審查確認段落存在且連結與指令可正確解析。
- [x] 6.3 [P] 更新 packages/coding-agent/docs/index.md 與 packages/coding-agent/README.md 的 Quick Start：在 curl 安裝器旁補上 Windows 一行安裝指令，並註明 fork 首次 push tag 觸發 build-binaries.yml 前，遠端安裝不可用、屆時改走 npm 或本機安裝。驗證：內容審查確認兩處文字一致且免責說明存在。
- [x] 6.4 核對所有文件中的安裝指令與 scripts/install.ps1 行為一致：一行指令 URL、參數名稱（-Version/-LocalPath/-InstallDir/-NoPath）、預設安裝目錄 %LOCALAPPDATA%\Programs\pi 皆與實作相符。驗證：逐條比對文件指令與腳本參數定義（manual assertion）。

## 7. 從原始碼建置並安裝（ingest 新增）

- [x] 7.1 在 scripts/install.ps1 實作 Build from source 需求的 Build-FromSource 前置檢查與 repo 驗證：以 Get-Command 檢查 node、npm、bun，缺一即以非零退出並輸出錯誤訊息指名缺的工具與安裝提示（bun 指向 bun.sh）；repo 根目錄解析——腳本位於 repo 內時預設為 PSScriptRoot 上一層，驗證根層 package.json 與 packages/coding-agent/ 存在，無效時重新提示而非退出。驗證：以假 repo 目錄結構與隔離的 PATH 實測缺 bun 錯誤與無效路徑重問（manual assertion）。
- [x] 7.2 落實「PowerShell 原生建置流程」決策的建置步驟：node_modules 不存在時於 repo 根目錄執行 npm ci --ignore-scripts，接著 npm run build:offline，再於 packages/coding-agent 執行 bun build --compile --no-compile-autoload-bunfig --target bun-windows-<arch>（x64 加 -baseline）將 ./dist/bun/cli.js 與 ./src/utils/image-resize-worker.ts 編譯為 binaries/windows-<arch>/pi.exe；建置前印出需時警告。驗證：在本 repo 實機執行一次完整建置，確認 pi.exe 產出（manual assertion）。
- [x] 7.3 實作 staging：將 package.json、README.md、CHANGELOG.md、node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm、dist/modes/interactive/theme/*.json、dist/modes/interactive/assets/、dist/core/export-html、docs、examples、node_modules/@mariozechner/clipboard（含 clipboard.win32-<arch>-msvc.node）、packages/tui/native/win32/prebuilds/win32-<arch>/win32-console-mode.node 複製到 binaries/windows-<arch>/，布局與 build-binaries.sh 的 windows 輸出一致；staging 前清空既有輸出目錄但保留 bun 剛編譯出的 pi.exe。驗證：以假 dist 與假 node_modules 結構實測 staging 後的檔案布局（manual assertion）。
- [x] 7.4 在互動選單新增「[5] 從本機原始碼建置並安裝」：追問 repo 路徑（repo 內執行時 Enter 帶入預設值）、印出建置時間警告、執行 Build-FromSource，成功後自動以 Install-FromDirectory 安裝 binaries/windows-<arch>/，不重複追問來源路徑。驗證：以管線輸入走 [5] 分支搭配假 repo 與假工具鏈（manual assertion）。
- [x] 7.5 擴充暫存測試 harness 涵蓋 7.1 的前置檢查與路徑驗證、7.3 的 staging 布局、7.4 的選單分支，並確認既有 35 項斷言不退化。驗證：harness 執行結果 0 failed。
- [x] 7.6 [P] 更新 packages/coding-agent/docs/quickstart.md 的安裝器說明：互動選單選項補上「從本機原始碼建置並安裝」，並列出前置需求（Node.js、npm、bun）與產物位置 packages/coding-agent/binaries/。驗證：內容審查與 install.ps1 實際選單選項一致。

## 8. 右鍵選單「用 MYPI 開啟」（ingest 新增）

- [x] 8.1 在 scripts/install.ps1 實作 Context menu integration 需求、落實「右鍵選單註冊走 HKCU per-user」決策的登錄檔函式：Set-ContextMenu（寫入 HKCU\Software\Classes\Directory\shell\mypi 與 Directory\Background\shell\mypi，含顯示名稱「用 MYPI 開啟」、Icon 指向 pi.exe、command 分別含 %1/%V 的 Set-Location 加 pi.exe 呼叫）與 Remove-ContextMenu（刪除兩個機碼，機碼不存在不報錯），根路徑以參數注入（預設 HKCU:\Software\Classes）以便測試。驗證：以暫存機碼路徑實測寫入的鍵值內容與移除後消失（manual assertion）。
- [x] 8.2 實作 PowerShell 偵測：Get-Command pwsh 優先取其 Source，否則使用 System32 的 Windows PowerShell powershell.exe；偵測結果 bake 進 command。驗證：在本機實測回傳 pwsh 路徑；以隔離環境模擬無 pwsh 時回傳 powershell.exe（manual assertion）。
- [x] 8.3 整合進安裝器：新增 -ContextMenu 與 -RemoveContextMenu 參數（互斥檢查，同給以非零退出指名衝突參數）；互動模式安裝成功後追問（Enter 預設註冊）；註冊成功訊息附 Win11「顯示更多選項」說明；-RemoveContextMenu 可單獨執行（不需安裝來源）。驗證：臨時呼叫實測參數互斥非零退出；管線輸入實測互動追問兩分支（manual assertion）。
- [x] 8.4 擴充測試 harness 涵蓋 8.1–8.3，並確認既有 56 項斷言不退化。驗證：harness 執行結果 0 failed。
- [x] 8.5 實機驗證：以 -ContextMenu 註冊至真實 HKCU，確認兩個機碼存在且 command 內容正確，再以 -RemoveContextMenu 移除並確認機碼消失。驗證：Get-ItemProperty 前後比對（manual assertion）。
- [x] 8.6 [P] 更新 packages/coding-agent/docs/quickstart.md：安裝器說明補右鍵選單功能（-ContextMenu 註冊、-RemoveContextMenu 移除、Win11 顯示更多選項限制）。驗證：內容審查與 install.ps1 實際參數一致。
