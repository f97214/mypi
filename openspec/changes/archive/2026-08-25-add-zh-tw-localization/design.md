## Context

mypi 是 pi-mono 的 fork，與上游同步頻繁（最近一次 2026-08-05）。使用者可見英文字串約 800–2,500 條，散落在約 50 個檔案：interactive-mode.ts（約 277 條）、modes/interactive/components/ 下約 40 個元件（約 368 條，最大熱點 settings-selector.ts 99 條）、main.ts 與 package-manager-cli.ts 的 CLI help、兩個 keybindings 描述檔（coding-agent 42 條、tui 47 條）、slash-commands 指令描述、以及錯誤訊息熱點（utils/shell.ts、core/compaction/、core/skills.ts、resolve-config-value.ts）。大量字串是含插值的模板字串（例：`Updated to v${latestVersion}. Use ... to view full changelog.`）。目前完全沒有 i18n 機制。

外掛機制（packages/coding-agent/src/core/extensions/）已成熟：ExtensionAPI 在 loader.ts 的 createExtensionAPI() 組裝，registerProvider 展示了「載入中先排隊、bindCore 後生效」的 pattern，可作為 registerTranslations 的實作範本。設定持久化由 core/settings-manager.ts 管理（全域 <agentDir>/settings.json + 專案覆蓋，深合併）。

## Goals / Non-Goals

**Goals:**

- 核心新增最小化、機械化的 t() 抽取層；英文模式輸出與現況位元組一致
- 翻譯內容全部放在外掛與 locale JSON，核心不硬編碼任何翻譯
- 覆蓋全部使用者可見文字：互動模式、元件、CLI help、keybinding 描述、slash-command 描述、錯誤訊息
- zh-TW 完整翻譯包，語言可由 settings.json language 欄位或 PI_LANG 切換

**Non-Goals:**

- 不翻譯 system prompt 與 LLM 對話內容
- 不做語系 fallback 鏈、複數形式規則、RTL 等完整 i18n 函式庫功能
- 不改 print/RPC 模式的少量 console 輸出以外的機器介面

## Decisions

### key 採用英文原文而非代碼式 key

t("to interrupt") 而非 t("hint.interrupt")。上游 merge 改到這些行時衝突直觀可解；英文模式 t() 是恆等函式，零行為風險。代碼式 key 需要維護雙份對照表且上游衝突難以判讀。

### 字典雙通道載入：啟動早期 JSON + 外掛註冊

CLI help 在 main.ts 最早期印出，早於 jiti 外掛載入，因此核心在啟動時先掃 <agentDir>/locales/<locale>.json。互動模式的字典由 .pi/extensions/i18n-zh-TW.ts 透過 pi.registerTranslations() 註冊（比照 registerProvider pattern 實作於 createExtensionAPI()）。兩者合併進同一 registry，外掛優先於檔案鍵值。匯出腳本保證 JSON 與 extension 字典內容一致。

### 參數替換採 {name} 具名佔位符

模板字串改寫為 t("Updated to v{version}.", { version })。不採位置參數（{0}），因為中文語序常與英文不同，具名佔位符讓譯文自由調整語序。

### tui 包用 setTranslations() 注入而非依賴 coding-agent 的 i18n 模組

packages/tui 不能反向依賴 packages/coding-agent。tui 只提供一個模組級 setTranslations(record) 與內部查表；coding-agent 啟動時餵入當前語系條目。預設為空表即英文原文。

### 語言解析單次啟動決定：PI_LANG > settings.json language > 未設定（英文）

不做執行期熱切換；切語言需重啟或 /reload。避免 UI 元件快取已渲染字串導致的半翻譯狀態。

### 描述類字串存英文原文，渲染／消費時才翻譯（禁止 module 級 t() 求值）

實作後發現的關鍵約束：module 級常數（core/slash-commands.ts 的 BUILTIN_SLASH_COMMANDS、core/keybindings.ts 的 KEYBINDINGS）在 import 當下求值，早於 main() 的 initializeLocale()，t() 會永遠凍結成英文。因此這兩處描述存純英文 key：slash 指令描述在消費端（interactive-mode.ts 組裝自動完成清單時）以 t(description, { name: APP_NAME }) 翻譯；app 快捷鍵描述繼承 tui 的 KeybindingsManager.getDefinition()，經啟動與切換時注入的翻譯表在呼叫當下解析。新增程式碼時禁止在 module 頂層呼叫 t()。

