/**
 * Subagent support for pi.
 *
 * Scans agent definition files and registers a "task" tool. Each invocation
 * runs the named agent in an isolated in-memory session with its own system
 * prompt and tool allowlist, then returns the final assistant text.
 *
 * Definition locations (first definition with a given name wins):
 * - <cwd>/.pi/agents/*.md
 * - <cwd>/.claude/agents/*.md   (Claude Code compatible)
 * - <agentDir>/agents/*.md      (~/.pi/agent/agents)
 * - ~/.claude/agents/*.md       (Claude Code compatible)
 *
 * Frontmatter fields:
 * - name: agent identifier used by the task tool (defaults to filename stem)
 * - description: when to use this agent
 * - tools: optional tool allowlist (comma-separated string or YAML list).
 *   Claude Code names are mapped to pi equivalents (Read->read, Glob->find, ...).
 * - model: optional "provider/model" override
 *
 * The markdown body below the frontmatter becomes the subagent system prompt.
 */

import { homedir } from "node:os";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, join } from "node:path";
import { Type } from "typebox";
import {
	createAgentSession,
	DefaultResourceLoader,
	getAgentDir,
	ModelRuntime,
	parseFrontmatter,
	resolveCliModel,
	SessionManager,
	type CreateAgentSessionOptions,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

interface SubagentFrontmatter {
	name?: unknown;
	description?: unknown;
	tools?: unknown;
	model?: unknown;
}

interface SubagentDefinition {
	name: string;
	description: string;
	tools: string[] | undefined;
	model: string | undefined;
	systemPrompt: string;
	filePath: string;
}

const KNOWN_TOOLS = new Set(["read", "bash", "powershell", "edit", "write", "grep", "find", "ls"]);

const TOOL_ALIASES: Record<string, string> = {
	read: "read",
	bash: "bash",
	edit: "edit",
	write: "write",
	grep: "grep",
	glob: "find",
	find: "find",
	ls: "ls",
	powershell: "powershell",
};

function parseToolsField(raw: unknown): string[] | undefined {
	if (raw === undefined || raw === null) return undefined;
	const rawList = Array.isArray(raw) ? raw.map((item) => String(item)) : String(raw).split(",");
	const names: string[] = [];
	for (const item of rawList) {
		const key = item.trim().toLowerCase();
		if (!key) continue;
		const mapped = TOOL_ALIASES[key] ?? key;
		if (!KNOWN_TOOLS.has(mapped)) continue;
		if (!names.includes(mapped)) names.push(mapped);
	}
	return names.length > 0 ? names : undefined;
}

function loadDefinitionsFromDir(dir: string): SubagentDefinition[] {
	if (!existsSync(dir)) return [];
	let entries: ReturnType<typeof readdirSync>;
	try {
		entries = readdirSync(dir, { withFileTypes: true });
	} catch {
		return [];
	}

	const definitions: SubagentDefinition[] = [];
	for (const entry of entries) {
		if (!entry.isFile() || !entry.name.endsWith(".md")) continue;
		const filePath = join(dir, entry.name);
		try {
			const parsed = parseFrontmatter<SubagentFrontmatter>(readFileSync(filePath, "utf8"));
			const frontmatter = parsed.frontmatter;
			const name =
				typeof frontmatter.name === "string" && frontmatter.name.trim()
					? frontmatter.name.trim()
					: basename(entry.name, ".md");
			definitions.push({
				name,
				description: typeof frontmatter.description === "string" ? frontmatter.description : "",
				tools: parseToolsField(frontmatter.tools),
				model:
					typeof frontmatter.model === "string" && frontmatter.model.trim()
						? frontmatter.model.trim()
						: undefined,
				systemPrompt: parsed.body,
				filePath,
			});
		} catch {
			// Skip unreadable/invalid files
		}
	}
	return definitions;
}

function loadSubagentDefinitions(cwd: string, agentDir: string): SubagentDefinition[] {
	const dirs = [
		join(cwd, ".pi", "agents"),
		join(cwd, ".claude", "agents"),
		join(agentDir, "agents"),
		join(homedir(), ".claude", "agents"),
	];
	const byName = new Map<string, SubagentDefinition>();
	for (const dir of dirs) {
		for (const def of loadDefinitionsFromDir(dir)) {
			if (!byName.has(def.name)) byName.set(def.name, def);
		}
	}
	return [...byName.values()];
}

interface TextContentBlock {
	type: unknown;
	text?: unknown;
}

function extractFinalAssistantText(messages: readonly unknown[]): string | undefined {
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i];
		if (!message || typeof message !== "object") continue;
		const record = message as { role?: unknown; content?: unknown };
		if (record.role !== "assistant" || !Array.isArray(record.content)) continue;
		const text = (record.content as TextContentBlock[])
			.filter((block) => block && block.type === "text" && typeof block.text === "string")
			.map((block) => block.text as string)
			.join("\n")
			.trim();
		if (text) return text;
	}
	return undefined;
}

