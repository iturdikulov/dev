/**
 * Minimal subagent extension (локальный форк @jerryan/pi-subagent-lite v0.2.0)
 *
 * Delegates a task to a fresh pi process with an isolated context window.
 * Optionally loads startup skills via --skill flags.
 *
 * Дополнения форка:
 * - лог каждого субагента в $TMPDIR/pi-subagent-logs/<время>-<id>.log (+ сырой .jsonl);
 * - команда /subagents [id] — выбор субагента и live-просмотр его хода работы;
 * - счётчик работающих субагентов в футере.
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { Message } from "@earendil-works/pi-ai";
import type { AgentToolResult, ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text, truncateToWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { Type } from "typebox";

const MAX_TASK_ARG_LENGTH = 4000;
// Персональный каталог: в общем /tmp чужой пользователь мог бы подсунуть симлинки
const LOG_DIR = path.join(os.tmpdir(), `pi-subagent-logs-${os.userInfo().uid}`);
const LOG_TTL_MS = 7 * 24 * 60 * 60 * 1000;
// Сколько записей истории держим в памяти на субагента (в файле — всё)
const MAX_HISTORY = 2000;
const STATUS_KEY = "subagents";
const RAW_SKIP_EVENTS = new Set(["message_update", "tool_execution_update", "message_start", "agent_end"]);

const MINIMAL_SYSTEM_PROMPT = `You are a subagent running in an isolated pi process with access to file system and shell tools.

Your job is to focus exclusively on the assigned task, use tools as needed, and provide a clear, concise report or summary at the end.

Guidelines:
- Stay focused on the task. Do not drift into unrelated work.
- Be concise, but include enough detail for the parent agent to act on your findings.
- End with a clear summary or conclusion.`;

type RunStatus = "running" | "done" | "error" | "aborted";
type EntryKind = "turn" | "text" | "tool" | "error" | "info";

interface HistoryEntry {
	time: number;
	kind: EntryKind;
	text: string;
}

interface SubagentRun {
	id: number;
	task: string;
	skills: string[];
	startedAt: number;
	endedAt?: number;
	status: RunStatus;
	turns: number;
	pid?: number;
	currentTool?: string;
	cost: number;
	contextTokens: number;
	history: HistoryEntry[];
	logFile: string;
	rawFile: string;
}

// Реестр запусков живёт в памяти текущего процесса pi
const runs = new Map<number, SubagentRun>();
const listeners = new Set<() => void>();
let nextRunId = 1;
let statusUi: ExtensionContext["ui"] | undefined;

// Ошибки UI (например, устаревший ctx после /new) не должны ломать сам запуск
function notifyListeners(): void {
	for (const listener of listeners) {
		try {
			listener();
		} catch {
			/* ignore */
		}
	}
}

function updateFooter(): void {
	if (!statusUi) return;
	const running = [...runs.values()].filter((r) => r.status === "running").length;
	try {
		statusUi.setStatus(STATUS_KEY, running > 0 ? `⚙ subagents: ${running} (/subagents)` : undefined);
	} catch {
		statusUi = undefined;
	}
}

async function ensureLogDir(): Promise<void> {
	await fs.promises.mkdir(LOG_DIR, { recursive: true, mode: 0o700 });
	const st = await fs.promises.lstat(LOG_DIR);
	if (!st.isDirectory() || st.uid !== os.userInfo().uid) {
		throw new Error(`Unsafe subagent log dir: ${LOG_DIR}`);
	}
}

// Удаляем логи старше LOG_TTL_MS
async function cleanupOldLogs(): Promise<void> {
	try {
		const now = Date.now();
		for (const name of await fs.promises.readdir(LOG_DIR)) {
			const file = path.join(LOG_DIR, name);
			const st = await fs.promises.lstat(file);
			if (st.isFile() && now - st.mtimeMs > LOG_TTL_MS) await fs.promises.rm(file, { force: true });
		}
	} catch {
		/* каталога ещё нет — нечего чистить */
	}
}

