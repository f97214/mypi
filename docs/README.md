# 文件索引

本目錄是 repository 層級的協作與工程文件。**產品與使用者文件不在這裡**——那些在 `packages/coding-agent/docs/`（有自己的 `docs.json` 與 `index.md`）與各套件的 `README.md`。

## 本目錄

| 文件 | 內容 | 什麼時候讀 |
|---|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 套件相依方向、分層職責、資料流、外部邊界、建置與型別約束 | 動到架構、分層或新增模組之前 |
| [FEATURES.md](FEATURES.md) | 有證據的能力清單與狀態，含明確的「刻意不做」 | 判斷某個能力是否已存在、是否被刻意排除 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | 先決條件、安裝、建置、`npm run check` 的內容、相依與 lockfile 紀律、環境變數鍵名、風格硬約束 | 設定環境、改相依、要 commit 之前 |
| [TESTING.md](TESTING.md) | 各套件的測試框架與位置、`./test.sh`、單檔執行方式、coding-agent 測試慣例、Spectra TDD 證據流程 | 動測試之前 |

## repository 根目錄

| 檔案 | 內容 |
|---|---|
| [`../README.md`](../README.md) | 專案門面、套件清單、快速開始 |
| [`../AGENTS.md`](../AGENTS.md) | 跨 AI 工具的協作規範單一事實來源（上游維護） |
| [`../CLAUDE.md`](../CLAUDE.md) | Claude Code 薄入口，以 `@AGENTS.md` 匯入共同規範 |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | 貢獻流程與 contributor gate |
| [`../SECURITY.md`](../SECURITY.md) | 安全回報 |

## 各套件文件

`packages/*/README.md` 是各套件的 API 與使用說明。篇幅較大的：`packages/ai/README.md`、`packages/tui/README.md`、`packages/coding-agent/README.md`、`packages/agent/README.md`、`packages/telemetry/README.md`。

`packages/coding-agent/docs/` 另有完整的使用者文件站（quickstart、settings、skills、extensions、themes、sessions、rpc、sdk、providers、models、environment-variables、containerization、security、windows、termux、tmux 等）。

## 尚未存在

以下在本 repository **不存在**，本次 bootstrap 也不建立空殼：

- `docs/adr/` 與 `docs/adr/README.md` — 架構決策紀錄。`.claude/rules/adr.md` 已就位，等第一份 ADR 出現才生效。
- `CONTEXT.md` — 專案詞彙表。`.claude/rules/glossary.md` 已就位，等詞彙表出現才生效。
