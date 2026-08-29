<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

# CLAUDE.md

@AGENTS.md

## 專案概述

Pi Agent Harness（本 checkout 是 fork `f97214/mypi`）— Node.js `>=22.19.0` 的 TypeScript npm workspaces monorepo，`packages/` 下 10 個套件共用單一 lockfile、單一 `tsconfig.base.json` 與單一 `biome.json`。核心產物是可自我擴充的終端 coding agent CLI（`@earendil-works/pi-coding-agent`）。

選定目標：repository 根目錄（整個 workspace，不是單一套件）

## 常用指令

| 指令 | 用途 |
|---|---|
| `npm install --ignore-scripts` | 安裝相依，不跑 lifecycle script |
| `npm run check` | biome 格式／lint、`tsgo --noEmit` 型別檢查、pinned deps／shrinkwrap／import 檢查 |
| `./test.sh` | 在隔離 HOME 與空白環境變數下跑測試，沒有 API key 時會跳過依賴 LLM 的測試 |
| `./pi-test.sh` | 從原始碼直接跑 pi，可在任何目錄執行 |
| `npm run build` | 依相依順序建置全部套件（會先更新 model 資料） |
| `npm run build:offline` | 用既有 model 資料重建，不連網 |
| `npm run eval -- --provider <p> --model <m>` | 跑 `packages/evals` 的行為評測 |

`npm run check` 必須看完整輸出，不要 tail。它不跑測試。

**不要**在未經使用者要求時執行 `npm run build` 或 `npm test`。**不要**直接跑完整 vitest suite——當 endpoint／auth 環境變數存在時它會啟動 e2e 測試。

來源：`package.json` scripts、`README.md`「Development」、`AGENTS.md`「Commands」、`test.sh`。

## Claude Code 專屬規則

- 跨工具共同規範已由上方 `@AGENTS.md` 匯入，避免雙寫漂移。本 repository 的 `AGENTS.md` 由上游維護，內容優先於本檔。
- `.claude/` 版本控制策略：**個人忽略**。`.gitignore` 已忽略 `.claude/`（第 22 行，上游設定），本次 bootstrap 另以 managed block 一併忽略 `/.agents/`、`/.codex/`、`/.ai/`。這些目錄屬個人環境，不隨 repository 分發，也不要在 commit 中夾帶。
- 這是 fork。新增的 tracked 檔案在跟上游同步時都要一起處理；動到上游既有檔案（`AGENTS.md`、`README.md`、`.gitignore`、`package.json`）之前先確認是否真的必要。
- 禁止未經授權建立、切換或刪除 Git 分支與 worktree。
- 不讀取或輸出 `.env`、credentials、私鑰與 token 真值。本 repository 沒有 `.env.example`；環境變數清單見 `docs/DEVELOPMENT.md`。
- CLI 與一般文字檔使用 UTF-8；遇到亂碼先修正 console encoding。
- 同一個 cwd 可能有多個 pi／agent session 同時在跑。只 commit 自己這次改的檔案，用明確路徑 `git add <path>`，絕不 `git add -A` 或 `git add .`。

## 詳細文件

- @README.md — 專案門面與快速開始
- @AGENTS.md — 跨工具協作規範與專案慣例
- @docs/README.md — 文件索引
- @docs/ARCHITECTURE.md — 架構、元件與資料流
- @docs/FEATURES.md — 已確認功能與狀態
- @docs/DEVELOPMENT.md — 開發環境與規範
- @docs/TESTING.md — 測試位置、命令與限制

## 來源

- `package.json`（workspaces、scripts、engines、devDependencies）
- `AGENTS.md`（Conversational Style、Code Quality、Commands、Dependency and Install Security、Git）
- `README.md`（套件清單、Development、Permissions & Containerization）
- `.gitignore`、`biome.json`、`tsconfig.base.json`、`vitest.base.ts`、`test.sh`
- `.husky/pre-commit`、`.github/workflows/ci.yml`
- `git remote -v`（origin = `https://github.com/f97214/mypi.git`）