function formatDuration(ms: number): string {
	const total = Math.max(0, Math.floor(ms / 1000));
	const m = Math.floor(total / 60);
	const s = total % 60;
	return m > 0 ? `${m}m${String(s).padStart(2, "0")}s` : `${s}s`;
}

function formatClock(time: number): string {
	return new Date(time).toTimeString().slice(0, 8);
}

function oneLine(text: string, max: number): string {
	const flat = text.replace(/\s+/g, " ").trim();
	return flat.length > max ? flat.slice(0, max) + "..." : flat;
}

// Короткое описание аргументов вызова инструмента
function describeArgs(args: any): string {
	if (!args || typeof args !== "object") return "";
	const key = ["command", "path", "file_path", "pattern", "query", "url", "task"].find(
		(k) => typeof args[k] === "string",
	);
	if (key) return oneLine(args[key], 160);
	try {
		return oneLine(JSON.stringify(args), 160);
	} catch {
		return "";
	}
}

function runElapsed(run: SubagentRun): number {
	return (run.endedAt ?? Date.now()) - run.startedAt;
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	if (currentScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}
	const execName = path.basename(process.execPath).toLowerCase();
	const isGenericRuntime = /^(node|bun)(\.exe)?$/.test(execName);
	if (!isGenericRuntime) {
		return { command: process.execPath, args };
	}
	return { command: "pi", args };
}

