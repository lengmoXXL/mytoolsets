import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, test } from "node:test";

const agentDir = mkdtempSync(path.join(tmpdir(), "pi-refine-test-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
const { default: refine } = await import("../refine.ts");
after(() => rmSync(agentDir, { recursive: true, force: true }));

function setup(t, maxRounds = 3) {
	writeFileSync(path.join(agentDir, "refine.json"), JSON.stringify({ maxRounds }));
	const events = new EventEmitter();
	const handlers = new Map();
	const state = { requests: [], cancellations: [], messages: [], entries: [], notices: [], idle: true, status: undefined };
	const ctx = {
		cwd: "/work",
		model: { provider: "test", id: "model" },
		sessionManager: { getSessionId: () => "session" },
		isIdle: () => state.idle,
		ui: {
			theme: { fg: (_color, text) => text },
			setStatus: (_key, value) => { state.status = value; },
			notify: (message) => state.notices.push(message),
		},
	};
	let command;
	events.on("prompt-template:subagent:request", (request) => state.requests.push(request));
	events.on("prompt-template:subagent:cancel", (request) => state.cancellations.push(request));
	refine({
		events,
		registerCommand: (_name, spec) => { command = spec.handler; },
		registerEntryRenderer: () => {},
		on: (name, handler) => handlers.set(name, handler),
		appendEntry: (_type, data) => state.entries.push(data),
		sendMessage: (message) => state.messages.push(message),
	});
	t.after(() => command("", ctx));
	return {
		state,
		command: (args) => command(args, ctx),
		emit: (event, data = {}) => handlers.get(event)(data, ctx),
		reply: (request, response) => events.emit("prompt-template:subagent:response", { requestId: request.requestId, ...response }),
	};
}

test("findings go to the parent; its settled turn triggers a new check; an empty result stops", async (t) => {
	const run = setup(t);
	await run.command("review this work");
	assert.equal(run.state.requests.length, 1);
	const finding = "cannot verify the criterion: required input is unavailable";
	run.reply(run.state.requests[0], { status: "completed", result: { kind: "structured", value: { findings: [finding] } } });
	await Promise.resolve();
	assert.deepEqual(run.state.entries[0].findings, [finding]);
	assert.equal(run.state.messages.length, 1);
	assert.ok(run.state.messages[0].content.includes(finding));
	assert.equal(run.state.requests.length, 1);
	run.emit("agent_settled");
	assert.equal(run.state.requests.length, 2);
	run.reply(run.state.requests[1], { status: "completed", result: { kind: "structured", value: { findings: [] } } });
	await Promise.resolve();
	assert.equal(run.state.status, undefined);
	assert.match(run.state.notices.at(-1), /criteria satisfied after round 2/);
	run.emit("agent_settled");
	assert.equal(run.state.requests.length, 2);
});

test("a running or interrupted parent turn is not checked until it settles normally", async (t) => {
	const run = setup(t);
	run.state.idle = false;
	await run.command("review this work");
	assert.equal(run.state.requests.length, 0);
	run.emit("agent_end", { messages: [{ role: "assistant", stopReason: "aborted" }] });
	run.emit("agent_settled");
	assert.equal(run.state.requests.length, 0);
	run.emit("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] });
	run.emit("agent_settled");
	assert.equal(run.state.requests.length, 1);
});

test("the round limit stops with remaining findings rather than claiming success", async (t) => {
	const run = setup(t, 2);
	await run.command("review this work");
	for (let round = 0; round < 2; round++) {
		run.reply(run.state.requests[round], { status: "completed", result: { kind: "structured", value: { findings: ["unfinished work"] } } });
		await Promise.resolve();
		run.emit("agent_settled");
	}
	assert.equal(run.state.requests.length, 2);
	assert.equal(run.state.messages.length, 1);
	assert.match(run.state.notices.at(-1), /findings remain/);
});

test("a failed check stops without requesting fixes", async (t) => {
	const run = setup(t);
	await run.command("review this work");
	run.reply(run.state.requests[0], { status: "failed", error: "checker exited" });
	await Promise.resolve();
	assert.equal(run.state.entries[0].error, "checker exited");
	assert.equal(run.state.messages.length, 0);
	assert.equal(run.state.status, undefined);
});

test("a missing structured result retries once and then stops", async (t) => {
	const run = setup(t);
	await run.command("review this work");
	for (let attempt = 0; attempt < 2; attempt++) {
		run.reply(run.state.requests[attempt], { status: "structured_output_failed" });
		await Promise.resolve();
	}
	assert.equal(run.state.requests.length, 2);
	assert.equal(run.state.entries.length, 1);
	assert.equal(run.state.entries[0].round, 1);
	assert.equal(run.state.messages.length, 0);
	assert.equal(run.state.status, undefined);
});

for (const action of ["cancel", "restart", "session_start"]) {
	test(`${action} ignores a response already queued by the old check`, async (t) => {
		const run = setup(t);
		await run.command("old criteria");
		const old = run.state.requests[0];
		run.reply(old, { status: "completed", result: { kind: "structured", value: { findings: ["old finding"] } } });
		// Cancel after the response arrives but before its promise continuation runs.
		if (action === "session_start") run.emit("session_start");
		else await run.command(action === "cancel" ? "" : "new criteria");
		await Promise.resolve();
		assert.equal(run.state.entries.length, 0);
		assert.equal(run.state.messages.length, 0);
		assert.equal(run.state.cancellations[0].requestId, old.requestId);
		if (action === "restart") {
			assert.equal(run.state.status, "R1");
			run.reply(run.state.requests[1], { status: "completed", result: { kind: "structured", value: { findings: [] } } });
			await Promise.resolve();
			assert.equal(run.state.entries.length, 1);
			assert.equal(run.state.entries[0].round, 1);
		}
	});
}

test("cancelling an in-flight check ignores a later response", async (t) => {
	const run = setup(t);
	await run.command("review this work");
	const request = run.state.requests[0];
	await run.command("");
	run.reply(request, { status: "completed", result: { kind: "structured", value: { findings: ["late finding"] } } });
	await Promise.resolve();
	assert.equal(run.state.entries.length, 0);
	assert.equal(run.state.messages.length, 0);
	assert.equal(run.state.cancellations[0].requestId, request.requestId);
});

test("a missing bridge response stops the loop and cancels the abandoned check", async (t) => {
	t.mock.timers.enable({ apis: ["setTimeout"] });
	const run = setup(t);
	await run.command("review this work");
	const request = run.state.requests[0];
	t.mock.timers.tick(request.timeoutMs + 30_000);
	assert.equal(run.state.entries[0].status, "timeout");
	assert.equal(run.state.status, undefined);
	assert.equal(run.state.messages.length, 0);
	assert.equal(run.state.cancellations[0]?.requestId, request.requestId);
	run.reply(request, { status: "completed", result: { kind: "structured", value: { findings: ["late finding"] } } });
	await Promise.resolve();
	assert.equal(run.state.entries.length, 1);
});
