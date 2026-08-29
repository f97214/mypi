# 開發

## 目錄

- [先決條件](#先決條件)
- [安裝](#安裝)
- [建置](#建置)
- [檢查](#檢查)
- [從原始碼執行](#從原始碼執行)
- [相依與 lockfile 紀律](#相依與-lockfile-紀律)
- [pre-commit 與 CI](#pre-commit-與-ci)
- [環境變數鍵名](#環境變數鍵名)
- [程式碼風格硬約束](#程式碼風格硬約束)
- [發行](#發行)
- [未確認](#未確認)

## 先決條件

- Node.js `>=22.19.0`（`package.json` 的 `engines`）。CI 使用 Node 22。
- npm（repository 使用 npm workspaces 與單一 `package-lock.json`）。
- CI 另外安裝的系統相依：`libcairo2-dev`、`libpango1.0-dev`、`libjpeg-dev`、`libgif-dev`、`librsvg2-dev`、`fd-find`、`ripgrep`。本機開發是否需要視你要跑到哪些功能而定。

來源：`package.json`、`.github/workflows/ci.yml`。

## 安裝

```bash
npm install --ignore-scripts    # 本機補水
npm ci --ignore-scripts         # 乾淨／CI 風格
```

**一律加 `--ignore-scripts`**，除非使用者明確要求跑 lifecycle script。

來源：`README.md`「Development」、`AGENTS.md`「Dependency and Install Security」、`.github/workflows/ci.yml`。

## 建置

```bash
npm run build          # 先更新 model 資料，再依相依順序建置全部套件
npm run build:offline  # 用既有 model 資料重建，不連網
```

建置順序寫死在根 `package.json` 的 `build` script：`tui → telemetry → ai → agent → session-backends/sqlite-node → protocol → client → server → coding-agent`。改動套件間相依關係時要同步改這個 script。

多數套件用 `tsgo -p tsconfig.build.json`；`packages/ai` 會先跑 `generate-models`；`packages/coding-agent` 會在 unbundled 建置後跑 `scripts/build-coding-agent-bundle.mjs`；`packages/session-backends/sqlite-node` 會複製 SQLite migration 到 dist。

**不要在未經使用者要求時執行 `npm run build`。**

來源：根 `package.json`、各套件 `package.json`、`AGENTS.md`「Commands」。

## 檢查

```bash
npm run check
```

它依序做這些事：

1. `biome check --write --error-on-warnings .` — 格式與 lint，**會直接改檔案**。
2. `npm run check:pinned-deps` — 直接外部相依必須鎖定精確版本。
3. `npm run check:ts-imports` — 相對 import 規則。
4. `npm run check:shrinkwrap` — `packages/coding-agent/npm-shrinkwrap.json` 是否需要重新產生。
5. `npm run check:install-lock:coding-agent` — install lock 檢查。
6. `tsgo --noEmit` — 全 workspace 型別檢查。
7. `npm run check:browser-smoke` — 瀏覽器可用性煙霧測試。

**改了程式碼（不含純文件）之後就要跑它，看完整輸出不要 tail，把 error、warning、info 全部修掉再 commit。它不跑測試。**

biome 設定：indent 為 tab、寬度 3、行寬 120，範圍是 `packages/*/src/**/*.ts`、`packages/*/test/**/*.ts`、`packages/session-backends/*/src/**/*.ts`。

來源：根 `package.json` 的 `check` script、`biome.json`、`AGENTS.md`「Commands」。

## 從原始碼執行

```bash
./pi-test.sh     # macOS / Linux / Git Bash，可從任何目錄執行
./pi-test.ps1    # PowerShell
./pi-test.bat    # cmd
```

來源：`README.md`「Development」、repository 根目錄的 `pi-test.*`。

## 相依與 lockfile 紀律

- npm 相依與 lockfile 變更視同**受審查的程式碼**。直接外部相依鎖定精確版本。
- 更新 `undici` 前**必須**讀該版本的 changelog／release note，評估是否影響功能。
- 相依 metadata 變更後用 `npm install --package-lock-only --ignore-scripts` 更新 `package-lock.json`。
- 需要重建 shrinkwrap 時跑 `node scripts/generate-coding-agent-shrinkwrap.mjs`（用 `--check` 或 `npm run check` 驗證）。新增帶 lifecycle script 的相依需要審查並在該腳本中明確加入 allowlist，不得默默加入。
- pre-commit 會擋下 lockfile 的 commit，除非設定 `PI_ALLOW_LOCKFILE_CHANGE=1`。除非使用者確實要 commit lockfile 變更，否則不要繞過。

來源：`AGENTS.md`「Dependency and Install Security」、`.husky/pre-commit`、`scripts/check-lockfile-commit.mjs`。

## pre-commit 與 CI

`.husky/pre-commit` 會：先跑 `node scripts/check-lockfile-commit.mjs`，再跑 `npm run check`；若 staged 檔案命中 `packages/ai/*`、`packages/web-ui/*`、`package.json`、`package-lock.json` 則追加 `npm run check:browser-smoke`；最後把先前 staged、可能被格式化改動過的檔案重新 `git add`。

CI（`.github/workflows/ci.yml`，push 到 `main` 與對 `main` 的 PR 觸發）：`npm ci --ignore-scripts` → `npm run build` → `npm run check` → `npm test`。

**注意**：`npm run check` 已經是 pre-commit 的一部分。要在其他地方（例如 session 收工閘門）再跑一次之前，先想清楚重複的成本。

其他 workflow：`build-binaries.yml`、`npm-audit.yml`、`pr-gate.yml`、`issue-gate.yml`、`issue-analysis.yml`、`issue-triage-labels.yml`、`approve-contributor.yml`、`publish-model-catalog.yml`、`remove-inprogress-on-close.yml`。

來源：`.husky/pre-commit`、`.github/workflows/`。

## 環境變數鍵名

repository **沒有** `.env.example` 或 `.env.sample`。`.gitignore` 忽略 `.env`。以下只列鍵名與用途，**不列值**；真值不得寫入任何文件、log 或 commit。

CLI 與程序識別：

| 鍵名 | 用途 |
|---|---|
| `AI_AGENT` | 由 CLI 與 RPC 進入點設為 `pi`，讓一般工具能歸因子程序 |
| `PI_CODING_AGENT` | 由 CLI 與 RPC 進入點設為 `true`，讓子程序偵測自己跑在 pi 內 |
| `PI_CODING_AGENT_DIR` | 覆寫設定目錄（預設 `~/.pi/agent`） |
| `PI_CODING_AGENT_SESSION_DIR` | 覆寫 session 儲存目錄（會被 `--session-dir` 覆蓋） |
| `PI_PACKAGE_DIR` | 覆寫套件目錄 |
| `PI_OFFLINE` | 關閉啟動時的網路操作（更新檢查、套件更新檢查、安裝／更新 telemetry） |
| `PI_SKIP_VERSION_CHECK` | 略過啟動時的版本檢查，不對 `pi.dev` 發請求 |
| `PI_TELEMETRY` | 覆寫安裝／更新 telemetry 與供應商歸因 header；不會關掉更新檢查 |
| `PI_CACHE_RETENTION` | 設為 `long` 啟用延長的 prompt cache |
| `VISUAL`、`EDITOR` | `externalEditor` 未設定時 Ctrl+G 的外部編輯器 |

由 `bash`／`powershell` 工具注入給命令的 session metadata：`PI_SESSION_ID`、`PI_SESSION_FILE`、`PI_PROVIDER`、`PI_MODEL`、`PI_REASONING_LEVEL`。

開發與測試相關：`PI_ALLOW_LOCKFILE_CHANGE`（允許 commit lockfile）、`PI_NO_LOCAL_LLM`（`test.sh` 設定）、`PI_EXPERIMENTAL`、`PI_TIMING`、`PI_STARTUP_BENCHMARK`、`PI_EVAL_ARTIFACT_DIR`、`PI_SESSION_SNAPSHOT_ARTIFACT`、`PI_BUNDLED_NODE`、`PI_HARDWARE_CURSOR`、`PI_CLEAR_ON_SHRINK`、`PI_TUI_WRITE_LOG`、`PI_TUI_ESC_TIMEOUT`、`PI_OAUTH_CALLBACK_HOST`、`PI_SHARE_VIEWER_URL`。

**祕密類鍵名**（只列名稱，取得方式請向專案維護者確認）：`PI_AUTH_JSON`、`PI_AUTH_UPDATE_TOKEN`、`PI_GIST_TOKEN`、`PI_ARTIFACTS_R2_ACCESS_KEY_ID`、`PI_ARTIFACTS_R2_SECRET_ACCESS_KEY`。供應商 API key 由 `packages/ai` 的 auth 解析層處理，完整清單見 `packages/ai/README.md`「Environment Variables」與 `packages/coding-agent/docs/environment-variables.md`。

來源：`packages/coding-agent/README.md`「Environment Variables」、`packages/coding-agent/docs/environment-variables.md`、`test.sh`、`.gitignore`、對 `packages/*/src`、`packages/*/scripts`、`scripts/`、`.github/workflows/` 的 `PI_[A-Z0-9_]+` 掃描。

## 程式碼風格硬約束

以下由 `AGENTS.md` 規定，`npm run check` 與 `tsconfig.base.json` 部分強制：

- 只用**可抹除**（erasable）的 TypeScript 語法：不得用 parameter property、`enum`、`namespace`／`module`、`import =`、`export =`。用明確欄位加建構子指派。
- **不得 inline import**：`await import()`、`import("pkg").Type`、動態型別 import 一律禁止，只允許 top-level import。
- 非必要不用 `any`。
- 只有一個呼叫點的單行 helper 直接內聯。
- 外部 API 型別去 `node_modules` 查，不要猜。
- 不得為了修掉舊版相依造成的型別錯誤而移除或降級程式碼；升級該相依。
- 不得寫死按鍵檢查（例如 `matchesKey(keyData, "ctrl+x")`），要加進 `DEFAULT_EDITOR_KEYBINDINGS` 或 `DEFAULT_APP_KEYBINDINGS`。
- 不得直接修改 `packages/ai/src/models.generated.ts`；改 `packages/ai/scripts/generate-models.ts` 後重新產生。
- 移除看起來是刻意存在的功能或程式碼前先問。
- 除非使用者要求，不保留向後相容。

來源：`AGENTS.md`「Code Quality」、`tsconfig.base.json`。

## 發行

版本與發行相關 script 都在根 `package.json`：`version:patch`／`minor`／`major`／`set`、`release:patch`／`minor`／`major`、`release:local`、`release:fix-links`、`publish`、`publish:dry`、`shrinkwrap:coding-agent`、`install-lock:coding-agent`、`check:model-catalog`、`diff:model-catalog`、`generate:model-catalog`、`hydrate:model-data`。

`prepublishOnly` 會跑 `clean` → `build` → `check`。

來源：根 `package.json`。

## 未確認

- 本機開發在 Windows 上需要哪些系統相依**未確認**：CI 的系統相依清單是 Ubuntu 專用（apt 套件）。`packages/coding-agent/docs/windows.md` 有 Windows 專章，但本 bootstrap 未逐字核對其內容。
- `packages/web-ui` 出現在 `.husky/pre-commit` 的 browser smoke 觸發條件中，但 `packages/` 底下**目前不存在**這個目錄；這條件可能是遺留或為未來預留。
