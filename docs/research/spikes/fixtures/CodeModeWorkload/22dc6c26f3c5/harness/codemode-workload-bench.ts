/**
 * Memoshi Code Mode workload: Node-oracle baseline for W1 and W2 at upstream 22dc6c26f3c5, for the D89/D90 record
 * docs/research/spikes/2026-11-02-code-mode-workload.md. Copy this file into packages/durable/test/ of the prepared
 * oracle worktree; it uses the imports of that worktree's test/codemode-bench.ts. Not executed when the record was
 * authored. Node timings are VERIFICATION §5's baseline, never reference-device evidence.
 *
 *   node --conditions=source --experimental-strip-types test/codemode-workload-bench.ts \
 *     --fixture <fixture-root> --workload W1 [--launches 10] > w1-node.jsonl
 *
 * Driver mode starts one child process per launch (`--launch <k>`), so every cold sample is a fresh process.
 */
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { BACKGROUND_CONTEXT as context, type Context } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai/models";
import { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { CodemodeSandbox } from "@earendil-works/pi-codemode";
import { Type } from "typebox";
import { createCodemodeTool } from "../src/codemode/codemode.ts";
import {
	createRegistry,
	defineExtension,
	defineTool,
	Harness,
	hook,
	type ToolExecutionApi,
	type ToolExecutionResult,
	ToolTask,
} from "../src/index.ts";
import { openNodeSqliteStorage } from "../src/storage/sqlite/node.ts";

// Deterministic fixture tools: the same generators as scenario.json and MemoshiRuntime's Qualification/CodeModeWorkload.swift.
const REPO = "memoshi/fixture";
const pad = (value: number, width: number) => String(value).padStart(width, "0");
const FILE_PATHS = Array.from({ length: 10 }, (_, index) => `Sources/Module${pad(index + 1, 2)}/File${pad(index + 1, 2)}.swift`);

function issuesList(repo: string, state: string, limit: number): string | undefined {
	if (repo !== REPO || state !== "open" || !Number.isInteger(limit) || limit < 1 || limit > 9) return undefined;
	const items = Array.from({ length: limit }, (_, offset) => ({ number: 100 + limit - offset, title: `Fixture issue ${100 + limit - offset}` }));
	return JSON.stringify({ repo, state: "open", items });
}

function issueBody(number: number): string {
	const lines = ["## Summary"];
	for (let paragraph = 1; paragraph <= 24; paragraph++) {
		lines.push(`Paragraph ${pad(paragraph, 2)} of issue ${number}: the fixture text repeats until the body reaches its target size.`);
	}
	lines.push("## Tasks");
	for (let task = 1; task <= 8; task++) lines.push(`${task <= number % 5 ? "- [x] " : "- [ ] "}Task ${task} for issue ${number}`);
	return lines.join("\n");
}

function issueGet(repo: string, number: number): string | undefined {
	if (repo !== REPO || !Number.isInteger(number) || number < 101 || number > 109) return undefined;
	const index = number - 100;
	return JSON.stringify({
		number,
		title: `Fixture issue ${number}`,
		state: "open",
		author: `author-${(number % 3) + 1}`,
		labels: ["fixture", number % 2 === 0 ? "bug" : "feature", ...(number % 4 === 0 ? ["ui"] : [])],
		createdAt: `2026-10-${pad(10 + index, 2)}T09:00:00Z`,
		updatedAt: `2026-11-${pad(((index * 3) % 4) + 1, 2)}T${pad(10 + index, 2)}:00:00Z`,
		comments: number % 9,
		body: issueBody(number),
	});
}

function codeSearch(query: string, path: string, maxResults: number): string | undefined {
	if (query !== "TODO(memoshi)" || path !== "Sources" || !Number.isInteger(maxResults) || maxResults < 1 || maxResults > 10) return undefined;
	return JSON.stringify({ query, matches: FILE_PATHS.slice(0, maxResults).map((file) => ({ path: file, line: 25 })) });
}

function fileRead(path: string): string | undefined {
	const position = FILE_PATHS.indexOf(path);
	if (position < 0) return undefined;
	const module = pad(position + 1, 2);
	let text = "";
	for (let line = 1; line <= 1000; line++) {
		const number = pad(line, 4);
		text += line % 25 === 0 ? `// TODO(memoshi): item ${module}-${number} review needed.\n` : `let v${module}_${number} = ${number} + ${module} // fixture code line\n`;
	}
	return text;
}

function symbolsOutline(paths: string[]): string | undefined {
	if (paths.length < 1 || paths.length > 10 || paths.some((path) => !FILE_PATHS.includes(path))) return undefined;
	return JSON.stringify({
		files: paths.map((path) => {
			const module = pad(FILE_PATHS.indexOf(path) + 1, 2);
			return { path, symbols: 960, firstSymbol: `v${module}_0001`, lastSymbol: `v${module}_0999` };
		}),
	});
}

// One result shape for every fixture tool; an unexpected request fails the nested call, which fails verification.
const answer = (tool: string, value: string | undefined) =>
	value === undefined
		? { output: [{ type: "text" as const, text: `fixture: unexpected ${tool} request` }], isError: true }
		: { output: [{ type: "text" as const, text: value }] };

const fixtureTools = [
	defineTool({
		name: "issues_list",
		description: "List open issues in a fixture repository, newest first.",
		parameters: Type.Object({ repo: Type.String(), state: Type.String(), limit: Type.Integer() }),
		replay: "safe",
		callers: ["tools"],
		execute: async (args) => answer("issues_list", issuesList(args.repo, args.state, args.limit)),
	}),
	defineTool({
		name: "issue_get",
		description: "Read one fixture issue as JSON.",
		parameters: Type.Object({ repo: Type.String(), number: Type.Integer() }),
		replay: "safe",
		callers: ["tools"],
		execute: async (args) => answer("issue_get", issueGet(args.repo, args.number)),
	}),
	defineTool({
		name: "code_search",
		description: "Search fixture sources for a literal string.",
		parameters: Type.Object({ query: Type.String(), path: Type.String(), maxResults: Type.Integer() }),
		replay: "safe",
		callers: ["tools"],
		execute: async (args) => answer("code_search", codeSearch(args.query, args.path, args.maxResults)),
	}),
	defineTool({
		name: "file_read",
		description: "Read one fixture source file.",
		parameters: Type.Object({ path: Type.String() }),
		replay: "safe",
		callers: ["tools"],
		execute: async (args) => answer("file_read", fileRead(args.path)),
	}),
	defineTool({
		name: "symbols_outline",
		description: "Summarize the symbols of fixture source files.",
		parameters: Type.Object({ paths: Type.Array(Type.String()) }),
		replay: "safe",
		callers: ["tools"],
		execute: async (args) => answer("symbols_outline", symbolsOutline(args.paths)),
	}),
];

type Execution = { ms: number; result?: ToolExecutionResult; error?: string };
type ExpectedWorkload = { script: string; result: string; nestedCalls: number; callsByTool: Record<string, number>; hookDecisions: number };
type NestedCall = { name: string; status: string };

// expected.json is this fixture's own file, but it is still parsed input: check the fields the baseline reads.
function expectedWorkload(file: unknown, workload: string): ExpectedWorkload {
	const entry = file && typeof file === "object" && "workloads" in file && file.workloads && typeof file.workloads === "object" && workload in file.workloads
		? (file.workloads as Record<string, unknown>)[workload]
		: undefined;
	if (
		!entry || typeof entry !== "object" ||
		!("script" in entry) || typeof entry.script !== "string" ||
		!("result" in entry) || typeof entry.result !== "string" ||
		!("nestedCalls" in entry) || typeof entry.nestedCalls !== "number" ||
		!("hookDecisions" in entry) || typeof entry.hookDecisions !== "number" ||
		!("callsByTool" in entry) || !entry.callsByTool || typeof entry.callsByTool !== "object" ||
		!Object.values(entry.callsByTool).every((count) => typeof count === "number")
	) {
		throw new Error(`expected.json has no complete ${workload} entry`);
	}
	return {
		script: entry.script,
		result: entry.result,
		nestedCalls: entry.nestedCalls,
		hookDecisions: entry.hookDecisions,
		callsByTool: entry.callsByTool as Record<string, number>, // every value was checked as a number above
	};
}

// The durable codemode tool reports `details: { calls: CodemodeNestedCall[] }`; its declared type is JsonValue.
function nestedCalls(details: unknown): NestedCall[] {
	if (!details || typeof details !== "object" || !("calls" in details) || !Array.isArray(details.calls)) return [];
	return details.calls.flatMap((call: unknown) =>
		call && typeof call === "object" && "name" in call && typeof call.name === "string" && "status" in call && typeof call.status === "string"
			? [{ name: call.name, status: call.status }]
			: [],
	);
}

function verify(execution: Execution | undefined, expected: ExpectedWorkload, decisions: number): { verified: boolean; verification: string } {
	if (!execution) return { verified: false, verification: "the codemode tool did not execute" };
	if (!execution.result) return { verified: false, verification: `codemode threw: ${execution.error}` };
	const texts = (execution.result.output ?? []).flatMap((block) => (block.type === "text" ? [block.text] : []));
	if (execution.result.isError) return { verified: false, verification: `script failed: ${texts.join(" | ")}` };
	if (texts.at(-1) !== expected.result) return { verified: false, verification: "result differs from expected.json" };
	const calls = nestedCalls(execution.result.details);
	if (calls.length !== expected.nestedCalls || calls.some((call) => call.status !== "ok")) {
		return { verified: false, verification: `${calls.length} nested calls or a call not ok; expected ${expected.nestedCalls} ok` };
	}
	const byTool: Record<string, number> = {};
	for (const call of calls) byTool[call.name] = (byTool[call.name] ?? 0) + 1;
	const sameCounts = Object.keys(expected.callsByTool).length === Object.keys(byTool).length &&
		Object.entries(expected.callsByTool).every(([name, count]) => byTool[name] === count);
	if (!sameCounts) return { verified: false, verification: `nested calls by tool ${JSON.stringify(byTool)}` };
	if (decisions !== expected.hookDecisions) return { verified: false, verification: `${decisions} policy decisions, expected ${expected.hookDecisions}` };
	return { verified: true, verification: "matched expected.json" };
}

async function runLaunch(fixture: string, workload: string, launchIndex: number) {
	if (workload !== "W1" && workload !== "W2") throw new Error("The Node baseline covers W1 and W2 only");
	const expected = expectedWorkload(JSON.parse(await readFile(join(fixture, "expected.json"), "utf8")), workload);
	const code = await readFile(join(fixture, expected.script), "utf8");
	const directory = await mkdtemp(join(tmpdir(), "memoshi-codemode-"));
	let decisions = 0;
	let commits = 0;
	const executions: Execution[] = [];
	try {
		const faux = fauxProvider();
		const models = createModels();
		models.setProvider(faux.provider);
		const registry = createRegistry();
		registry.install(defineExtension({ name: "fixture.tools", tools: fixtureTools }));
		registry.install(
			defineExtension({
				name: "fixture.policy",
				hooks: [
					hook(ToolTask, {
						beforeTool: () => {
							decisions++;
							return undefined;
						},
						afterTool: () => undefined,
					}),
				],
			}),
		);
		const storage = await openNodeSqliteStorage(join(directory, "session.sqlite"));
		const harness = await Harness.open(storage, { models, registry, settings: {} }, context);
		const root = await harness.root(context, { agent: { model: { provider: "faux", modelId: "faux-1" } } });
		harness.subscribeCommits(() => {
			commits++;
		});
		await sleep(2000);

		const initStarted = performance.now();
		const sandbox = new CodemodeSandbox({ memoryLimitBytes: 268435456 });
		const base = createCodemodeTool({ sandbox, models: false });
		const timed = {
			...base,
			execute: async (args: { code: string }, api: ToolExecutionApi, callContext: Context) => {
				const started = performance.now();
				try {
					const result = await base.execute(args, api, callContext);
					executions.push({ ms: performance.now() - started, result });
					return result;
				} catch (error) {
					executions.push({ ms: performance.now() - started, error: String(error) });
					throw error;
				}
			},
		};
		registry.install(defineExtension({ name: "codemode", tools: [timed] }));
		const codemodeInitMs = performance.now() - initStarted;

		const samples = [];
		const modes = ["cold", "warmup", "warm"];
		for (let index = 0; index < modes.length; index++) {
			if (index > 0) await sleep(1500);
			executions.length = 0;
			decisions = 0;
			commits = 0;
			faux.setResponses([
				fauxAssistantMessage([fauxToolCall("codemode", { code }, { id: `${workload.toLowerCase()}-${modes[index]}-${index + 1}` })], {
					stopReason: "toolUse",
				}),
				fauxAssistantMessage([fauxText("ok")]),
			]);
			const started = performance.now();
			await (await root.submit({ type: "input", content: "go" }, context)).wait(context);
			const turnMs = performance.now() - started;
			const execution = executions.at(-1);
			samples.push({ mode: modes[index], workload, codemodeMs: execution?.ms, turnMs, commits, hookDecisions: decisions, ...verify(execution, expected, decisions) });
		}
		await sleep(1500);
		await harness.close(context);
		await sandbox.close();
		return {
			schema: "memoshi.codemode-workload.result.v1",
			workload,
			backendLabel: "node-oracle",
			runtime: `node ${process.version}`,
			launchIndex,
			codemodeInitMs,
			samples,
			failures: samples.filter((sample) => !sample.verified).map((sample) => `${sample.mode} ${workload}: ${sample.verification}`),
		};
	} finally {
		await rm(directory, { recursive: true, force: true });
	}
}

const argv = process.argv.slice(2);
const option = (flag: string) => {
	const index = argv.indexOf(flag);
	return index >= 0 && index + 1 < argv.length ? argv[index + 1] : undefined;
};
const fixture = option("--fixture");
const workload = option("--workload");
if (fixture === undefined || workload === undefined) {
	throw new Error("usage: codemode-workload-bench.ts --fixture <dir> --workload W1|W2 [--launches N | --launch K]");
}
const launch = option("--launch");
if (launch !== undefined) {
	const result = await runLaunch(fixture, workload, Number(launch));
	process.stdout.write(`${JSON.stringify(result)}\n`);
	if (result.failures.length > 0) process.exitCode = 2;
} else {
	const launches = Number(option("--launches") ?? "10");
	for (let index = 1; index <= launches; index++) {
		const child = spawnSync(
			process.execPath,
			[...process.execArgv, fileURLToPath(import.meta.url), "--fixture", fixture, "--workload", workload, "--launch", String(index)],
			{ encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
		);
		process.stdout.write(child.stdout);
		if (child.status !== 0) process.stderr.write(`launch ${index} exited with status ${child.status}\n`);
	}
}
