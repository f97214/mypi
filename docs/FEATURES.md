# 功能

只列已在 repository 中找到證據的能力。狀態欄取自套件自述或明確標記，沒有明確標記的以「一般」表示；沒有證據的推測不寫入本檔。

## 目錄

- [Coding agent CLI](#coding-agent-cli)
- [LLM 抽象層](#llm-抽象層)
- [Agent runtime](#agent-runtime)
- [終端 UI](#終端-ui)
- [遠端 session](#遠端-session)
- [持久化與搜尋](#持久化與搜尋)
- [Telemetry](#telemetry)
- [評測](#評測)
- [明確的非功能](#明確的非功能)
- [未確認](#未確認)

## Coding agent CLI

`@earendil-works/pi-coding-agent`。

| 能力 | 狀態 | 說明 |
|---|---|---|
| 四種執行形態 | 一般 | 互動模式、print／JSON 模式、供程序整合的 RPC 模式、嵌入用 SDK。 |
| 互動編輯器 | 一般 | 內建 editor、指令、鍵盤快速鍵、訊息佇列。 |
| Session 管理 | 一般 | 管理、分支（branching）、compaction。 |
| Extensions | 一般 | TypeScript 撰寫的擴充點，用來改變行為而不必 fork 內部程式碼。 |
| Skills | 一般 | 自訂技能。 |
| Prompt Templates | 一般 | 自訂提示樣板。 |
| Themes | 一般 | 主題切換與匯出。 |
| Pi Packages | 一般 | 把 extension／skill／prompt template／theme 打包，經 npm 或 git 分享。 |
| Project Trust | 一般 | 專案信任機制。 |
| Context Files 與 system prompt | 一般 | 專案脈絡檔與系統提示組裝。 |
| Telemetry 與更新檢查 | 一般 | 可設定。 |
| Package 指令 | 一般 | CLI 內建的套件安裝與管理指令。 |
| 容器化指引 | 一般 | Gondolin extension（把工具與 `!` 命令導進本機 Linux micro-VM，pi 與供應商認證留在 host）、純 Docker、OpenShell 三種模式，見 `packages/coding-agent/docs/containerization.md`。 |

來源：`packages/coding-agent/README.md`（Interactive Mode、Sessions、Customization、Extensions、Pi Packages、Programmatic Usage、CLI Reference）、`packages/coding-agent/src/modes/`、`README.md`「Permissions & Containerization」。

## LLM 抽象層

`@earendil-works/pi-ai`。

| 能力 | 狀態 | 說明 |
|---|---|---|
| 多供應商統一 API | 一般 | Anthropic、OpenAI、Google GenAI、AWS Bedrock、Azure OpenAI Responses、Cloudflare gateway、GitHub Copilot、Ant Ling 等，實作在 `src/api/` 與 `src/providers/`。 |
| 只收錄支援 tool calling 的模型 | 刻意限制 | 套件自述：這是 agentic workflow 的必要條件。 |
| Auth 解析 | 一般 | credential store、環境變數、OAuth（`src/auth/oauth/`）、request header 轉換。 |
| Tools | 一般 | 工具定義、tool call 處理、partial JSON 串流、參數驗證、constrained sampling。 |
| 圖片輸入與圖片生成 | 一般 | 圖片生成章節另有明列的限制。 |
| Thinking／Reasoning | 一般 | 統一介面（`streamSimple`／`completeSimple`）與供應商專屬選項並存，可串流 thinking 內容。 |
| Token 與成本追蹤 | 一般 | — |
| 跨供應商交接 | 一般 | session 進行到一半可換模型。 |
| Context 序列化 | 一般 | 簡單的 context 持久化。 |
| 中止與續接 | 一般 | abort 後可繼續。 |
| 自訂供應商 | 一般 | `createProvider()`、直接呼叫 API 實作、OpenAI 相容設定。 |
| 測試用 faux provider | 一般 | 不需要真實 API key。 |
| 瀏覽器使用與 tree shaking | 一般 | 套件自述有專章；根 `package.json` 有 `check:browser-smoke` 把關。 |
| 模型資料產生 | 一般 | `src/models.generated.ts` 為產生物，**不得直接編輯**；改 `scripts/generate-models.ts` 後重新產生。 |

來源：`packages/ai/README.md`、`packages/ai/src/api/`、`packages/ai/src/providers/`、`packages/ai/src/auth/`、`AGENTS.md`、根 `package.json`（`generate:models`、`check:browser-smoke`、`check:model-data`）。

## Agent runtime

`@earendil-works/pi-agent-core`。

有狀態的 agent：`prompt()`／`continue()` 事件序列、tool call 事件、steering 與 follow-up、自訂訊息型別、session 與 thinking 預算、proxy 使用、低階 API。harness 層另含 compaction、skills、system prompt、prompt template、reducer 與 telemetry 接點（`src/harness/`）。

來源：`packages/agent/README.md`、`packages/agent/src/harness/`。

## 終端 UI

`@earendil-works/pi-tui`。

可互換的 renderer（主畫面與 alternate-screen 共用 `TUI` 介面）、差分渲染（只更新變動的行或 viewport 列）、應用程式自有的捲動（滑鼠／觸控板／鍵盤）、CSI 2026 同步輸出、bracketed paste（超過 10 行的貼上會加標記）、主題、內建元件（Text、TruncatedText、Input、Editor、Markdown、Loader、SelectList、SettingsList、Spacer、Image、Box、Container、VStack、HStack、ScrollView）、Kitty／iTerm2 行內圖片、檔案路徑與 slash command 自動完成。

**鍵盤綁定是設定項不是硬編碼**：新增按鍵時要加進 `DEFAULT_EDITOR_KEYBINDINGS` 或 `DEFAULT_APP_KEYBINDINGS`，不得寫死 `matchesKey(keyData, "ctrl+x")` 之類的檢查。

來源：`packages/tui/README.md`、`AGENTS.md`「Code Quality」。

## 遠端 session

`@earendil-works/pi-protocol` + `@earendil-works/pi-client` + `@earendil-works/pi-server`。

| 能力 | 狀態 |
|---|---|
| CBOR 協定與 byte framing（協定版本 1） | 一般 |
| 任意分片／合併都能解的增量 decoder | 一般 |
| 一條連線掛多個 session、請求以 ID 相關聯 | 一般 |
| exclusive／shared 兩種 session 租約 | 一般 |
| `PiServer` 與 unix socket listener | **實驗性** — 套件自述可能變更或移除，API 與行為尚未穩定 |

**不自動重連**：斷線後要自行呼叫 `reconnect()`。**progress event 不是權威狀態**，只有 server snapshot 與成功回應的 snapshot 才是。

來源：`packages/protocol/README.md`、`packages/client/README.md`、`packages/server/README.md`。

## 持久化與搜尋

`@earendil-works/pi-session-backend-sqlite-node`：`node:sqlite` adapter、SQLite session repository、migration、materialized view、可選 FTS 搜尋。repository 惰性持有單一共用連線；search 是同一個資料庫上的獨立服務。FTS 表與 trigger 在第一次非空白搜尋時建立並做一次性 rebuild，之後由 trigger 維持同步。

刻意獨立成套件，讓 `pi-agent-core` 不必預設拉進 runtime builtin 或原生 SQLite 相依。

來源：`packages/session-backends/sqlite-node/README.md`、`packages/agent/README.md`「SQLite session backends」。

## Telemetry

`@earendil-works/pi-telemetry`：明確的 callback 式 `TelemetryContext`／`TelemetrySpan` 契約、共用的 `NOOP_TELEMETRY_CONTEXT`、`InMemoryTelemetryContext` 參考實作、可序列化的 schema 定義與推導型別、adapter 一致性測試。

**刻意不提供**：exporter、全域 current-span 狀態、對任何 telemetry backend 的相依。應用端自行接 OpenTelemetry、Sentry 或 log。

來源：`packages/telemetry/README.md`。

## 評測

`@earendil-works/pi-evals`：行為式、模型驅動的檢查。把真實 `AgentSession` 接到 `vitest-evals`，在隔離的暫存專案與 agent 目錄中執行，並附上原生 pi session artifact。用來比較提示、工具、skill、模型或其他 harness 設定的端到端行為。

執行方式：`npm run eval -- --provider <p> --model <m>`，或用 `PI_PROVIDER`／`PI_MODEL` 環境變數；provider 與 model 必須成對提供。額外參數會轉發給 vitest。

來源：`packages/evals/README.md`、根 `package.json` 的 `eval` script。

## 明確的非功能

這些是刻意不做，不是待辦：

- **沒有內建權限系統**。pi 不限制檔案系統、程序、網路或憑證存取，預設以啟動它的使用者與程序權限執行。需要邊界請容器化或沙箱化。
- **沒有 sub agent、沒有 plan mode**。專案立場是「你可以叫 pi 幫你做一個，或安裝第三方 pi package」。
- `pi-telemetry` 不含 exporter，也不含全域 current-span 狀態。
- `pi-ai` 不收錄不支援 tool calling 的模型。

來源：`README.md`「Permissions & Containerization」、`packages/coding-agent/README.md`、`packages/telemetry/README.md`、`packages/ai/README.md`。

## 未確認

- Bun 支援範圍：`packages/coding-agent/src/bun/` 與 `packages/ai/src/bun-oauth.ts` 存在，但 `package.json` 的 `engines` 只宣告 Node `>=22.19.0`，Bun 的支援程度與保證未見文件說明。
- `packages/coding-agent/binaries/` 被 `.gitignore` 排除，`.github/workflows/build-binaries.yml` 顯示有二進位發行流程，但其涵蓋平台與發行節奏未在 repository 文件中說明。