async function runSubagent(
	cwd: string,
	task: string,
	skills: string[],
	signal?: AbortSignal,
	onUpdate?: (result: AgentToolResult) => void,
): Promise<string> {
	const args: string[] = ["--mode", "json", "-p", "--no-session"];

	for (const skill of skills) {
		args.push("--skill", skill);
	}

	const id = nextRunId++;
	await ensureLogDir();
	const stamp = new Date().toISOString().replace(/[:.]/g, "-");
	const base = path.join(LOG_DIR, `${stamp}-${process.pid}-${id}`);
	const run: SubagentRun = {
		id,
		task,
		skills,
		startedAt: Date.now(),
		status: "running",
		turns: 0,
		cost: 0,
		contextTokens: 0,
		history: [],
		logFile: `${base}.log`,
		rawFile: `${base}.jsonl`,
	};
	runs.set(id, run);
	const logStream = fs.createWriteStream(run.logFile, { flags: "wx", mode: 0o600 });
	const rawStream = fs.createWriteStream(run.rawFile, { flags: "wx", mode: 0o600 });
	// Ошибки записи лога не должны ронять субагента
	logStream.on("error", () => {});
	rawStream.on("error", () => {});

	const record = (kind: EntryKind, text: string) => {
		// После finish() потоки закрыты — поздние события игнорируем
		if (run.status !== "running") return;
		const entry: HistoryEntry = { time: Date.now(), kind, text };
		run.history.push(entry);
		if (run.history.length > MAX_HISTORY) run.history.splice(0, run.history.length - MAX_HISTORY);
		logStream.write(`[${formatClock(entry.time)}] ${kind.toUpperCase().padEnd(5)} ${text}\n`);
		notifyListeners();
	};

	const finish = (status: RunStatus, note: string) => {
		if (run.status !== "running") return;
		record(status === "done" ? "info" : "error", note);
		run.status = status;
		run.endedAt = Date.now();
		run.currentTool = undefined;
		logStream.end();
		rawStream.end();
		updateFooter();
		notifyListeners();
	};

	record("info", `task: ${task}`);
	if (skills.length > 0) record("info", `skills: ${skills.join(", ")}`);
	updateFooter();

	let tmpDir: string | null = null;

	try {
		onUpdate?.({ content: [{ type: "text", text: `Subagent #${id} running... (/subagents ${id})` }] });

		tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "pi-subagent-"));
		const promptFile = path.join(tmpDir, "prompt.md");
		await fs.promises.writeFile(promptFile, MINIMAL_SYSTEM_PROMPT, { encoding: "utf-8", mode: 0o600 });
		args.push("--append-system-prompt", promptFile);

		if (task.length > MAX_TASK_ARG_LENGTH) {
			const taskFile = path.join(tmpDir, "task.md");
			await fs.promises.writeFile(taskFile, task, { encoding: "utf-8", mode: 0o600 });
			args.push(`Task: Please read ${taskFile} and follow the instructions there.`);
		} else {
			args.push(`Task: ${task}`);
		}

		const invocation = getPiInvocation(args);
		const proc = spawn(invocation.command, invocation.args, {
			cwd,
			shell: false,
			stdio: ["ignore", "pipe", "pipe"],
			env: { ...process.env, PI_SUBAGENT_LITE_DISABLE: "true" },
		});
		run.pid = proc.pid;
		record("info", `pid ${proc.pid}, log ${run.logFile}`);

		let buffer = "";
		let stderr = "";
		const messages: Message[] = [];

		const processLine = (line: string) => {
			if (!line.trim()) return;
			let event: any;
			try {
				event = JSON.parse(line);
			} catch {
				return;
			}
			// Дельты, частичный вывод и дубли message_end (message_start, agent_end) не пишем — они раздувают файл
			if (!RAW_SKIP_EVENTS.has(event.type)) rawStream.write(line + "\n");

			if (event.type === "tool_execution_start") {
				run.currentTool = `${event.toolName} ${describeArgs(event.args)}`.trim();
				notifyListeners();
				return;
			}
			if (event.type === "tool_execution_end") {
				run.currentTool = undefined;
				if (event.isError) {
					const errText = (event.result?.content ?? [])
						.filter((c: any) => c.type === "text")
						.map((c: any) => c.text)
						.join("");
					record("error", `${event.toolName} failed: ${oneLine(errText, 300)}`);
				} else {
					notifyListeners();
				}
				return;
			}
			if (event.type === "message_end" && event.message) {
				const msg = event.message as Message & { content: any[]; usage?: any };
				messages.push(msg);
				if (msg.role !== "assistant") return;

				run.turns++;
				if (msg.usage) {
					run.cost += msg.usage.cost?.total ?? 0;
					run.contextTokens = msg.usage.totalTokens ?? run.contextTokens;
				}
				const toolCalls = (msg.content ?? []).filter((c: any) => c.type === "toolCall");
				const textParts = (msg.content ?? [])
					.filter((c: any) => c.type === "text")
					.map((c: any) => c.text)
					.join("");

				record("turn", `Turn ${run.turns}`);
				if (textParts.trim()) record("text", textParts.trim());
				for (const c of toolCalls) record("tool", `${c.name} ${describeArgs(c.arguments)}`.trim());

				if (onUpdate) {
					let updateText = "";
					if (toolCalls.length > 0) {
						const counts = new Map<string, number>();
						for (const c of toolCalls) counts.set(c.name, (counts.get(c.name) || 0) + 1);
						const toolsStr = Array.from(counts.entries())
							.map(([name, count]) => (count > 1 ? `${name} (x${count})` : name))
							.join(", ");
						updateText = `#${id} Turn ${run.turns}: ${toolsStr}`;
					} else {
						updateText = `#${id} Turn ${run.turns}: thinking...`;
					}
					if (textParts) {
						const preview = textParts.length > 60 ? textParts.slice(0, 60) + "..." : textParts;
						updateText += `\n${preview}`;
					}
					onUpdate({ content: [{ type: "text", text: updateText }] });
				}
			}
		};

		proc.stdout.on("data", (data) => {
			buffer += data.toString();
			const lines = buffer.split("\n");
			buffer = lines.pop() || "";
			for (const line of lines) processLine(line);
		});

		proc.stderr.on("data", (data) => {
			stderr += data.toString();
		});

		let spawnError = "";
		let killTimer: NodeJS.Timeout | undefined;
		const exitCode = await new Promise<number>((resolve) => {
			const onAbort = () => {
				proc.kill("SIGTERM");
				// proc.killed становится true сразу после SIGTERM, поэтому смотрим на фактический выход
				killTimer = setTimeout(() => {
					if (proc.exitCode === null && proc.signalCode === null) proc.kill("SIGKILL");
				}, 5000);
				killTimer.unref();
			};

			if (signal?.aborted) {
				onAbort();
			} else {
				signal?.addEventListener("abort", onAbort, { once: true });
			}

			proc.on("close", (code, sig) => {
				signal?.removeEventListener("abort", onAbort);
				clearTimeout(killTimer);
				if (buffer.trim()) processLine(buffer);
				// Убитый сигналом процесс (code === null) — это ошибка, а не успех
				if (sig) spawnError = spawnError || `Subagent killed by ${sig}`;
				resolve(sig ? 128 + (os.constants.signals[sig] ?? 0) : (code ?? 1));
			});
			proc.on("error", (err) => {
				signal?.removeEventListener("abort", onAbort);
				clearTimeout(killTimer);
				spawnError = err.message;
				resolve(1);
			});
		});

		if (signal?.aborted) throw new Error("Subagent aborted");

		if (exitCode !== 0) {
			throw new Error(stderr || spawnError || `Subagent exited with code ${exitCode}`);
		}

		finish("done", `finished in ${formatDuration(runElapsed(run))}`);

		for (let i = messages.length - 1; i >= 0; i--) {
			const msg = messages[i];
			if (msg.role === "assistant") {
				for (const part of msg.content) {
					if (part.type === "text") return part.text ?? "";
				}
			}
		}

		return "";
	} catch (err: any) {
		if (run.status === "running") {
			const aborted = signal?.aborted ?? false;
			finish(aborted ? "aborted" : "error", aborted ? "aborted" : `error: ${err?.message ?? err}`);
		}
		throw err;
	} finally {
		if (tmpDir) {
			try {
				await fs.promises.rm(tmpDir, { recursive: true, force: true });
			} catch {
				/* ignore */
			}
		}
	}
}

