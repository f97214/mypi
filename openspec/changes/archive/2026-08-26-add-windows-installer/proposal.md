## Why

Pi 目前的安裝文件對 Windows 使用者不友善：curl 安裝器（install.sh）只支援 Linux/macOS，Windows 只能靠 npm 全域安裝；根目錄 README 沒有 Quick Start 段落，新手找不到安裝入口；quickstart.md 的 Uninstall 段落插在 Install 與首次啟動流程之間，打斷閱讀動線。此外，本 fork 尚未發佈任何 GitHub Release，文件也未說明如何用本機建置產物安裝。

## What Changes

- 新增 scripts/install.ps1：Windows 安裝器（PowerShell 5.1 相容），提供兩種使用模式：
  - 參數模式（適合自動化）：-Version、-LocalPath、-InstallDir、-NoPath；-Version 與 -LocalPath 互斥
  - 互動選單模式（不帶參數時）：可選擇從 GitHub Releases 安裝最新版／指定版本、從本機 zip 安裝、從本機目錄安裝，並確認安裝目錄
- 遠端安裝：偵測 CPU 架構（x64/arm64）、下載對應 pi-windows-*.zip 與 SHA256SUMS 並驗證雜湊後解壓
- 本機安裝：接受 build-binaries.sh 的產物格式（pi-windows-x64.zip 或解壓後的 windows-x64/ 目錄），驗證內含 pi.exe 後安裝；本機模式不做雜湊驗證
- 從原始碼建置並安裝（ingest 新增）：互動選單新增「[5] 從本機原始碼建置並安裝」——安裝器以 PowerShell 原生流程（npm ci → npm run build:offline → bun build --compile → stage runtime assets）在 repo 內建置 windows-<arch> 產物到 packages/coding-agent/binaries/，完成後自動安裝；不依賴 bash/zip，Windows 原生可跑
- 右鍵選單整合（ingest 新增）：安裝器可向 HKCU\Software\Classes 註冊「用 MYPI 開啟」右鍵選單（右鍵資料夾與資料夾內空白處），以機器上最新的 PowerShell（pwsh 7 優先，Windows PowerShell 備援）在該目錄開啟 pi；互動模式安裝後追問，參數模式提供 -ContextMenu 與 -RemoveContextMenu
- 兩種來源收斂到共用流程：驗證內容 → 解壓／複製到 InstallDir（預設 %LOCALAPPDATA%\Programs\pi）→ 加入使用者 PATH → 印出下一步提示
- 文件改善：
  - 根目錄 README.md 新增 Quick Start 段落（npm 安裝、Windows 一行指令、quickstart 連結）
  - packages/coding-agent/docs/quickstart.md：Uninstall 段移至文件尾端；Install 段新增 standalone binary 與 Windows 安裝器說明
  - packages/coding-agent/docs/index.md 與 packages/coding-agent/README.md 的 Quick Start 補上 Windows 一行安裝指令
  - 各文件註明：fork 首次 push tag 觸發 build-binaries.yml 產出 release assets 前，遠端安裝不可用，屆時走 npm 或本機安裝

## Non-Goals

- 不修改 build-binaries.sh 或 build-binaries.yml（已會產生 Windows assets 與 SHA256SUMS）
- 不新增 macOS/Linux 之外的安裝器變體，也不改動既有 install.sh 的內容或託管位置
- 不實作 -Uninstall 參數（解除安裝維持文件中現行的手動方式）
- 不處理 npm/pnpm/yarn/bun 等套件管理器的安裝路徑偵測

## Capabilities

### New Capabilities

- `windows-installer`: scripts/install.ps1 安裝器的行為規格——參數與互動雙模式、遠端下載與 SHA256 驗證、本機 zip／目錄安裝、從原始碼建置並安裝、「用 MYPI 開啟」右鍵選單註冊與移除、PATH 設定與錯誤處理

### Modified Capabilities

(none)

## Impact

- Affected specs: windows-installer（新能力）
- Affected code:
  - New: scripts/install.ps1
  - Modified: README.md, packages/coding-agent/docs/quickstart.md, packages/coding-agent/docs/index.md, packages/coding-agent/README.md
