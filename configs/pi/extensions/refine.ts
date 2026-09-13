// /refine <prompt>: iterative refinement loop against acceptance criteria.
// <prompt> is the acceptance standard. Each round forks the current context into a
// worker subagent via the pi-subagents delegation API; if the check
// reports findings, they are injected as a fix directive for the main agent, and
// the work is re-checked after the fix turn. The loop exits when the check passes.

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const STATUS_KEY = "refine";
const MAX_ROUNDS = 10;
const CHECK_TIMEOUT_MS = 3_600_000;
// Fallback when the delegation bridge never answers (pi-subagents not loaded).
const NO_RESPONSE_TIMEOUT_MS = CHECK_TIMEOUT_MS + 30_000;

// pi-subagents delegation contract (src/api/delegation.ts); inline to avoid bare imports.
const DELEGATION_REQUEST_EVENT = "prompt-template:subagent:request";
const DELEGATION_RESPONSE_EVENT = "prompt-template:subagent:response";
const DELEGATION_CANCEL_EVENT = "prompt-template:subagent:cancel";

interface DelegationRequest {
	requestId: string;
	ownerRunId: string;
	nodeId: string;
	agent: string;
	task: string;
	context: "fresh" | "fork";
	cwd: string;
	model?: string;
	timeoutMs?: number;
	result: { kind: "structured"; schema: Record<string, unknown> };
}

interface DelegationResponse {
	requestId: string;
	ownerRunId?: string;
	nodeId?: string;
	status: string;
	error?: string;
	result?: { kind: "structured"; value?: unknown } | { kind: "text"; text: string };
}

interface CheckOutcome {
	passed: boolean;
	findings: string[];
}

interface RefineCheckData {
	round: number;
	passed?: boolean; // undefined = the check itself failed
	findings: string[];
	status: string;
	error?: string;
}

const FINDINGS_SCHEMA = {
	type: "object",
	properties: {
		passed: { type: "boolean" },
		findings: { type: "array", items: { type: "string" } },
	},
	required: ["passed", "findings"],
	additionalProperties: false,
};