const STATUS_ICON: Record<RunStatus, string> = { running: "●", done: "✓", error: "✗", aborted: "■" };

function runLabel(run: SubagentRun): string {
	return `#${run.id} ${STATUS_ICON[run.status]} ${run.status} ${formatDuration(runElapsed(run))} T${run.turns} — ${oneLine(run.task, 70)}`;
}

function sortedRuns(): SubagentRun[] {
	// Сначала работающие, затем самые свежие
	return [...runs.values()].sort((a, b) => {
		if ((a.status === "running") !== (b.status === "running")) return a.status === "running" ? -1 : 1;
		return b.id - a.id;
	});
}

function textSummary(run: SubagentRun): string {
	const lines = [runLabel(run), `log: ${run.logFile}`];
	if (run.currentTool) lines.push(`now: ${run.currentTool}`);
	const last = run.history.slice(-5).map((e) => `[${formatClock(e.time)}] ${oneLine(e.text, 120)}`);
	return [...lines, ...last].join("\n");
}

// Live-просмотр одного субагента; возвращается по Esc/q/Enter
async function showRunViewer(run: SubagentRun, ctx: ExtensionContext): Promise<void> {
	await ctx.ui.custom<void>((tui, theme, keybindings, done) => {
		// null — следим за концом истории
		let scrollTop: number | null = null;
		let lastMaxTop = 0;
		let lastPage = 10;

		const onChange = () => tui.requestRender();
		listeners.add(onChange);
		// Тикаем раз в секунду, чтобы обновлялось время работы
		const timer = setInterval(() => {
			if (run.status === "running") tui.requestRender();
		}, 1000);
		let closed = false;
		const close = () => {
			if (closed) return;
			closed = true;
			listeners.delete(onChange);
			clearInterval(timer);
			done();
		};

		const styleEntry = (e: HistoryEntry): string => {
			const clock = theme.fg("dim", formatClock(e.time));
			switch (e.kind) {
				case "turn":
					return `${clock} ${theme.fg("accent", theme.bold(`── ${e.text} ──`))}`;
				case "tool":
					return `${clock} ${theme.fg("toolTitle", "→ ")}${e.text}`;
				case "error":
					return `${clock} ${theme.fg("error", e.text)}`;
				case "info":
					return `${clock} ${theme.fg("muted", e.text)}`;
				default:
					return `${clock} ${e.text}`;
			}
		};

		return {
			render(width: number): string[] {
				const statusColor =
					run.status === "running" ? "warning" : run.status === "done" ? "success" : "error";
				const header = [
					theme.fg("accent", theme.bold(`Subagent #${run.id}`)) +
						" " +
						theme.fg(statusColor, `${STATUS_ICON[run.status]} ${run.status}`) +
						theme.fg(
							"muted",
							`  ${formatDuration(runElapsed(run))}  turns ${run.turns}  ctx ${run.contextTokens}  $${run.cost.toFixed(3)}` +
								(run.pid ? `  pid ${run.pid}` : ""),
						),
					theme.fg("dim", `task: ${oneLine(run.task, 400)}`),
					theme.fg("dim", `log:  ${run.logFile}`),
					run.currentTool
						? theme.fg("warning", `now:  ${run.currentTool}`)
						: theme.fg("dim", run.status === "running" ? "now:  thinking..." : "now:  —"),
					theme.fg("borderMuted", "─".repeat(Math.max(1, width))),
				];

				const body: string[] = [];
				for (const e of run.history) body.push(...wrapTextWithAnsi(styleEntry(e), width));

				const footer = theme.fg("dim", "↑/↓ scroll  PgUp/PgDn page  Home/End  Esc/q back");
				const rows = tui.terminal.rows;
				const page = Math.max(5, Math.floor(rows * 0.75) - header.length - 1);
				const maxTop = Math.max(0, body.length - page);
				lastMaxTop = maxTop;
				lastPage = page;
				const top = scrollTop === null ? maxTop : Math.min(scrollTop, maxTop);
				const visible = body.slice(top, top + page);
				const position = body.length > page ? theme.fg("dim", `  [${top + visible.length}/${body.length}]`) : "";

				return [...header, ...visible, footer + position].map((line) => truncateToWidth(line, width));
			},
			handleInput(data: string): void {
				const current = scrollTop ?? lastMaxTop;
				const scrollTo = (value: number) => {
					const clamped = Math.max(0, Math.min(value, lastMaxTop));
					scrollTop = clamped >= lastMaxTop ? null : clamped;
					tui.requestRender();
				};
				if (keybindings.matches(data, "tui.select.cancel") || keybindings.matches(data, "tui.select.confirm") || data === "q") {
					close();
				} else if (keybindings.matches(data, "tui.select.up") || data === "k") {
					scrollTo(current - 1);
				} else if (keybindings.matches(data, "tui.select.down") || data === "j") {
					scrollTo(current + 1);
				} else if (keybindings.matches(data, "tui.select.pageUp")) {
					scrollTo(current - lastPage);
				} else if (keybindings.matches(data, "tui.select.pageDown")) {
					scrollTo(current + lastPage);
				} else if (data === "g" || data === "\x1b[H" || data === "\x1b[1~") {
					scrollTo(0);
				} else if (data === "G" || data === "\x1b[F" || data === "\x1b[4~") {
					scrollTo(lastMaxTop);
				}
			},
			invalidate() {},
			dispose: close,
		};
	});
}

