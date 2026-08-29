# 架構

本檔描述 repository 根目錄這一個 workspace 的元件、相依方向、資料流與外部邊界。每節末尾標示來源；沒有可引用來源的推論標示「未確認」。

## 目錄

- [系統定位](#系統定位)
- [套件與相依方向](#套件與相依方向)
- [分層職責](#分層職責)
- [資料流](#資料流)
- [外部邊界](#外部邊界)
- [建置與型別約束](#建置與型別約束)
- [未確認](#未確認)

## 系統定位

Pi 是一個終端 coding agent harness。它刻意不內建 sub agent 與 plan mode，而是把擴充點開放出來：使用者用 TypeScript Extensions、Skills、Prompt Templates 與 Themes 調整行為，並可打包成 Pi Package 透過 npm 或 git 分享，不需要 fork 內部程式碼。

Pi 有四種執行形態：互動模式、print／JSON 模式、供程序整合的 RPC 模式，以及嵌入自家應用的 SDK。

Pi **沒有內建權限系統**去限制檔案系統、程序、網路或憑證存取；預設以啟動它的使用者與程序權限執行。需要更強的邊界時要自行容器化或沙箱化。

來源：`packages/coding-agent/README.md`、`README.md`「Permissions & Containerization」、`packages/coding-agent/src/modes/`（`interactive`、`print-mode.ts`、`json-event.ts`、`rpc`）。

## 套件與相依方向

10 個 workspace 套件。箭頭是「相依於」，只列 `@earendil-works/*` 內部相依：

```
pi-telemetry        （無內部相依）
pi-tui              （無內部相依）
pi-protocol         （無內部相依）

pi-ai               → pi-telemetry
pi-agent-core       → pi-ai, pi-telemetry
pi-session-backend-sqlite-node → pi-ai, pi-agent-core
pi-client           → pi-protocol
pi-server           → pi-ai, pi-protocol
pi-coding-agent     → pi-agent-core, pi-ai, pi-client, pi-protocol, pi-tui
pi-evals            （無內部相依；透過 harness 驅動真實 AgentSession）
```

根 `package.json` 的 `build` script 以這個順序建置：`tui → telemetry → ai → agent → session-backends/sqlite-node → protocol → client → server → coding-agent`。順序即相依拓樸，改動相依關係時要同步改這個 script。

| 套件 | 職責 |
|---|---|
| `pi-telemetry` | 廠商中立的 telemetry 契約（`TelemetryContext`／`TelemetrySpan`）、no-op context、in-memory 參考實作、typed schema。不含 exporter，也不相依任何 telemetry backend。 |
| `pi-tui` | 差分渲染的終端 UI 框架：主畫面與 alternate-screen 兩種 renderer 共用 `TUI` 介面、CSI 2026 同步輸出、bracketed paste、內建元件、Kitty／iTerm2 行內圖片。 |
| `pi-protocol` | 遠端 session 的線路協定：CBOR 編碼、四位元組大端長度前綴的 byte framing、訊息 schema。`hello` 一定是 client 第一則訊息。 |
| `pi-ai` | 統一多供應商 LLM API：provider collection、auth 解析、token／成本追蹤、context 持久化與跨模型交接。只收錄支援 tool calling 的模型。 |
| `pi-agent-core` | 有狀態的 agent runtime：tool 執行、事件串流、session 狀態管理、compaction、skills、system prompt、prompt template。 |
| `pi-session-backend-sqlite-node` | `node:sqlite` adapter、SQLite session repository、migration、materialized view 與可選 FTS 搜尋。獨立成套件，讓核心不必預設拉進原生 SQLite 相依。 |
| `pi-client` | transport-neutral 的遠端 session client。只透過 `ByteTransport` 介面收送長度前綴 CBOR，無 Node 專屬 import。 |
| `pi-server` | **實驗性**。`PiServer` session server 與 unix socket listener。API 與行為尚未穩定，可能變更或移除。 |
| `pi-coding-agent` | 互動式 coding agent CLI，組合上述全部套件。 |
| `pi-evals` | 行為式、模型驅動的評測。把真實 `AgentSession` 接到 `vitest-evals`，在隔離的暫存專案與 agent 目錄中執行。 |

來源：各套件 `package.json` 的 `dependencies`／`peerDependencies`、各套件 `README.md`、根 `package.json` 的 `build` script。

## 分層職責

由下而上三層，加上兩條與主線平行的支線：

**基礎層**：`pi-telemetry`（觀測契約）、`pi-tui`（終端輸出）、`pi-protocol`（線路格式）。三者彼此不相依，也不相依上層。

**runtime 層**：`pi-ai` 把各家 LLM 差異收斂成單一 API；`pi-agent-core` 在其上加入 tool calling、狀態與事件串流。session 持久化由 `pi-session-backend-sqlite-node` 以可抽換的 backend 形式提供——repository 只擁有一條共用的資料庫連線，search 是同一個 canonical database 上的獨立服務，repository 不暴露 `search()`。

**應用層**：`pi-coding-agent` 是終端使用者面對的 CLI；它同時是 `pi-client`／`pi-protocol` 的消費者，因此可以連到遠端 session。

**遠端支線**：`pi-client` ⇄ `pi-protocol` ⇄ `pi-server`。session 與 server snapshot 是權威狀態；progress event 只是暫時性的 UI 提示，不得被歸納進權威狀態。

**評測支線**：`pi-evals` 不被任何套件相依，由 `npm run eval` 單獨驅動。

來源：`packages/*/README.md`、`packages/session-backends/sqlite-node/README.md`、`packages/protocol/README.md`、`packages/client/README.md`。

## 資料流

**互動模式**：終端輸入 → `pi-tui` 元件與 keybinding → `pi-coding-agent` 的 `AgentSession`（`src/core/agent-session.ts`、`agent-session-runtime.ts`）→ `pi-agent-core` 的 agent loop → `pi-ai` 的 provider API → 串流事件回流 → `pi-tui` 差分渲染只重畫變動的行或 viewport 列。

**工具執行**：agent loop 產生 tool call → `pi-agent-core` 的 tool 層執行 → coding agent 提供 read／bash／edit／write 等實作（`src/core/bash-executor.ts`、`src/core/exec.ts`）→ 結果回填進對話狀態。

**遠端 session**：`PiClient` 透過 `ByteTransport` 送出框架化 CBOR → `pi-server` 的 listener 收下 → 交給 `PiServerService` 實作 → 回傳 snapshot 與事件封包。請求以 ID 相關聯；`PiClient` 不會自動重連，斷線後要自行呼叫 `reconnect()`。一條連線可掛多個 session。session 取得（acquire）分 `exclusive` 與 `shared` 兩種租約，任一租約存在時 exclusive 取得會失敗。

**持久化**：session 條目寫進 SQLite canonical entries；FTS 表與 trigger 在第一次非空白搜尋時才惰性建立，建立當下做一次性 rebuild，之後由 SQLite trigger 維持同步。

來源：`packages/coding-agent/src/core/`、`packages/coding-agent/src/modes/`、`packages/agent/src/harness/`、`packages/client/README.md`、`packages/protocol/README.md`、`packages/session-backends/sqlite-node/README.md`。

## 外部邊界

| 邊界 | 位置 | 說明 |
|---|---|---|
| LLM 供應商 | `packages/ai/src/api/`、`packages/ai/src/providers/` | Anthropic、OpenAI、Google GenAI、AWS Bedrock、Azure OpenAI、Cloudflare gateway、GitHub Copilot 等。相依 `@anthropic-ai/sdk`、`openai`、`@google/genai`、`@aws-sdk/client-bedrock-runtime`。 |
| 憑證與 OAuth | `packages/ai/src/auth/`、`packages/coding-agent/src/core/auth-storage.ts` | credential store 與環境變數解析。**不要在任何情況下輸出真值。** |
| 終端 | `packages/tui/` | ProcessTerminal、CSI 2026、Kitty／iTerm2 圖形協定。 |
| 檔案系統與程序 | `packages/coding-agent/src/core/bash-executor.ts`、`exec.ts` | 以啟動者的權限執行，無內建限制。 |
| SQLite | `packages/session-backends/sqlite-node/` | `node:sqlite`。 |
| npm 與 git | `packages/coding-agent/src/package-manager-cli.ts`、`src/core/` 的 git 相關模組 | Pi Package 安裝與 session 的 git 操作。 |
| HTTP proxy | `http-proxy-agent`、`https-proxy-agent`（`pi-ai`） | 供應商請求可經 proxy。 |

模型資料是**產生**出來的：`packages/ai/src/models.generated.ts` 不得直接編輯，要改就改 `packages/ai/scripts/generate-models.ts` 再重新產生。

來源：`packages/ai/package.json`、`packages/ai/src/api/`、`AGENTS.md`「Code Quality」最後一條、`README.md`「Permissions & Containerization」。

## 建置與型別約束

- 全部套件共用 `tsconfig.base.json`：`target ES2022`、`module Node16`、`strict`、`erasableSyntaxOnly`、`allowImportingTsExtensions`、`rewriteRelativeImportExtensions`。
- `erasableSyntaxOnly` 是硬約束：`packages/*/src`、`packages/*/test`、`packages/coding-agent/examples` 只能使用 Node strip-only 模式可抹除的 TypeScript 語法——不得用 parameter property、`enum`、`namespace`／`module`、`import =`、`export =`。要用明確欄位加建構子指派。
- **禁止 inline import**（`await import()`、`import("pkg").Type`、動態型別 import），只允許 top-level import。
- 型別檢查用 `tsgo`（`@typescript/native-preview`），格式與 lint 用 biome 2.3.5，indent 為 tab、寬度 3、行寬 120，範圍是 `packages/*/src/**/*.ts`、`packages/*/test/**/*.ts`、`packages/session-backends/*/src/**/*.ts`。
- 直接外部相依一律鎖定精確版本，由 `npm run check:pinned-deps` 把關。

來源：`tsconfig.base.json`、`biome.json`、`AGENTS.md`「Code Quality」、根 `package.json` 的 `check` script。

## 未確認

- `pi-server` 的穩定度：其 README 自述為實驗性、可能變更或移除，但未載明棄用時程。
- `packages/coding-agent/src/bun/` 與 `packages/ai/src/bun-oauth.ts` 顯示有 Bun runtime 支援路徑，但 `package.json` 的 `engines` 只宣告 Node `>=22.19.0`，Bun 的支援範圍與保證程度**未確認**。
- `pi-evals` 有兩套 vitest 設定：`vitest.test.config.ts` 只收 `test/**/*.test.ts`（harness 自身的單元測試，會被 CI 的 `npm test` 收錄），`vitest.config.ts` 才是跑 `src/*.eval.ts` 的模型驅動評測，需由 `npm run eval` 帶 provider 與 model 啟動。CI 不跑後者。
