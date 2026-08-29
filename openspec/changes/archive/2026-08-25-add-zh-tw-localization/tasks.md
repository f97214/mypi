## 1. i18n 基礎設施——Core translation lookup layer 與啟動早載入（TDD）

- [x] 1.1 先寫失敗測試：為 Core translation lookup layer 新增 vitest 測試檔（packages/coding-agent/test/ 下），案例涵蓋「缺譯回退英文原文」「Updated to v{version}. 模板的 {name} 具名佔位符替換」「同 locale 重複 key 後註冊者覆蓋」「Startup-early locale file loading 的合法 JSON 載入生效」「壞 JSON 靜默降級不中斷」。行為合約：language 未設定時 t() 為恆等函式。驗證方式：執行該測試檔確認全部紅燈（模組不存在而失敗）。
- [x] 1.2 實作 packages/coding-agent/src/core/i18n.ts：t(key, params)、registerTranslations(locale, dict)、setLocale(locale)、loadLocaleFile(path)，key 採用英文原文而非代碼式 key，參數替換採 {name} 具名佔位符；實作 Startup-early locale file loading：啟動最早期掃描 <agentDir>/locales/<locale>.json 併入 registry（字典雙通道載入：啟動早期 JSON + 外掛註冊的檔案通道），JSON 缺檔或解析失敗時靜默忽略。驗證方式：1.1 的測試全數轉綠。

## 2. 語言設定與解析

- [x] 2.1 [P] Language selection via settings and environment——設定面：packages/coding-agent/src/core/settings-manager.ts 的 Settings 增加 language?: string 欄位與 getLanguage()/setLanguage()；components/settings-selector.ts 的 SettingsConfig 增加語言顯示項與 onLanguageChange 回呼；interactive-mode.ts 的 showSettingsSelector() 讀值接線。行為合約：使用者可在設定選單切換語言且選擇持久化到全域 settings.json。驗證方式：tmux 開啟設定選單確認 Language 項存在、切換後檢查 settings.json 內容。
- [x] 2.2 [P] Language selection via settings and environment——解析面：實作語言解析單次啟動決定：PI_LANG > settings.json language > 未設定（英文），在 CLI help 與任何 UI 渲染前呼叫 setLocale。行為合約：環境變數可覆蓋設定檔且解析只發生一次。驗證方式：手動斷言——settings 設 zh-TW 但 PI_LANG=en 時 pi --help 為英文；反過來 PI_LANG=zh-TW 時為中文。

## 3. 外掛字典 API

- [x] 3.1 Extension dictionary registration API：core/extensions/types.ts 的 ExtensionAPI 新增 registerTranslations(locale, dict) 宣告，core/extensions/loader.ts 的 createExtensionAPI() 比照 registerProvider pattern 實作；extension 經 /reload 重載時先移除該 extension 舊字典再套用新的。行為合約：外掛可註冊翻譯且熱載入不留殘留條目。驗證方式：暫存測試外掛註冊一條譯文後 UI 顯示譯文、/reload 後舊譯文消失，驗畢移除測試外掛。

## 4. tui 描述注入

- [x] 4.1 TUI keybinding description injection：packages/tui 新增匯出 setTranslations(dict)，tui 包用 setTranslations() 注入而非依賴 coding-agent 的 i18n 模組；packages/tui/src/keybindings.ts 的 47 條描述改經注入表查詢，coding-agent 啟動時於建構任何 TUI 元件前餵入當前語系條目。行為合約：zh-TW 下快捷鍵提示與說明面板顯示中文，未注入時維持英文。驗證方式：npm run check 通過 + tmux 確認 zh-TW 下 footer 快捷鍵提示為中文。

## 5. 字串抽取（機械式改為 t() 呼叫；key 採用英文原文而非代碼式 key）

- [x] 5.1 [P] 抽取 interactive-mode.ts 全部約 277 條使用者可見字串為 t() 呼叫，含內嵌樣式呼叫（theme.bold 等）的字串拆為帶 {name} 佔位符的完整模板、樣式包裹移到 t() 回傳值之後。行為合約：抽取後英文模式輸出不變。驗證方式：npm run check 通過；PI_LANG 未設定時 pi 啟動畫面與變更前一致。
- [x] 5.2 [P] 抽取 modes/interactive/components/ 下高頻元件（settings-selector、model-selector、footer、login-dialog、first-time-setup、session-selector、tree-selector、config-selector、oauth-selector、scoped-models-selector、thinking-selector、mermaid）。行為合約：這些對話框與清單的所有標題、提示、錯誤訊息可被字典翻譯。驗證方式：npm run check 通過。
- [x] 5.3 [P] 抽取其餘 modes/interactive/components/ 元件（5.2 未列出的全部）。行為合約：元件層無遺漏硬編碼字串。驗證方式：npm run check 通過 + 以 grep 掃描 components/ 目錄剩餘含引號英文字串人工複核清單。
- [x] 5.4 [P] 抽取 CLI help：main.ts 與 package-manager-cli.ts 的 help/usage 文字（依賴 Startup-early locale file loading 在外掛載入前生效）。行為合約：pi --help 與 package manager CLI 的 help 在 zh-TW 下顯示中文。驗證方式：PI_LANG=zh-TW pi --help 輸出含中文、未設定時輸出與變更前一致。
- [x] 5.5 [P] 抽取 core/keybindings.ts 的 42 條描述與 core/slash-commands.ts 的指令描述。行為合約：快捷鍵說明與 slash command 清單描述可翻譯。驗證方式：npm run check 通過。
- [x] 5.6 [P] 抽取錯誤訊息熱點：utils/shell.ts、core/compaction/ 下訊息、core/skills.ts 驗證訊息、core/resolve-config-value.ts 錯誤訊息。行為合約：這些錯誤情境在使用者面前以當前語系呈現。驗證方式：npm run check 通過。

