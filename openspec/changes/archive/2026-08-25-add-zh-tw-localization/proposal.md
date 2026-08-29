## Why

mypi 是經常同步上游 pi-mono 的 fork，但整個介面（互動模式、元件、CLI help、錯誤訊息）約 800–2,500 條使用者可見英文字串硬編碼散落在約 50 個檔案中，完全沒有 i18n 機制。台灣繁體中文使用者需要完整的繁體中文介面，且做法必須把核心 diff 最小化、機械化，以壓低日後上游同步的衝突成本。

## What Changes

- 新增核心字串抽取層：packages/coding-agent 內新增 i18n 模組，提供 t(key, params) 函式；key 即英文原文，無翻譯時恆等回傳（英文模式行為完全不變）。描述類資料結構（slash 指令、快捷鍵）存英文原文，於渲染／消費時翻譯——module 頂層禁止呼叫 t()（會在語言解析前求值而凍結英文）
- 字典載入雙通道：
  - 外掛 API：ExtensionAPI 新增 registerTranslations(locale, dict)，字典本體放在專案 .pi/extensions/i18n-zh-TW.ts
  - 啟動早期載入：<agentDir>/locales/zh-TW.json，解決 CLI help 在外掛載入前印出的順序問題；提供匯出腳本從 extension 字典產生此 JSON
- 語言切換：settings.json 新增 language 欄位（含 settings-selector UI 項目），環境變數 PI_LANG 可覆蓋
- tui 包新增 setTranslations() 注入點，讓 coding-agent 啟動時餵入 keybindings 描述翻譯
- 全量字串抽取為機械式 t() 呼叫：interactive-mode.ts（約 277 條）、components/ 約 40 個檔案（約 368 條）、CLI help（main.ts、package-manager-cli.ts）、core/keybindings.ts 與 packages/tui/src/keybindings.ts 的描述、slash-commands 指令描述、錯誤訊息熱點（utils/shell.ts、compaction、skills、resolve-config-value.ts）
- 完整 zh-TW 翻譯字典覆蓋全部抽取條目

## Non-Goals

- 不翻譯 system prompt 與 LLM 對話內容——只處理使用者介面文字
- 不做語系 fallback 鏈、複數形式規則等完整 i18n 函式庫功能——單一 zh-TW 目標語系不需要
- 不採用純外掛方案（不改核心）——外掛 API 攔不到對話框與提示訊息等核心字串，覆蓋率不足
- 不改用 hash 或代碼式 key——key 必須是英文原文，上游 merge 衝突才直觀可解

## Capabilities

### New Capabilities

- `ui-localization`: 使用者介面多語系能力——核心 t() 抽取層、語言設定與切換（settings.json language 欄位 + PI_LANG）、外掛字典註冊 API（registerTranslations）、啟動早期 locale JSON 載入、zh-TW 繁體中文翻譯包

### Modified Capabilities

(none)

## Impact

- Affected specs: ui-localization（新 capability）
- Affected code:
  - New:
    - packages/coding-agent/src/core/i18n.ts（t() 抽取層與 registry）
    - .pi/extensions/i18n-zh-TW.ts（zh-TW 字典外掛）
    - scripts/export-locales.mjs（字典匯出 locales JSON 的腳本）
  - Modified:
    - packages/coding-agent/src/core/settings-manager.ts（language 欄位）
    - packages/coding-agent/src/core/extensions/types.ts（ExtensionAPI 加 registerTranslations）
    - packages/coding-agent/src/core/extensions/loader.ts（API 實作）
    - packages/coding-agent/src/modes/interactive/interactive-mode.ts（約 277 條字串抽取）
    - packages/coding-agent/src/modes/interactive/components/ 下約 40 個元件（約 368 條字串抽取）
    - packages/coding-agent/src/main.ts（CLI help）
    - packages/coding-agent/src/package-manager-cli.ts（CLI help）
    - packages/coding-agent/src/core/keybindings.ts（42 條描述）
    - packages/tui/src/keybindings.ts（47 條描述與注入點）
    - packages/coding-agent/src/core/slash-commands.ts（指令描述）
    - packages/coding-agent/src/utils/shell.ts（錯誤訊息）
    - packages/coding-agent/src/core/compaction/ 下訊息
    - packages/coding-agent/src/core/skills.ts（驗證訊息）
    - packages/coding-agent/src/core/resolve-config-value.ts（錯誤訊息）
