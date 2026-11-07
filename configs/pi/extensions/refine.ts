import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const STATUS_KEY = "refine";
const DEFAULT_MAX_ROUNDS = 30;
const CONFIG_PATH = path.join(getAgentDir(), "refine.json");
const CHECK_TIMEOUT_MS = 3_600_000;
// Fallback when the delegation bridge never answers (pi-subagents not loaded).
const NO_RESPONSE_TIMEOUT_MS = CHECK_TIMEOUT_MS + 30_000;

const loadMaxRounds = (): number => {
	try {
		const value = (JSON.parse(readFileSync(CONFIG_PATH, "utf8")) as { maxRounds?: unknown }).maxRounds;
		if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return value;
	} catch {}
	return DEFAULT_MAX_ROUNDS;
};

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

interface RefineCheckData {
	round: number;
	findings: string[];
	status: string;
	error?: string;
}

const FINDINGS_SCHEMA = {
	type: "object",
	properties: {
		findings: { type: "array", items: { type: "string" } },
	},
	required: ["findings"],
	additionalProperties: false,
};

export default function (pi: ExtensionAPI) {
	let criteria: string | undefined; // undefined = loop off
	let round = 0;
	let maxRounds = loadMaxRounds();
	let pendingCheck = false;
	let lastStopReason: string | undefined;
	let retriedRound: number | undefined;
	let activeRequest: { requestId: string; ownerRunId: string; nodeId: string } | undefined;
	let activeTimer: ReturnType<typeof setTimeout> | undefined;
	const waiters = new Map<string, (response: DelegationResponse) => void>();

	const reset = (ctx: ExtensionContext) => {
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
		lastStopReason = undefined;
		retriedRound = undefined;
		ctx.ui.setStatus(STATUS_KEY, undefined);
	};

	const setStatus = (ctx: ExtensionContext) => {
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("accent", `R${round}`));
	};

	pi.registerEntryRenderer<RefineCheckData>("refine-check", (entry, _meta, theme) => {
		const data = entry.data!;
		const failed = data.status !== "completed";
		const header = failed
			? theme.fg("error", `refine R${data.round}: check failed (${data.status})`)
			: data.findings.length === 0
				? theme.fg("success", `refine R${data.round}: criteria satisfied`)
				: theme.fg("warning", `refine R${data.round}: ${data.findings.length} finding(s)`);
		const box = new Box(1, 1);
		box.addChild(new Text(header, 0, 0));
		data.findings.forEach((finding, index) => {
			box.addChild(new Text(theme.fg("muted", `${index + 1}. `) + finding, 0, 0));
		});
		if (failed && data.error) {
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
			agent: "refine-checker",
			task: `Refinement check, round ${round} of an iterative loop that repeats after every fix turn.
Acceptance criteria:
${criteria}

Use the parent conversation for context and check the current work. Read any
instructions referenced by the criteria and follow their scope, review order,
and reporting requirements.

Return only unresolved findings that require action under the criteria. Exclude
passing checks, withdrawn concerns, and commentary from the findings array.
Consider previous fixes and rejections; repeat a finding only if it remains
valid, explaining why any previous rejection no longer applies.

If a criterion cannot be verified, include it in findings with the reason so
the parent can address it. Return empty findings only when the work satisfies
the criteria under their review procedure.

Return the result ONLY by calling the structured_output tool.`,
			context: "fork",
			cwd: ctx.cwd,
			model: ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined,
			timeoutMs: CHECK_TIMEOUT_MS,
			result: { kind: "structured", schema: FINDINGS_SCHEMA },
		};
		activeRequest = { requestId, ownerRunId: request.ownerRunId, nodeId: request.nodeId };
		// Install the timer and waiter before emitting: the bridge can synchronously answer
		// invalid_request/unavailable_context during the emit itself.
		new Promise<DelegationResponse>((resolve) => {
			waiters.set(requestId, resolve);
			activeTimer = setTimeout(() => {
				if (activeRequest?.requestId !== requestId) return;
				waiters.delete(requestId);
				onCheckDone(ctx, {
					requestId,
					status: "timeout",
					error: "no response from the pi-subagents delegation bridge",
				});
			}, NO_RESPONSE_TIMEOUT_MS);
		}).then((response) => {
			if (activeRequest?.requestId !== requestId) return;
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
			retriedRound = completedRound;
			ctx.ui.notify(`refine: round ${completedRound} check missed structured_output, retrying once`, "warning");
			runCheck(ctx);
			return;
		}
		// The delegation bridge schema-validates structured results before returning them.
		const outcome =
			response.status === "completed" && response.result?.kind === "structured"
				? response.result.value as Pick<RefineCheckData, "findings">
				: undefined;
		// The renderer reads only this status, so record the effective outcome, not the raw one.
		const entryStatus = outcome
			? "completed"
			: response.status === "completed"
				? "unstructured"
				: response.status;
		pi.appendEntry<RefineCheckData>("refine-check", {
			round: completedRound,
			findings: outcome?.findings ?? [],
			status: entryStatus,
			error: response.error,
		});
		if (!outcome) {
			ctx.ui.notify(`refine: check failed (${entryStatus}${response.error ? `: ${response.error}` : ""}), loop stopped`, "error");
			reset(ctx);
			return;
		}
		if (outcome.findings.length === 0) {
			ctx.ui.notify(`refine: criteria satisfied after round ${completedRound}`, "info");
			reset(ctx);
			return;
		}
		round += 1;
		if (round > maxRounds) {
			ctx.ui.notify(`refine: stopped after ${completedRound} rounds (max ${maxRounds}); findings remain`, "warning");
			reset(ctx);
			return;
		}
		ctx.ui.notify(`refine: round ${completedRound} found ${outcome.findings.length} issue(s); requesting fixes`, "info");
		pendingCheck = true;
		pi.sendMessage(
			{
				customType: "refine-control",
				content: `<refine_control round="${completedRound}">
Acceptance criteria:
${criteria}

Findings from the round ${completedRound} check:
${outcome.findings.map((finding, index) => `${index + 1}. ${finding}`).join("\n")}

Read any instructions referenced by the criteria. Review these findings against
the criteria and current work before changing anything. Address the findings
you accept; explain any you reject so the next check can take that into account.
Follow the criteria's scope, workflow, and validation requirements.

A follow-up check runs automatically after this turn settles.
</refine_control>`,
				display: false,
			},
			{ triggerTurn: true, deliverAs: "followUp" },
		);
	};

	pi.registerCommand("refine", {
		description:
			"Iteratively refine work against <prompt> as acceptance criteria; /refine set <n> sets the round limit; run without args to cancel",
		handler: async (args, ctx) => {
			const standard = args.trim();
			const setRoundLimit = standard.match(/^set(?:\s+(\d+))?$/);
			if (setRoundLimit) {
				const value = setRoundLimit[1];
				if (value === undefined) {
					ctx.ui.notify(`refine: limit ${maxRounds} rounds (${CONFIG_PATH})`, "info");
					return;
				}
				const rounds = Number(value);
				if (!Number.isSafeInteger(rounds) || rounds < 1) {
					ctx.ui.notify("Usage: /refine set <n>", "warning");
					return;
				}
				maxRounds = rounds;
				mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
				writeFileSync(CONFIG_PATH, `${JSON.stringify({ maxRounds: rounds }, null, 2)}\n`);
				ctx.ui.notify(`refine: limit ${rounds} rounds, saved to ${CONFIG_PATH}`, "info");
				return;
			}
			if (!standard) {
				if (criteria === undefined) {
					ctx.ui.notify("Usage: /refine <acceptance criteria> | /refine set <n>", "info");
					return;
				}
				reset(ctx);
				ctx.ui.notify("refine loop cancelled", "info");
				return;
			}
			reset(ctx);
			round = 1;
			criteria = standard;
			if (!ctx.isIdle()) {
				pendingCheck = true;
				setStatus(ctx);
				ctx.ui.notify("refine enabled: check starts when the current turn settles", "info");
				return;
			}
			ctx.ui.notify("refine enabled: checking against the criteria", "info");
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
		// A user-interrupted turn pauses the loop; the check resumes after the next settled turn.
		if (lastStopReason === "aborted") return;
		pendingCheck = false;
		runCheck(ctx);
	});
}
