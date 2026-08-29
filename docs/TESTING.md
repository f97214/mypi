# 測試

## 目錄

- [框架與位置](#框架與位置)
- [怎麼跑](#怎麼跑)
- [不要做的事](#不要做的事)
- [coding-agent 的測試慣例](#coding-agent-的測試慣例)
- [Spectra 現況](#spectra-現況)
- [限制](#限制)
- [這台機器上的實測結果](#這台機器上的實測結果)

## 框架與位置

| 套件 | 框架 | 測試位置 | 套件內命令 |
|---|---|---|---|
| `packages/agent` | vitest | `test/` | `vitest --run` |
| `packages/ai` | vitest | `test/` | `vitest --run` |
| `packages/client` | vitest | `test/` | `vitest --run` |
| `packages/coding-agent` | vitest | `test/`、`test/suite/`、`test/suite/regressions/` | `vitest --run` |
| `packages/evals` | vitest | `test/`（harness 單元測試） | `vitest run --config vitest.test.config.ts` |
| `packages/protocol` | vitest | `test/` | `vitest --run` |
| `packages/server` | vitest | `test/` | `vitest --run` |
| `packages/session-backends/sqlite-node` | vitest | `test/` | `vitest --run` |
| `packages/telemetry` | vitest | `test/` | `vitest --run` |
| `packages/tui` | **`node:test`**（不是 vitest） | `test/` | `node --test --test-reporter=dot --test-reporter-destination=stdout test/*.test.ts` |

根目錄的 `vitest.base.ts` 把 `@earendil-works/*` 的 import 別名指向各套件的 `src/` 進入點，所以測試跑的是原始碼不是 dist。

另有 `scripts/*.test.mjs`（例如 `scripts/publish-release-announcement.test.mjs`），由 `npm run test:scripts` 以 `node --test` 執行。

`packages/evals` 有兩套 vitest 設定：`vitest.test.config.ts` 只收 `test/**/*.test.ts`（會被 CI 收錄），`vitest.config.ts` 才是模型驅動的 `src/*.eval.ts` 評測，需 `npm run eval` 帶 provider 與 model 才會跑。

來源：各套件 `package.json`、`vitest.base.ts`、`packages/evals/vitest.test.config.ts`、根 `package.json` 的 `test`／`test:scripts`。

## 怎麼跑

**整個 repository（非 e2e）——從根目錄跑這一個：**

```bash
./test.sh
```

`test.sh` 會建立隔離的 `HOME`／`TMPDIR`／npm 設定，用 `env -i` 從空白環境啟動，只放行必要的平台與測試變數，並設 `PI_NO_LOCAL_LLM=1`。沒有 API key 時依賴 LLM 的測試會跳過。它在 Windows 上也可用：腳本明確把 `SystemRoot`、`WINDIR`、`COMSPEC`、`PATHEXT` 等值繼承給子程序。結束時只刪除它自己標記過 `.pi-test-owned` 的暫存目錄。

**單一測試檔（從套件根目錄）：**

```bash
# vitest 套件
node "$(git rev-parse --show-toplevel)/node_modules/vitest/dist/cli.js" --run test/specific.test.ts

# packages/tui（node:test）
node --test test/specific.test.ts
```

建立或修改測試檔之後就跑它，反覆修測試或實作直到通過。

來源：`test.sh`、`AGENTS.md`「Commands」。

## 不要做的事

- **不要直接跑完整 vitest suite。** 當 endpoint／auth 環境變數存在時它會啟動 e2e 測試。非 e2e 測試一律走 `./test.sh`。
- **不要在未經使用者要求時跑 `npm test`。**
- `test/suite/` 底下不得使用真實 provider API、真實 API key、網路呼叫或付費 token。

來源：`AGENTS.md`「Commands」、`packages/coding-agent/test/suite/README.md`。

## coding-agent 的測試慣例

`packages/coding-agent/test/suite/` 是圍繞 `AgentSession` 與 `AgentSessionRuntime` 的新 harness 測試套件：

- 用 `test/suite/harness.ts`。
- 用 `packages/ai/src/providers/faux.ts` 的 faux provider。
- 保持 CI 安全且具決定性。
- 除非缺少能力逼不得已，不要使用或擴充舊的 `test/test-harness.ts` 路徑。
- 廣泛的生命週期與特性測試直接放 `test/suite/`。
- 針對特定 issue 的迴歸測試放 `test/suite/regressions/`，命名為 `<issue-number>-<short-slug>.test.ts`（例如 `2023-queued-slash-command-followup.test.ts`）。

來源：`packages/coding-agent/test/suite/README.md`、`AGENTS.md`「Commands」。

## Spectra 現況

repository 根目錄有 `.spectra.yaml` 與 `openspec/`（`config.yaml` 加空的 `changes/archive`、`specs/`），所以 Spectra 的規格驅動流程本身可用。

但 `.spectra.yaml` 的 **`tdd` 仍是註解狀態、未啟用**，`openspec/config.yaml` 也沒有測試品質關卡。因此**沒有** TDD 證據流程、沒有 `.claude/rules/testing.md`、沒有 evidence observer，`openspec/changes/<change>/test-evidence.md` 也不會被產生或要求。要啟用需要 `./test.sh` 先能在你的環境下實際跑綠——目前跑不綠，原因見最後一節。

來源：`.spectra.yaml`、`openspec/config.yaml`。

## 限制

- 依賴 LLM 的測試在沒有 API key 時會跳過——**跳過不等於通過**，報告時要分開講。
- e2e 測試會在 endpoint／auth 環境變數存在時啟動，所以「本機跑過」與「CI 跑過」涵蓋範圍可能不同。
- `packages/tui` 用 `node:test` 而非 vitest，vitest 的 selector 與 reporter 參數對它無效。
- 本 repository 沒有集中的 coverage 設定；`.gitignore` 有 `coverage/` 與 `.nyc_output/` 條目，但**沒有**產生 coverage 的 script。coverage 現況**未確認**。

## 這台機器上的實測結果

以下是 2026-08-24 在 Windows 11 + Git Bash 下，`npm ci --ignore-scripts` 之後跑 `./test.sh` 的實際結果（退出碼 1）。記在這裡是為了讓下一個人不必重新踩一遍。

全綠：`pi-client`（32）、`pi-protocol`（147）、`pi-telemetry`（15）、`pi-session-backend-sqlite-node`（87）。
有失敗：`pi-agent-core`、`pi-ai`、`pi-coding-agent`、`pi-evals`、`pi-server`、`pi-tui`。

失敗分三類，**都不是產品程式碼缺陷**：

1. **缺少產生物（絕大多數）**：`Cannot find module './data/amazon-bedrock.json'`。`packages/ai/src/providers/data/` 被 `.gitignore` 排除，要由 `npm run hydrate:model-data`（只產生 data JSON）或 `npm run generate:models` 產生，兩者都需要連網。少數測試另外需要 `node_modules/@earendil-works/pi-ai/dist/index.js`，那要 `npm run build`。
   同一個原因也會讓 `tsgo --noEmit` 失敗：model ID 的聯合型別由產生出來的 catalog 推導，data 不存在時型別塌成 `never`，所有帶 model ID 的呼叫都報 `TS2345`。
2. **Git Bash 的 `TMPDIR`／`HOME` 路徑形式**（`pi-agent-core` 2 個、`pi-tui` 5 個）：測試期望 `C:\Users\...\Temp\pi-test.…`，實際拿到 `/tmp/pi-test.…`。`test.sh` 用 `env -i` 傳入 POSIX 形式的路徑，Node 在 Windows 上原樣採用，於是 `realpath()` 與環境變數對不起來。**改用原生 Windows shell 執行可能可避開，未確認。**
3. **Windows 的 unix domain socket**（`pi-server` 16 個）：`listen EACCES … server.sock`。

第 1 類補上產生物即可解決；第 2、3 類在 Git Bash 下是環境限制，不是要修的 bug。回報測試結果時要把這三類跟真正的失敗分開講。
