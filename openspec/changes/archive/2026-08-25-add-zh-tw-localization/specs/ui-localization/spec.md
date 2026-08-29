## ADDED Requirements

### Requirement: Core translation lookup layer

The coding-agent package SHALL provide a central i18n module exporting a translate function t(key, params) where key is the exact English source string and params is an optional record of placeholder values. The module SHALL replace {placeholder} tokens in the resolved string with the corresponding param values. When no translation exists for the active locale, t(key, params) SHALL return the English key with placeholders substituted (identity behavior), so that English-mode output is byte-identical to current behavior.

#### Scenario: Missing translation falls back to English

- **WHEN** active locale is zh-TW and a key has no registered zh-TW entry
- **THEN** t() returns the original English string with any {placeholder} tokens substituted

##### Example: fallback and substitution

| Input | Expected Output | Notes |
| ----- | --------------- | ----- |
| key "to interrupt", locale en | "to interrupt" | identity, no dictionary |
| key "to interrupt", locale zh-TW, no entry | "to interrupt" | missing translation falls back |
| key "Updated to v{version}.", params {version: "1.2.3"}, locale en | "Updated to v1.2.3." | placeholder substituted |

#### Scenario: Placeholder substitution

- **WHEN** code calls t("Updated to v{version}.", { version: "1.2.3" })
- **THEN** the returned string is "Updated to v1.2.3." when untranslated, or the translated template with {version} substituted when a translation exists

#### Scenario: English mode is unchanged

- **WHEN** no language setting is configured and PI_LANG is unset
- **THEN** all user-visible text renders exactly as before this change

### Requirement: Language selection via settings and environment

The Settings interface SHALL support a language field persisted in the global settings.json, editable through the settings selector UI. The environment variable PI_LANG SHALL override the settings value at startup. The effective locale SHALL be resolved once during startup before any UI text or CLI help is rendered.

#### Scenario: Setting takes effect

- **WHEN** settings.json contains "language": "zh-TW" and PI_LANG is unset
- **THEN** user-visible text renders using zh-TW translations where available

#### Scenario: Environment variable overrides setting

- **WHEN** settings.json contains "language": "zh-TW" but PI_LANG=en
- **THEN** user-visible text renders in English

##### Example: override precedence

| PI_LANG | settings language | Effective locale |
| ------- | ----------------- | ---------------- |
| unset   | "zh-TW"           | zh-TW            |
| "en"    | "zh-TW"           | en               |
| "zh-TW" | unset             | zh-TW            |
| unset   | unset             | en               |

#### Scenario: Language item appears in settings selector

- **WHEN** the user opens the settings selector
- **THEN** a language item is listed showing the current value and allows switching it, and the choice persists to global settings.json after restart

### Requirement: Extension dictionary registration API

The ExtensionAPI SHALL expose registerTranslations(locale, dict) allowing an extension to register a flat record of translations for a given locale. Dictionaries from multiple extensions SHALL merge; for duplicate keys within the same locale, the later-loaded extension SHALL win. Unloading or reloading an extension SHALL remove that extension's previously registered dictionaries.

#### Scenario: Extension registers zh-TW dictionary

- **WHEN** an extension calls pi.registerTranslations("zh-TW", { "to interrupt": "中斷" }) and the active locale is zh-TW
- **THEN** UI text containing the key "to interrupt" renders as "中斷"

#### Scenario: Reload removes stale entries

- **WHEN** an extension that registered translations is reloaded via /reload
- **THEN** its old dictionary entries are removed before the new ones are applied

##### Example: reload behavior

- **GIVEN** extension A registered { "to interrupt": "舊譯" } for zh-TW
- **WHEN** /reload runs and A registers { "to interrupt": "中斷" }
- **THEN** t("to interrupt") returns "中斷" and no trace of "舊譯" remains in the registry

### Requirement: Startup-early locale file loading

At startup, before CLI help text is printed, the core SHALL load locale JSON files from the agent directory locales path (<agentDir>/locales/<locale>.json). Entries loaded from files and entries registered by extensions SHALL be merged into the same lookup registry, with extension registrations taking precedence over file entries for identical keys.

#### Scenario: CLI help renders translated before extensions load

- **WHEN** <agentDir>/locales/zh-TW.json exists, language is zh-TW, and the user runs pi --help
- **THEN** help text lines whose keys exist in the JSON render translated even though no extension has run yet

##### Example: early load ordering

- **GIVEN** <agentDir>/locales/zh-TW.json contains { "Usage:": "用法：" } and no extension is configured
- **WHEN** user runs pi --help with effective locale zh-TW
- **THEN** the usage line renders as "用法："

#### Scenario: Invalid locale file degrades silently

- **WHEN** <agentDir>/locales/zh-TW.json is missing or contains invalid JSON
- **THEN** startup continues and all text renders in English; no error interrupts startup

### Requirement: Full zh-TW translation pack

A project-local extension at .pi/extensions/i18n-zh-TW.ts SHALL register a Traditional Chinese (Taiwan) dictionary covering every extracted user-visible string in the interactive mode, interactive components, CLI help texts, keybinding descriptions, slash-command descriptions, and error message hotspots enumerated by this change. A script SHALL export the same dictionary to <agentDir>/locales/zh-TW.json so early-loading contexts use identical content.

#### Scenario: Dictionary coverage matches extracted keys

- **WHEN** the export script runs against the zh-TW extension dictionary and the set of keys collected by the extraction
- **THEN** every extracted key has a non-empty zh-TW entry, and the exported JSON content equals the extension dictionary

##### Example: coverage check failure mode

- **GIVEN** extracted keys number 850 and the dictionary misses 1 key
- **WHEN** the export script runs
- **THEN** it exits with a non-zero code and names the missing key

#### Scenario: Interactive UI displays Chinese

- **WHEN** language is zh-TW and the user starts interactive mode with the extension loaded
- **THEN** footer hints, dialog titles, prompts, and error messages whose keys are covered render in Traditional Chinese; uncovered strings fall back to English

### Requirement: TUI keybinding description injection

The tui package SHALL provide a setTranslations function accepting a record of translated strings used for keybinding descriptions. The coding-agent startup SHALL call setTranslations with the active locale's entries before constructing any TUI components. Default descriptions SHALL remain English when no translations are injected.

#### Scenario: Keybinding help shows translated descriptions

- **WHEN** language is zh-TW and translations are injected at startup
- **THEN** keybinding hint lines and help panels display zh-TW descriptions instead of English ones

##### Example: injection ordering

- **GIVEN** injected dict maps "Move cursor up" to "游標上移"
- **WHEN** the help panel renders the cursorUp keybinding
- **THEN** its description shows "游標上移"; before injection or with an empty dict it shows "Move cursor up"
