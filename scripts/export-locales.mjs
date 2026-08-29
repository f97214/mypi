#!/usr/bin/env node
// Export .pi/extensions/i18n-zh-TW.ts dictionary to <agentDir>/locales/zh-TW.json
// and verify coverage against every t() key extracted from packages/coding-agent/src
// plus TUI keybinding descriptions. Exits non-zero listing missing keys.
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const srcDir = join(root, "packages", "coding-agent", "src");
const dictPath = join(root, ".pi", "extensions", "i18n-zh-TW.ts");

function listTsFiles(dir) {
	const out = [];
	for (const name of readdirSync(dir)) {
		const full = join(dir, name);
		if (statSync(full).isDirectory()) {
			out.push(...listTsFiles(full));
		} else if (name.endsWith(".ts")) {
			out.push(full);
		}
	}
	return out;
}

function unescapeSource(raw) {
	return raw.replace(
		/\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|n|t|r|0|"|'|`|\\)/g,
		(match, esc) => {
			if (esc.startsWith("u{") || esc.startsWith("u") || esc.startsWith("x")) {
				return String.fromCodePoint(parseInt(esc.replace(/[ux]\{?/, ""), 16));
			}
			switch (esc) {
				case "n":
					return "\n";
				case "t":
					return "\t";
				case "r":
					return "\r";
				case "0":
					return "\0";
				default:
					return esc;
			}
		},
	);
}

function collectKeys() {
	const keys = new Set();
	for (const file of listTsFiles(srcDir)) {
		const source = readFileSync(file, "utf8");
		const re = /\bt\(\s*(?:"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|`([^`]*)`)/g;
		let m;
		while ((m = re.exec(source)) !== null) {
			const raw = m[1] ?? m[2] ?? m[3];
			if (typeof raw !== "string" || raw.length === 0 || raw.includes("${")) continue;
			keys.add(unescapeSource(raw));
		}
	}
	const tuiKeybindings = join(root, "packages", "tui", "src", "keybindings.ts");
	const tuiSource = readFileSync(tuiKeybindings, "utf8");
	const descRe = /description:\s*"((?:[^"\\]|\\.)*)"/g;
	let d;
	while ((d = descRe.exec(tuiSource)) !== null) {
		keys.add(unescapeSource(d[1]));
	}
	return [...keys];
}

function loadDictionary() {
	const source = readFileSync(dictPath, "utf8");
	const dict = {};
	const re = /"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"/g;
	let m;
	while ((m = re.exec(source)) !== null) {
		try {
			dict[JSON.parse(`"${m[1]}"`)] = JSON.parse(`"${m[2]}"`);
		} catch {
			throw new Error(`Unparseable dictionary entry near: ${m[1].slice(0, 60)}`);
		}
	}
	return dict;
}

function main() {
	const args = process.argv.slice(2);
	const outIdx = args.indexOf("--out");
	const outPath =
		outIdx !== -1 ? args[outIdx + 1] : join(homedir(), ".pi", "agent", "locales", "zh-TW.json");

	const keys = collectKeys();
	const dict = loadDictionary();

	const missing = keys.filter((key) => !(key in dict) || dict[key].length === 0);
	const stale = Object.keys(dict).filter((key) => !keys.includes(key));

	if (missing.length > 0) {
		console.error(`Missing ${missing.length} translation(s):`);
		for (const key of missing) {
			console.error(JSON.stringify(key));
		}
		process.exit(1);
	}

	mkdirSync(dirname(outPath), { recursive: true });
	writeFileSync(outPath, `${JSON.stringify(dict, null, "\t")}\n`, "utf8");
	console.log(
		`Exported ${Object.keys(dict).length} entries (${keys.length} code keys, ${stale.length} extra) -> ${outPath}`,
	);
}

main();