export default function (pi: ExtensionAPI) {
	let criteria: string | undefined; // undefined = loop off
	let round = 0;
	let pendingCheck = false;
	let expectAbort = false; // the loop itself interrupted the current turn
	let lastStopReason: string | undefined;
	let retriedRound: number | undefined; // round that already used its structured-output retry
	let activeRequest: { requestId: string; ownerRunId: string; nodeId: string } | undefined;
	let activeTimer: ReturnType<typeof setTimeout> | undefined;
	const waiters = new Map<string, (response: DelegationResponse) => void>();

	const reset = (ctx: ExtensionContext) => {
		// Abandon any in-flight check: tell the bridge, drop its waiter, stop its fallback timer.
		if (activeRequest) {
			pi.events.emit(DELEGATION_CANCEL_EVENT, { ...activeRequest });
			waiters.delete(activeRequest.requestId);
			activeRequest = undefined;
		}
		if (activeTimer) {
			clearTimeout(activeTimer);
			activeTimer = undefined;
		}
		criteria = undefined;
		round = 0;
		pendingCheck = false;
		expectAbort = false;
		lastStopReason = undefined;
		retriedRound = undefined;
		ctx.ui.setStatus(STATUS_KEY, undefined);
	};

	const setStatus = (ctx: ExtensionContext) => {
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("accent", `R${round}`));
	};

	pi.registerEntryRenderer<RefineCheckData>("refine-check", (entry, _meta, theme) => {
		const data = entry.data!;
		const header =
			data.passed === undefined
				? theme.fg("error", `refine R${data.round}: check failed (${data.status})`)
				: data.passed || data.findings.length === 0
					? theme.fg("success", `refine R${data.round}: criteria satisfied`)
					: theme.fg("warning", `refine R${data.round}: ${data.findings.length} finding(s)`);
		const box = new Box(1, 1);
		box.addChild(new Text(header, 0, 0));
		data.findings.forEach((finding, index) => {
			box.addChild(new Text(theme.fg("muted", `${index + 1}. `) + finding, 0, 0));
		});
		if (data.passed === undefined && data.error) {
			box.addChild(new Text(theme.fg("error", data.error), 0, 0));
		}
		return box;
	});

	pi.events.on(DELEGATION_RESPONSE_EVENT, (payload) => {
		const response = payload as DelegationResponse;
		const waiter = waiters.get(response.requestId);
		if (!waiter) return;
		waiters.delete(response.requestId);
		waiter(response);
	});

	const runCheck = (ctx: ExtensionContext): void => {
		setStatus(ctx);
		const requestId = crypto.randomUUID();
		const request: DelegationRequest = {
			requestId,
			ownerRunId: `refine-${ctx.sessionManager.getSessionId()}`,
			nodeId: `refine-r${round}-${requestId.slice(0, 8)}`,
			agent: "worker",
			task: `Refinement check, round ${round} of an iterative loop that repeats after every fix turn.
Acceptance criteria:
${criteria}

You have the parent session's conversation context. Inspect the current
workspace state and verify whether the work satisfies ALL criteria.
Go through the criteria ONE BY ONE and check each against the actual files;
do not stop at the first issue. Earlier rounds' findings were not necessarily
exhaustive, and reported ones are not necessarily fixed -- verify the full
criteria list against the current state.
Every round, if the criteria rely on a skill, reload its SKILL.md first;
do not judge from memory of earlier rounds.
A premature pass ends the loop with unfinished work; when in doubt, report a finding.
Only report issues you can justify with evidence (cite file paths).
Report the verdict ONLY by calling the structured_output tool with
{ "passed": <boolean>, "findings": [<string>, ...] }; a prose-only final answer fails this step.`,
			context: "fork",
			cwd: ctx.cwd,
			// Per-run override: inherit the main session model.
			model: ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined,
			timeoutMs: CHECK_TIMEOUT_MS,
			result: { kind: "structured", schema: FINDINGS_SCHEMA },
		};
		activeRequest = { requestId, ownerRunId: request.ownerRunId, nodeId: request.nodeId };
		// Install the timer and waiter before emitting: the bridge can synchronously answer
		// invalid_request/unavailable_context during the emit itself.
		new Promise<DelegationResponse>((resolve) => {
			waiters.set(requestId, (response) => {
				resolve(response);
			});
			activeTimer = setTimeout(() => {
				waiters.delete(requestId);
				activeRequest = undefined;
				activeTimer = undefined;
				onCheckDone(ctx, {
					requestId,
					status: "timeout",
					error: "no response from the pi-subagents delegation bridge",
				});
			}, NO_RESPONSE_TIMEOUT_MS);
		}).then((response) => {
			clearTimeout(activeTimer);
			activeRequest = undefined;
			activeTimer = undefined;
			onCheckDone(ctx, response);
		});
		pi.events.emit(DELEGATION_REQUEST_EVENT, request);
	};

	const onCheckDone = (ctx: ExtensionContext, response: DelegationResponse): void => {
		const completedRound = round;
		if (response.status === "structured_output_failed" && retriedRound !== completedRound) {
			// The reviewer ended with prose instead of calling structured_output; retry once per round.
			retriedRound = completedRound;
			ctx.ui.notify(`refine: round ${completedRound} check missed structured_output, retrying once`, "warning");
			runCheck(ctx);
			return;
		}
		// The delegation bridge schema-validates structured results before returning them.
		const outcome =
			response.status === "completed" && response.result?.kind === "structured"
				? response.result.value as CheckOutcome
				: undefined;
		pi.appendEntry<RefineCheckData>("refine-check", {
			round: completedRound,
			passed: outcome?.passed,
			findings: outcome?.findings ?? [],
			status: response.status,
			error: response.error,
		});
		if (!outcome) {
			ctx.ui.notify(`refine: check failed (${response.status}${response.error ? `: ${response.error}` : ""}), loop stopped`, "error");
			reset(ctx);
			return;
		}
		if (outcome.passed || outcome.findings.length === 0) {
			ctx.ui.notify(`refine: criteria satisfied after round ${completedRound}`, "success");
			reset(ctx);
			return;
		}
		round += 1;
		if (round > MAX_ROUNDS) {
			ctx.ui.notify(`refine: stopped after ${completedRound} rounds (max ${MAX_ROUNDS}); findings remain`, "warning");
			reset(ctx);
			return;
		}
		ctx.ui.notify(`refine: round ${completedRound} found ${outcome.findings.length} issue(s); requesting fixes`, "info");
		pendingCheck = true;
		pi.sendMessage(
			{
				customType: "refine-control",
				content: `<refine_control round="${completedRound}">
Judge every finding below against the acceptance criteria before fixing anything:
fix the real ones; for a finding you judge wrong, do not fix it and say plainly
that you reject it and why (cite the file, line, or the criterion it misreads),
so the next round does not raise it again; if you cannot tell whether a finding
is right, do not guess -- call the ask_user_question tool with the finding and
your doubt, then act on the user's decision.
A follow-up check runs automatically after this turn; do not restate the criteria
or the findings you are fixing.
After fixing, re-check every criterion yourself to ensure nothing is missed.
If the criteria rely on a skill, reload its SKILL.md this round before fixing.

Acceptance criteria:
${criteria}

Findings from the round ${completedRound} check:
${outcome.findings.map((finding, index) => `${index + 1}. ${finding}`).join("\n")}
</refine_control>`,
				display: false,
			},
			{ triggerTurn: true, deliverAs: "followUp" },
		);
	};

	pi.registerCommand("refine", {
		description: "Iteratively refine work against <prompt> as acceptance criteria; run without args to cancel",
		handler: async (args, ctx) => {
			const standard = args.trim();
			if (!standard) {
				if (criteria === undefined) {
					ctx.ui.notify("Usage: /refine <acceptance criteria>", "info");
					return;
				}
				reset(ctx);
				ctx.ui.notify("refine loop cancelled", "info");
				return;
			}
			reset(ctx); // abandons any active loop and in-flight check
			round = 1;
			criteria = standard;
			pendingCheck = true;
			setStatus(ctx);
			if (!ctx.isIdle()) {
				expectAbort = true;
				ctx.abort();
				ctx.ui.notify("refine enabled: check starts when the current turn ends", "info");
				return;
			}
			pendingCheck = false;
			ctx.ui.notify("refine enabled: checking against the criteria (round 1)", "info");
			runCheck(ctx);
		},
	});

	pi.on("session_start", (_event, ctx) => {
		reset(ctx);
	});

	pi.on("agent_end", (event) => {
		if (criteria === undefined) return;
		lastStopReason = event.messages.findLast((message) => message.role === "assistant")?.stopReason;
	});

	pi.on("agent_settled", (_event, ctx) => {
		if (criteria === undefined || !pendingCheck) return;
		// A user-interrupted fix turn pauses the loop; the check resumes after the next settled turn.
		if (lastStopReason === "aborted" && !expectAbort) {
			setStatus(ctx);
			return;
		}
		expectAbort = false;
		pendingCheck = false;
		runCheck(ctx);
	});
}
