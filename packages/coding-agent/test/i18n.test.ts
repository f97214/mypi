import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { clearExtensionTranslations, loadLocaleFile, registerTranslations, setLocale, t } from "../src/core/i18n.ts";

describe("i18n core translation lookup layer", () => {
	it("returns the key unchanged when no language is set", () => {
		setLocale(undefined);
		expect(t("to interrupt")).toBe("to interrupt");
	});

	it("falls back to the English key when the active locale has no entry", () => {
		registerTranslations("zh-TW", { "Move cursor up": "游標上移" });
		setLocale("zh-TW");
		expect(t("to interrupt")).toBe("to interrupt");
	});

	it("substitutes {name} placeholders in an untranslated template", () => {
		setLocale(undefined);
		expect(t("Updated to v{version}.", { version: "1.2.3" })).toBe("Updated to v1.2.3.");
	});

	it("uses a registered translation with substituted placeholders", () => {
		registerTranslations("zh-TW", {
			"Extension command '/{name}' conflicts with built-in interactive command.":
				"Extension 指令 '/{name}' 與內建互動指令衝突。",
		});
		setLocale("zh-TW");
		expect(
			t("Extension command '/{name}' conflicts with built-in interactive command.", {
				name: "deploy",
			}),
		).toBe("Extension 指令 '/deploy' 與內建互動指令衝突。");
	});

	it("lets a later registration override duplicate keys in the same locale", () => {
		registerTranslations("zh-TW", { Settings: "設定 A" });
		registerTranslations("zh-TW", { Settings: "設定 B" });
		setLocale("zh-TW");
		expect(t("Settings")).toBe("設定 B");
	});

	it("loads a valid locale JSON file and applies its entries", () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-i18n-"));
		const file = join(dir, "zh-TW.json");
		writeFileSync(file, JSON.stringify({ "No matches": "沒有符合的項目" }), "utf8");
		loadLocaleFile(file);
		setLocale("zh-TW");
		expect(t("No matches")).toBe("沒有符合的項目");
	});

	it("ignores a missing or invalid locale file without throwing", () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-i18n-"));
		const badFile = join(dir, "broken.json");
		writeFileSync(badFile, "{ not valid json", "utf8");
		expect(() => loadLocaleFile(badFile)).not.toThrow();
		expect(() => loadLocaleFile(join(dir, "missing.json"))).not.toThrow();
		setLocale("zh-TW");
		expect(t("Still untranslated")).toBe("Still untranslated");
	});

	it("keeps locales isolated from each other", () => {
		registerTranslations("ja-JP", { Settings: "設定（日）" });
		setLocale("ja-JP");
		expect(t("Settings")).toBe("設定（日）");
	});

	it("clearing extension translations keeps file-loaded entries and drops registered ones", () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-i18n-"));
		const file = join(dir, "zz-CLEAR.json");
		writeFileSync(file, JSON.stringify({ "File loaded key": "檔案譯文" }), "utf8");
		loadLocaleFile(file);
		registerTranslations("zz-CLEAR", { "Extension key": "外掛舊譯" });
		setLocale("zz-CLEAR");
		expect(t("File loaded key")).toBe("檔案譯文");
		expect(t("Extension key")).toBe("外掛舊譯");
		clearExtensionTranslations();
		setLocale("zz-CLEAR");
		expect(t("File loaded key")).toBe("檔案譯文");
		expect(t("Extension key")).toBe("Extension key");
	});

	it("re-registering after a clear replaces stale entries on reload", () => {
		registerTranslations("zz-RELOAD", { "to interrupt": "舊中斷" });
		clearExtensionTranslations();
		registerTranslations("zz-RELOAD", { "to interrupt": "新中斷" });
		setLocale("zz-RELOAD");
		expect(t("to interrupt")).toBe("新中斷");
	});
});