### clearExtensionTranslations 的時機：extension factory 重跑前，而非 _buildRuntime

實作後發現的修復：清理原本放在 agent-session 的 _buildRuntime()，但 --help 與互動模式啟動都會走完整 session bootstrap，順序是「initializeLocale 載入 → extension 註冊 → _buildRuntime 清理」——清理發生在註冊之後，每次啟動都把整個字典清空，UI 全部回退英文。正確位置是 loader.ts 的 loadExtensionsInternal() 開頭：每次 extension factory 重跑前先清舊條目，註冊後不再清除。/reload 語意不變（清舊 → 重註冊新），且 pre-trust 與 trusted 兩次載入 pass 之間的清理也安全（每個 pass 的 factory 都會重新註冊）。

## Implementation Contract

- 行為：設定 language=zh-TW 後，互動模式 footer 提示、對話框標題、提示訊息、錯誤訊息、CLI help、keybinding 幫助文字以繁體中文呈現；未涵蓋的 key 顯示英文原文。language 未設定且 PI_LANG 未設時，所有輸出與現況完全相同。
- 介面／資料形狀：
  - core/i18n.ts 匯出：t(key: string, params?: Record<string, string | number>): string、registerTranslations(locale, dict)、setLocale(locale)、loadLocaleFile(path)
  - ExtensionAPI 新增方法簽名：pi.registerTranslations(locale: string, dict: Record<string, string>): void
  - Settings 新增欄位：language?: string；SettingsManager 新增 getLanguage()/setLanguage()
  - settings-selector 的 SettingsConfig 新增 language 顯示項與 onLanguageChange 回呼
  - packages/tui 新增匯出：setTranslations(dict: Record<string, string>): void
  - locale JSON 格式：扁平物件 { "English source": "譯文" }，路徑 <agentDir>/locales/<locale>.json
- 失敗模式：locale 檔不存在或 JSON 解析失敗 → 忽略該檔並以英文呈現（靜默降級，不中斷啟動）；外掛字典重複 key → 後載入者覆蓋。
- 額外約束：module 頂層禁止呼叫 t()（會在 initializeLocale 前求值而凍結英文）；描述類資料結構存英文原文，於渲染／消費時翻譯。
- 驗收條件：
  - npm run check 通過（零新錯誤）
  - PI_LANG 未設定時，pi --help 輸出與變更前一致
  - PI_LANG=zh-TW 時，pi --help 出現中文 help 文字
  - tmux 啟動互動模式（language=zh-TW），footer 提示與 /model 等對話框顯示中文
  - 匯出腳本執行後產出的 zh-TW.json 內容與 extension 字典一致且涵蓋全部抽取 key
- 範圍邊界：
  - In scope：上述列出的字串抽取熱點、i18n 基礎設施、zh-TW 字典、匯出腳本、settings UI 語言項
  - Out of scope：system prompt、LLM 對話內容、print/RPC 機器輸出、其他語系字典、執行期熱切換

## Risks / Trade-offs

- [抽取觸及約 50 檔數百處，日後上游同步衝突面大] → key=英文原文讓衝突直觀；抽取集中在少數幾個大型 commit，merge 時以「還原英文原文行 + 重套 t() 包裹」處理
- [interactive-mode.ts 超過 6500 行，大範圍編輯易引入筆誤] → 抽取以機械式規則逐段進行，每完成一個檔案即跑 npm run check
- [部分長文案含內嵌樣式呼叫（theme.bold 等）跨行拼接] → 這類字串拆為帶佔位符的完整模板，樣式包裹移到 t() 回傳值之後套用
- [CLI help 早於外掛載入] → 啟動早期 locales JSON 通道專門解決此順序問題

## Migration Plan

純加法變更，無資料遷移。回滾方式：還原 commit 即可；locale JSON 與外掛檔案為新增檔案，殘留無副作用。

## Open Questions

(none)