const SubagentParams = Type.Object({
	task: Type.String({ description: "Task to delegate to the subagent" }),
	skills: Type.Optional(
		Type.Array(Type.String({ description: "Skill path or name to load via --skill" }), {
			description: "Optional startup skills to load into the subagent process",
		}),
	),
});

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_LITE_DISABLE === "true") {
		return;
	}

	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: "Delegate tasks to fresh pi subagents with isolated context windows. You may invoke multiple subagents in parallel via separate tool calls. Each subagent returns a concise summary or report when its work is done. Optional startup skills can be preloaded.",
		promptSnippet: "Delegate a task to an isolated subagent process",
		promptGuidelines: [
			"Delegate non-trivial, self-contained tasks to subagents so you can stay focused on the overall picture.",
		],
		parameters: SubagentParams,

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			if (ctx.hasUI) statusUi = ctx.ui;
			try {
				const output = await runSubagent(ctx.cwd, params.task, params.skills ?? [], signal, onUpdate);
				return {
					content: [{ type: "text", text: output || "(no output)" }],
				};
			} catch (err: any) {
				return {
					content: [{ type: "text", text: err.message || String(err) }],
					isError: true,
				};
			}
		},

		renderCall(args, theme) {
			const taskPreview = args.task.length > 60 ? args.task.slice(0, 60) + "..." : args.task;
			let text = theme.fg("toolTitle", theme.bold("subagent ")) + theme.fg("dim", taskPreview);
			const skillsArr = args.skills ?? [];
			if (skillsArr.length > 0) {
				text += ` ${theme.fg("accent", `+${skillsArr.length} skills`)}`;
			}
			return new Text(text, 0, 0);
		},

		renderResult(result, options, theme, context) {
			const output = result.content.find((c) => c.type === "text")?.text ?? "";
			if (options.isPartial) {
				return new Text(theme.fg("muted", output || "Subagent running..."), 0, 0);
			}
			const marker = context.isError ? theme.fg("error", "✗ ") : theme.fg("success", "✓ ");
			const separator = theme.fg("muted", "--- Result ---");
			const text = `${marker}${separator}\n${output}`;
			return new Text(text, 0, 0);
		},
	});

	pi.registerCommand("subagents", {
		description: "Show subagent status: /subagents [id]",
		getArgumentCompletions: (prefix: string) => {
			const items = sortedRuns()
				.map((r) => ({ value: String(r.id), label: String(r.id), description: runLabel(r) }))
				.filter((i) => i.value.startsWith(prefix.trim()));
			return items.length > 0 ? items : null;
		},
		handler: async (args, ctx) => {
			if (runs.size === 0) {
				ctx.ui.notify("Субагенты в этой сессии ещё не запускались", "info");
				return;
			}

			const requested = args.trim();
			if (requested) {
				const run = runs.get(Number(requested));
				if (!run) {
					ctx.ui.notify(`Нет субагента #${requested}`, "error");
					return;
				}
				if (ctx.mode === "tui") await showRunViewer(run, ctx);
				else ctx.ui.notify(textSummary(run), "info");
				return;
			}

			if (ctx.mode !== "tui") {
				ctx.ui.notify(sortedRuns().map(runLabel).join("\n"), "info");
				return;
			}

			// Список → просмотр → обратно в список, пока не нажат Esc в списке
			while (true) {
				const list = sortedRuns();
				const labels = list.map(runLabel);
				const choice = await ctx.ui.select("Субагенты:", labels);
				if (choice === undefined) return;
				const run = list[labels.indexOf(choice)];
				if (!run) return;
				await showRunViewer(run, ctx);
			}
		},
	});

	// После /new, /resume, /reload возвращаем счётчик в футер нового ctx
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.hasUI) {
			statusUi = ctx.ui;
			updateFooter();
		}
		void cleanupOldLogs();
	});

	pi.on("session_shutdown", async () => {
		statusUi?.setStatus(STATUS_KEY, undefined);
		statusUi = undefined;
	});
}
