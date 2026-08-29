type TranslationParams = Record<string, string | number>;

import { readFileSync } from "node:fs";
import { basename } from "node:path";

const registries = new Map<string, Map<string, string>>();

const extensionKeys = new Map<string, Set<string>>();

let activeLocale: string | undefined;

function getRegistry(locale: string): Map<string, string> {
	let registry = registries.get(locale);
	if (!registry) {
		registry = new Map();
		registries.set(locale, registry);
	}
	return registry;
}

function applyEntries(locale: string, dict: Record<string, string>, track: boolean): void {
	const registry = getRegistry(locale);
	let tracked: Set<string> | undefined;
	if (track) {
		tracked = extensionKeys.get(locale);
		if (!tracked) {
			tracked = new Set();
			extensionKeys.set(locale, tracked);
		}
	}
	for (const [key, value] of Object.entries(dict)) {
		if (typeof value !== "string") {
			continue;
		}
		registry.set(key, value);
		tracked?.add(key);
	}
}

export function registerTranslations(locale: string, dict: Record<string, string>): void {
	applyEntries(locale, dict, true);
}

export function clearExtensionTranslations(): void {
	for (const [locale, keys] of extensionKeys) {
		const registry = registries.get(locale);
		if (!registry) {
			continue;
		}
		for (const key of keys) {
			registry.delete(key);
		}
	}
	extensionKeys.clear();
}

export function loadLocaleFile(path: string): void {
	let content: string;
	try {
		content = readFileSync(path, "utf8");
	} catch {
		return;
	}
	try {
		const parsed: unknown = JSON.parse(content);
		if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
			applyEntries(basename(path, ".json"), parsed as Record<string, string>, false);
		}
	} catch {
		return;
	}
}

export function setLocale(locale: string | undefined): void {
	activeLocale = locale;
}

export function getLocale(): string | undefined {
	return activeLocale;
}

export function getTranslations(locale: string): Record<string, string> {
	const registry = registries.get(locale);
	if (!registry) {
		return {};
	}
	return Object.fromEntries(registry);
}

function substitute(template: string, params?: TranslationParams): string {
	if (!params) {
		return template;
	}
	return template.replace(/\{(\w+)\}/g, (match, name: string) => {
		const value = params[name];
		return value === undefined ? match : String(value);
	});
}

export function t(key: string, params?: TranslationParams): string {
	if (activeLocale) {
		const translation = registries.get(activeLocale)?.get(key);
		if (translation !== undefined) {
			return substitute(translation, params);
		}
	}
	return substitute(key, params);
}