## 6. zh-TW 字典——Full zh-TW translation pack

- [x] 6.1 Full zh-TW translation pack——字典本體：新增 .pi/extensions/i18n-zh-TW.ts，以 pi.registerTranslations("zh-TW", dict) 註冊涵蓋群組 5 全部抽取 key 的台灣繁體中文字典，譯文使用台灣慣用詞彙（如「設定」非「设置」）。行為合約：zh-TW 模式下互動模式 footer 提示、對話框、錯誤訊息以繁體中文呈現，未涵蓋 key 回退英文。驗證方式：tmux 啟動互動模式抽查 footer、/model 對話框、設定選單均為中文。
- [x] 6.2 Full zh-TW translation pack——匯出與涵蓋率檢查：新增 scripts/export-locales.mjs：從 .pi/extensions/i18n-zh-TW.ts 匯出扁平 JSON 至 <agentDir>/locales/zh-TW.json，並比對抽取 key 集合做涵蓋率檢查，缺項時以非零結束碼失敗並印出缺漏 key。行為合約：JSON 內容與 extension 字典一致且涵蓋全部 key，CLI help 早載入通道取得相同內容。驗證方式：執行腳本成功產出 JSON、故意刪一條 key 後腳本以非零結束碼失敗。

## 7. 整體驗證

- [x] 7.1 執行 npm run check（完整輸出），修掉所有 error/warning/info 直到乾淨。行為合約：型別、lint、格式全數通過。驗證方式：npm run check 零退出。
- [x] 7.2 端到端手動驗收：tmux 分別以 PI_LANG 未設定與 PI_LANG=zh-TW 啟動互動模式，逐項確認——英文模式啟動畫面與變更前一致；中文模式下 footer 提示、/model 與 /settings 對話框、錯誤情境訊息、CLI help 為繁體中文。行為合約：規格中所有 Scenario 的可觀察結果成立。驗證方式：tmux capture-pane 截圖比對記錄於任務回報。

## 8. 實作後修復（凍結描述與清理時機）

- [x] 8.1 修復凍結描述——「描述類字串存英文原文，渲染／消費時才翻譯（禁止 module 級 t() 求值）」：core/slash-commands.ts 的 BUILTIN_SLASH_COMMANDS（23 條）與 core/keybindings.ts 的 KEYBINDINGS（42 條）原在 module 頂層以 t() 求值，早於 initializeLocale() 而永遠凍結英文。改為描述存純英文 key；slash 描述在 interactive-mode.ts 組裝自動完成清單時以 t(description, { name: APP_NAME }) 翻譯，app 快捷鍵描述經 tui 注入表於 getDefinition() 呼叫當下解析（quit 指令的 "Quit {name}" 模板由消費端帶入 APP_NAME）。行為合約：zh-TW 下 slash 選單與 footer 快捷鍵提示顯示中文，英文模式輸出與 HEAD baseline 位元組一致。驗證方式：模擬測試斷言 t("Open settings menu") 為「開啟設定選單」、t("Cancel or abort") 為「取消或中止」；PI_LANG=en 時 pi --help 與 baseline diff 為空。
- [x] 8.2 修復字典清理時機——「clearExtensionTranslations 的時機：extension factory 重跑前，而非 _buildRuntime」：clearExtensionTranslations() 原放在 agent-session 的 _buildRuntime()，但 --help 與互動模式啟動都會先載入 extension（註冊字典）再走 _buildRuntime（清理），導致每次啟動字典被清空、UI 全部回退英文。將清理移至 core/extensions/loader.ts 的 loadExtensionsInternal() 開頭（factory 重跑前清舊、註冊後不清），/reload 語意不變。行為合約：settings language=zh-TW 且無 PI_LANG 時，pi --help 輸出完整繁體中文。驗證方式：實測 pi --help 首行為「pi - AI 具備讀取、bash、編輯、寫入工具的編碼助理」且含「用法：」「指令：」；PI_LANG=en 時與 HEAD baseline 位元組一致；i18n/keybindings/args 測試 96 筆全數通過。
