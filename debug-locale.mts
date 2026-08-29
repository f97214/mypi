import { readFileSync } from "node:fs";
import { getSettingsPath, getAgentDir } from "./packages/coding-agent/src/config.ts";
import { stripBom } from "./packages/coding-agent/src/utils/text.ts";

console.log("settingsPath:", getSettingsPath());
try {
	const raw = readFileSync(getSettingsPath(), "utf8");
	console.log("raw length:", raw.length, "first char code:", raw.charCodeAt(0));
	const parsed: unknown = JSON.parse(stripBom(raw));
	const language = (parsed as { language?: unknown }).language;
	console.log("language field:", JSON.stringify(language), typeof language);
} catch (err) {
	console.log("THREW:", err);
}
console.log("agentDir:", getAgentDir());
console.log("locales exists:", require("node:fs").existsSync(getAgentDir() + "/locales/zh-TW.json"));