let cachedModelRuntime: ModelRuntime | undefined;

async function getModelRuntime(): Promise<ModelRuntime> {
	if (!cachedModelRuntime) {
		cachedModelRuntime = await ModelRuntime.create();
	}
	return cachedModelRuntime;
}

async function runSubagent(
	definition: SubagentDefinition,
	prompt: string,
	cwd: string,
	signal: AbortSignal | undefined,
): Promise<string> {
	const agentDir = getAgentDir();

	let model: CreateAgentSessionOptions["model"];
	let modelRuntime: ModelRuntime | undefined;
	if (definition.model) {
		modelRuntime = await getModelRuntime();
		const resolved = resolveCliModel({ cliModel: definition.model, modelRuntime });
		if (resolved.error || !resolved.model) {
			throw new Error(`Unknown model "${definition.model}" for agent "${definition.name}": ${resolved.error}`);
		}
		model = resolved.model;
	}

	const resourceLoader = new DefaultResourceLoader({
		cwd,
		agentDir,
		noExtensions: true,
		noSkills: true,
		noPromptTemplates: true,
		noThemes: true,
		systemPromptOverride: () => definition.systemPrompt,
		appendSystemPromptOverride: () => [],
	});
	await resourceLoader.reload();

	const { session } = await createAgentSession({
		cwd,
		agentDir,
		resourceLoader,
		sessionManager: SessionManager.inMemory(cwd),
		model,
		modelRuntime,
		tools: definition.tools,
		excludeTools: ["task"],
	});

	const onAbort = () => {
		void session.abort();
	};
	signal?.addEventListener("abort", onAbort, { once: true });

	try {
		await session.prompt(prompt);
		await session.waitForIdle();
	} finally {
		signal?.removeEventListener("abort", onAbort);
		session.dispose();
	}

	const text = extractFinalAssistantText(session.messages);
	if (!text) {
		throw new Error(`Subagent "${definition.name}" finished without producing any text output.`);
	}
	return text;
}

export default function subagentExtension(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (!ctx.isProjectTrusted()) return;

		const definitions = loadSubagentDefinitions(ctx.cwd, getAgentDir());
		if (definitions.length === 0) return;

		const byName = new Map(definitions.map((def) => [def.name, def]));
		const catalog = definitions
			.map((def) => `- ${def.name}: ${def.description || "(no description)"}`)
			.join("\n");

		pi.registerTool({
			name: "task",
			label: "Task",
			description: `Delegate a task to a specialized subagent. The subagent runs in an isolated context with its own instructions and tool set; only its final answer is returned.\n\nAvailable agents:\n${catalog}`,
			parameters: Type.Object({
				agent: Type.String({
					description: "The agent to run",
					enum: definitions.map((def) => def.name),
				}),
				prompt: Type.String({ description: "Complete, self-contained task description for the subagent" }),
			}),
			async execute(_toolCallId, params, signal, onUpdate, ctx) {
				const definition = byName.get(params.agent);
				if (!definition) {
					throw new Error(
						`Unknown agent "${params.agent}". Available: ${[...byName.keys()].join(", ")}`,
					);
				}
				onUpdate?.({
					content: [{ type: "text", text: `Running ${definition.name}...` }],
					details: { agent: definition.name },
				});
				const text = await runSubagent(definition, params.prompt, ctx.cwd, signal ?? ctx.signal);
				return {
					content: [{ type: "text", text }],
					details: { agent: definition.name },
				};
			},
		});
	});
}
