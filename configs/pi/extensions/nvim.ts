// /goal <goal>: drive one goal inside the Neovim buffer the user is editing.
// Nothing runs until /goal: that command connects to the Neovim instance whose cwd is pi's
// cwd (over `nvim --server <sock> --remote-expr`, ~30ms per call) and installs a trigger key.
// The user asks for options on purpose with <F8> or :PiOptions, which appends a line of
// "<file>\t<first>\t<last>" to a trigger file of its own; those lines are the only thing watched,
// so edits and cursor moves never interrupt. Presses queue and are answered one per turn, so
// pressing the key while an answer streams loses nothing; a widget above the editor lists what is
// still waiting.
// /goal stop (or goal_done) unmaps the key and closes the connection.
// Env: PI_NVIM_SOCKET (explicit socket), PI_NVIM_GOAL_KEY (the trigger key),
//      PI_NVIM_SELECT_TIMEOUT_MS (how long a selection waits).

import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { readdir, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "nvim";
const QUEUE_KEY = "nvim-goal-queue";
const POLL_MS = 1000;
const MAX_SCAN_DEPTH = 3;
const REMOTE_TIMEOUT_MS = 5000;
const SELECT_TIMEOUT_MS = Number(process.env.PI_NVIM_SELECT_TIMEOUT_MS) || 300_000;
const TRIGGER_POLL_MS = 500;
const WAKE_MIN_MS = 1000;

const TRIGGER_KEY = process.env.PI_NVIM_GOAL_KEY || "<F8>";
const HEARTBEAT_MAX_S = 10;
// Ownership tags: neither install nor remove touches a key or a command made by the user. A command
// created from a Lua callback reports this desc back as its `definition`, which is what we compare.
const MAP_DESC = "pi goal: request options";
const CMD_DESC = "pi: ask for new options";
// A press line is far shorter than this, so a replaced file almost never shares the old tail.
const TAIL_BYTES = 256;
// mode() reports 0x16 as the first byte of a blockwise visual selection.
const BLOCK_VISUAL = "\x16";

function triggerFile(socket: string): string {
	return path.join(os.tmpdir(), `pi-nvim-goal-${createHash("sha1").update(socket).digest("hex").slice(0, 12)}`);
}

// Written by /goal and refreshed every tick: the key in nvim appends only while this file is
// younger than HEARTBEAT_MAX_S, which is how a mapping left behind by a killed pi reports itself.
function heartbeatFile(socket: string): string {
	return `${triggerFile(socket)}.live`;
}

// Loaded by select(); lives beside the two above so two pi sessions never share one blob.
function pickerFile(socket: string): string {
	return `${triggerFile(socket)}.lua`;
}

interface NvimState {
	file: string;
	line: number;
	sel?: { start: number; end: number };
}

interface RawState {
	file: string;
	mode: string;
	cursor: number;
	sel: [number, number];
}

interface Focus {
	file: string;
	start: number;
	end: number;
	kind: "highlight" | "cursor line";
}

interface GoalRun {
	goal: string;
	socket: string;
}

function nvimExpr(socket: string, expr: string, timeout = REMOTE_TIMEOUT_MS, signal?: AbortSignal): Promise<string> {
	return new Promise((resolve, reject) => {
		const child = execFile(
			"nvim",
			["--server", socket, "--remote-expr", expr],
			{ timeout, maxBuffer: 64 * 1024 * 1024 },
			(error, stdout, stderr) => {
				signal?.removeEventListener("abort", abort);
				if (error) {
					reject(new Error((stderr || error.message).trim()));
					return;
				}
				resolve(stdout);
			},
		);
		// Killing the client leaves nvim waiting on the prompt; the user closes it with Esc.
		const abort = () => child.kill();
		signal?.addEventListener("abort", abort);
	});
}

function vimlString(text: string): string {
	return `'${text.replace(/'/g, "''").replace(/[\r\n]+/g, " ")}'`;
}

// How a TS value travels into a luaeval argument list.
function luaJson(value: unknown): string {
	return `json_decode(${vimlString(JSON.stringify(value))})`;
}

// Keyboard-only, and falls back to inputlist() when the panel cannot be used.
const PICKER_LUA = `local MANUAL = "type what you want instead"
-- Preview is cut at this many rows so the panel stays a glance, not a second buffer.
local MAX_DETAIL_ROWS = 10
-- Rows the panel must leave free in the editor, command line included.
local FEWEST_EDITOR_ROWS = 3
-- Gap kept below the panel, clear of the command line.
local BOTTOM_GAP = 2

local function typed()
  vim.cmd("redraw")
  local answer = vim.fn.input("pi> ")
  vim.cmd("redraw")
  if answer == "" then return nil end
  return { text = answer }
end

local function pick(items, prompt, details, multi, targets)
  local rows = #items + 1
  local head = (prompt and prompt ~= "") and { prompt } or {}
  local marked = {}
  local origin = vim.api.nvim_get_current_win()
  local originBuf = vim.api.nvim_win_get_buf(origin)
  local originView = vim.api.nvim_win_call(origin, function()
    return vim.fn.winsaveview()
  end)
  local originCursorline = vim.wo[origin].cursorline
  local function label(index)
    local text = index <= #items and items[index] or MANUAL
    if not multi then return text end
    return (marked[index] and "[x] " or "[ ] ") .. text
  end
  local function detailRows(index)
    local text = (details and details[index]) or ""
    local out = {}
    for line in (text .. "\\n"):gmatch("([^\\n]*)\\n") do
      out[#out + 1] = line
      if #out == MAX_DETAIL_ROWS then
        out[#out + 1] = "..."
        break
      end
    end
    return out
  end

  local pad = 0
  for i = 1, #items do
    pad = math.max(pad, #detailRows(i))
  end

  local width = math.max(vim.o.columns - 2, 12)
  local height = #head + rows + (pad > 0 and pad + 1 or 0)
  if height > vim.o.lines - FEWEST_EDITOR_ROWS then error("picker does not fit") end

  -- Anchored above the command line; reveal() scrolls the buffer itself, so the shown line is only
  -- visible as far as the space left above the panel allows.
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = vim.o.lines - height - BOTTOM_GAP,
    col = 1,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winhl = "NormalFloat:NormalFloat,CursorLine:Visual"

  local sel = 1
  local function reveal(index)
    local target = targets and targets[index]
    if not target or not target.line or target.line <= 0 or not vim.api.nvim_win_is_valid(origin) then return end
    pcall(function()
      local file = target.file
      local current = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin))
      if file and file ~= "" and vim.fn.fnamemodify(file, ":p") ~= vim.fn.fnamemodify(current, ":p") then
        vim.api.nvim_win_call(origin, function()
          vim.cmd("edit " .. vim.fn.fnameescape(file))
        end)
      end
      -- The panel keeps the focus, so the terminal cursor stays there: cursorline marks the
      -- line being shown in the buffer instead.
      vim.wo[origin].cursorline = true
      vim.api.nvim_win_set_cursor(origin, { target.line, 0 })
      vim.api.nvim_win_call(origin, function()
        vim.cmd("normal! zz")
      end)
    end)
  end
  local function toggled()
    local out = {}
    for i = 1, #items do
      if marked[i] then out[#out + 1] = i end
    end
    return out
  end
  local function show()
    local lines = {}
    for _, line in ipairs(head) do
      lines[#lines + 1] = line
    end
    for i = 1, rows do
      lines[#lines + 1] = (i == sel and "> " or "  ") .. label(i)
    end
    if pad > 0 then
      local extra = detailRows(sel)
      lines[#lines + 1] = string.rep("-", math.max(width - 2, 4))
      for i = 1, pad do
        lines[#lines + 1] = extra[i] or ""
      end
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(win, { #head + sel, 0 })
    reveal(sel)
  end
  show()

  local ok, chosen = pcall(function()
    while true do
      vim.cmd("redraw")
      local name = vim.fn.keytrans(vim.fn.getcharstr())
      if name == "<CR>" or name == "<NL>" then
        local picked = multi and toggled() or {}
        if #picked == 0 and sel <= #items then picked = { sel } end
        if #picked > 0 then return { indexes = picked } end
        return typed()
      elseif multi and (name == " " or name == "<Space>" or name == "x") then
        if sel <= #items then
          marked[sel] = not marked[sel] or nil
          show()
        end
      elseif name == "i" or name == "e" or name == "<C-e>" then
        return typed()
      elseif name == "<Esc>" or name == "<C-c>" or name == "q" then
        return nil
      elseif name == "j" or name == "<Down>" or name == "<C-n>" or name == "<Tab>" then
        if sel < rows then
          sel = sel + 1
          show()
        end
      elseif name == "k" or name == "<Up>" or name == "<C-p>" then
        if sel > 1 then
          sel = sel - 1
          show()
        end
      elseif #name == 1 and name:match("%d") then
        local index = tonumber(name)
        if index >= 1 and index <= #items then
          if not multi then return { indexes = { index } } end
          marked[index] = not marked[index] or nil
          show()
        end
      end
    end
  end)

  pcall(vim.api.nvim_win_close, win, true)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  -- Whatever was chosen, the user keeps reading where they were: the panel was only a detour.
  if vim.api.nvim_win_is_valid(origin) then
    pcall(function()
      vim.wo[origin].cursorline = originCursorline
      if vim.api.nvim_win_get_buf(origin) ~= originBuf then
        vim.api.nvim_win_set_buf(origin, originBuf)
      end
      vim.api.nvim_win_call(origin, function()
        vim.fn.winrestview(originView)
      end)
    end)
  end
  vim.cmd("redraw")
  if ok then return chosen end
  return nil
end

local function listChoice(items)
  local rows = #items + 1
  local list = { unpack(items) }
  list[rows] = MANUAL
  local index = vim.fn.inputlist(list)
  if index == rows then return typed() end
  if index > 0 then return { indexes = { index } } end
  return nil
end

return function(items, prompt, details, multi, targets)
  local ok, chosen = pcall(pick, items, prompt, details, multi == 1, targets)
  if ok then return chosen end
  return listChoice(items)
end
`;

async function walkSockets(dir: string, depth: number, out: string[]): Promise<void> {
	const entries = await readdir(dir, { withFileTypes: true }).catch(() => undefined);
	if (!entries) return;
	for (const entry of entries) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			// Default sockets live in <tmp>/nvim.<user>/<random>/nvim.<pid>.0:
			// descend freely once inside an nvim* directory, never into other trees.
			if (depth < MAX_SCAN_DEPTH && (depth > 0 || entry.name.startsWith("nvim"))) {
				await walkSockets(full, depth + 1, out);
			}
			continue;
		}
		if (!entry.name.startsWith("nvim")) continue;
		const info = await stat(full).catch(() => undefined);
		if (info?.isSocket()) out.push(full);
	}
}

async function listSockets(): Promise<string[]> {
	const roots = [process.env.XDG_RUNTIME_DIR, os.tmpdir(), "/tmp"].filter((dir): dir is string => !!dir);
	const found: string[] = [];
	for (const root of roots) {
		const dir = await realpath(root).catch(() => root);
		await walkSockets(dir, 0, found);
	}
	return [...new Set(found)];
}

async function probeCwd(socket: string): Promise<string | undefined> {
	try {
		return JSON.parse(await nvimExpr(socket, 'json_encode(getcwd())')) as string;
	} catch {
		return undefined;
	}
}

async function pickSocket(): Promise<string | undefined> {
	const explicit = process.env.PI_NVIM_SOCKET?.trim();
	if (explicit) return explicit;
	// nvim sets NVIM for what it spawns, so `pi` started from :terminal finds it.
	const inherited = process.env.NVIM?.trim();
	if (inherited) return inherited;

	// Only the instance rooted in this directory counts: another project's Neovim is not this one.
	const cwd = await realpath(process.cwd()).catch(() => process.cwd());
	for (const socket of await listSockets()) {
		const nvimCwd = await probeCwd(socket);
		if (nvimCwd === undefined) continue;
		if ((await realpath(nvimCwd).catch(() => nvimCwd)) === cwd) return socket;
	}
	return undefined;
}

function shortName(file: string): string {
	if (!file) return "[No Name]";
	const relative = path.relative(process.cwd(), file);
	return relative === "" || relative.startsWith("..") || path.isAbsolute(relative) ? file : relative;
}

function where(focus: Focus): string {
	return `${shortName(focus.file)}:${focus.start}-${focus.end}`;
}

function describe(focus: Focus): string {
	return `${where(focus)} (${focus.kind})`;
}

function protocol(key: string): string {
	return `Neovim goal loop. The user keeps editing in Neovim while you drive one goal.
Hard scope: every option and every delegated change stays inside the lines the goal-wake message names (the highlight, or the cursor line when nothing is highlighted). Never propose or delegate edits to other lines, other files, repo-wide cleanups, or unrelated refactors. If the goal needs more than those lines, offer "open <file> in Neovim first" or "widen the highlight" as an option and wait.
1. Read that file at those lines with the read tool before answering. Never trust an earlier look or a remembered buffer: the cursor, the highlight and the files change while you work, so only a fresh read is right.
2. Offer 2-4 candidates with nvim_select, simplest first, each one touching only those lines. The options are competing ways to change that code: start each option string with "<file>:<line> - " and say what changes at that line, give the resulting lines or a short -/+ diff as the matching details entry, and always pass files and lines with one entry per option. The user picks the concrete change, not just a direction. When they type an instruction instead, it is not a pick: read the lines again and offer revised candidates that follow it. Pass multi: true whenever several options belong together.
3. Delegate the chosen modification with subagent({ agent: "worker", task: "<brief>" }); the brief quotes the goal as the user wrote it, along with the scope and the exact change (file, line range, resulting code) so the worker applies that edit and nothing else, and covers every option the user selected. Keep one live worker: steer it with subagent({ action: "steer", id, message }) when the next choice arrives, and launch a new worker only when the previous run finished, failed, or was stopped. While it runs the worker is the only writer; do not edit files yourself.
4. Options are offered only when the user asks: they press ${key} in Neovim and you receive a goal-wake message with the file and lines. Starting the goal, ordinary edits and cursor moves are not requests: never offer options right after /goal or on your own, only after a goal-wake.
5. Blockers reach the user the same way, as candidate fixes with previews; when nothing at those lines can fix it, the options say so.
6. Call goal_done only after at least one goal-wake, when the goal is met or abandoned; right after /goal the loop is simply waiting for the key, so answer in one line and stop.`;
}

// Where the user is, not what they see: the agent reads the file itself, so nothing here can go
// stale while the answer is written.
function stateExpr(): string {
	const fields = [
		'"file": expand("%:p")',
		'"mode": mode(1)',
		'"cursor": line(".")',
		// '< and '> hold the last range; 0 means none.
		`"sel": [line("'<"), line("'>")]`,
	];
	return `json_encode({${fields.join(", ")}})`;
}

function isVisualMode(mode: string): boolean {
	return mode.startsWith("v") || mode.startsWith("V") || mode.startsWith(BLOCK_VISUAL);
}

function normalize(raw: RawState): NvimState {
	return {
		file: raw.file,
		line: raw.cursor,
		// Only a live visual selection counts: the '< and '> marks outlive it and would
		// otherwise point at text the user selected long ago.
		sel: raw.sel[0] > 0 && isVisualMode(raw.mode) ? { start: raw.sel[0], end: raw.sel[1] } : undefined,
	};
}

export default function nvimGoalExtension(pi: ExtensionAPI) {
	let run: GoalRun | undefined;
	let sessionCtx: ExtensionContext | undefined;
	let latest: NvimState | undefined;
	let statusText: string | undefined;
	let wakeTimer: ReturnType<typeof setTimeout> | undefined;
	let pollTimer: ReturnType<typeof setInterval> | undefined;
	let triggerTimer: ReturnType<typeof setInterval> | undefined;
	let queue: Focus[] = [];
	let answering: Focus | undefined;
	// What of the trigger file is already answered, and the bytes just before that point: if they
	// no longer match, the file was replaced and reading restarts from zero.
	let readBytes = 0;
	let readTail = Buffer.alloc(0);
	let lastWakeAt = 0;

	async function refresh(): Promise<NvimState | undefined> {
		const socket = run?.socket;
		if (!socket) return undefined;
		try {
			const raw = JSON.parse(await nvimExpr(socket, stateExpr())) as RawState;
			return normalize(raw);
		} catch {
			return undefined;
		}
	}

	// The focus is the press this turn answers, else the oldest waiting one, else the live
	// selection, else the cursor.
	function focusOf(state: NvimState): Focus {
		const pending = answering ?? queue[0];
		if (pending) return pending;
		if (state.sel) return { file: state.file, start: state.sel.start, end: state.sel.end, kind: "highlight" };
		return { file: state.file, start: state.line, end: state.line, kind: "cursor line" };
	}

	// Requests no answer has taken yet, in the order they will arrive.
	function showQueue(ctx: ExtensionContext | undefined): void {
		if (!ctx?.hasUI) return;
		const socket = run?.socket;
		if (!socket) {
			ctx.ui.setWidget(QUEUE_KEY, undefined);
			return;
		}
		const lines = queue.map((press, index) => `${index + 1}. ${describe(press)}`);
		ctx.ui.setWidget(QUEUE_KEY, [`pending requests (${queue.length}) on ${socket}`, ...lines]);
	}

	function footer(state: NvimState | undefined): string {
		return state ? `nvim ${where(focusOf(state))}` : "nvim: disconnected";
	}

	function setStatus(ctx: ExtensionContext, text: string | undefined): void {
		if (!ctx.hasUI || statusText === text) return;
		statusText = text;
		ctx.ui.setStatus(STATUS_KEY, text === undefined ? undefined : ctx.ui.theme.fg("dim", text));
	}

	function clearWakeTimer(): void {
		if (wakeTimer) clearTimeout(wakeTimer);
		wakeTimer = undefined;
	}

	function stopTimers(): void {
		clearWakeTimer();
		if (pollTimer) clearInterval(pollTimer);
		if (triggerTimer) clearInterval(triggerTimer);
		pollTimer = undefined;
		triggerTimer = undefined;
	}

	async function close(ctx: ExtensionContext | undefined): Promise<void> {
		const socket = run?.socket;
		run = undefined;
		latest = undefined;
		queue = [];
		answering = undefined;
		readBytes = 0;
		readTail = Buffer.alloc(0);
		lastWakeAt = 0;
		stopTimers();
		showQueue(ctx);
		if (ctx) setStatus(ctx, undefined);
		if (!socket) return;
		await removeMapping(socket);
		await rm(triggerFile(socket), { force: true });
		await rm(heartbeatFile(socket), { force: true });
		await rm(pickerFile(socket), { force: true });
	}

	// A streaming agent retries from agent_settled; anything still queued waits for the next turn.
	function wake(): void {
		if (!run || !sessionCtx) return;
		const focus = queue[0];
		if (!focus || !sessionCtx.isIdle()) return;
		const wait = WAKE_MIN_MS - (Date.now() - lastWakeAt);
		if (wait > 0) {
			clearWakeTimer();
			wakeTimer = setTimeout(wake, wait);
			return;
		}
		answering = focus;
		queue.shift();
		lastWakeAt = Date.now();
		showQueue(sessionCtx);
		const left = queue.length ? ` ${queue.length} more request(s) are queued and follow after this one.` : "";
		pi.sendMessage(
			{
				customType: "goal-wake",
				content: `The user asked for options from Neovim about ${describe(focus)}.${left}`,
				display: false,
			},
			{ triggerTurn: true },
		);
	}

	function parsePress(line: string): Focus | undefined {
		const [file, first, second] = line.split("\t");
		const from = Number(first);
		const to = Number(second);
		if (!Number.isFinite(from) || !Number.isFinite(to) || from <= 0 || to <= 0) return undefined;
		return {
			file,
			start: Math.min(from, to),
			end: Math.max(from, to),
			kind: from === to ? "cursor line" : "highlight",
		};
	}

	async function checkTrigger(): Promise<void> {
		const socket = run?.socket;
		if (!socket) return;
		const buffer = await readFile(triggerFile(socket)).catch(() => Buffer.alloc(0));
		const same = buffer.length >= readBytes && buffer.subarray(readBytes - readTail.length, readBytes).equals(readTail);
		if (!same) {
			readBytes = 0;
			readTail = Buffer.alloc(0);
		}
		const text = buffer.subarray(readBytes).toString("utf8");
		// Only whole lines are presses: a half-written one waits for the next poll.
		const end = text.lastIndexOf("\n");
		if (end < 0) return;
		readBytes += Buffer.byteLength(text.slice(0, end + 1));
		readTail = buffer.subarray(Math.max(0, readBytes - TAIL_BYTES), readBytes);
		for (const line of text.slice(0, end).split("\n")) {
			const press = parsePress(line);
			if (press) queue.push(press);
		}
		if (!queue.length) return;
		showQueue(sessionCtx);
		wake();
	}

	// Keeps the footer honest while the user edits and the loop's heartbeat fresh enough for the
	// key to accept presses; never wakes the agent.
	async function tick(ctx: ExtensionContext): Promise<void> {
		const socket = run?.socket;
		if (!socket) return;
		await writeFile(heartbeatFile(socket), "").catch(() => {});
		const state = await refresh();
		// /goal stop may have closed the loop while the query was in flight.
		if (!run) return;
		if (state) latest = state;
		setStatus(ctx, footer(state));
	}

	async function enable(ctx: ExtensionContext, goal: string): Promise<boolean> {
		const socket = await pickSocket();
		if (!socket) {
			ctx.ui.notify(
				`No Neovim socket for ${process.cwd()}. Start one there with \`nvim --listen /tmp/nvim\` or set PI_NVIM_SOCKET.`,
				"error",
			);
			return false;
		}
		run = { goal, socket };
		// Before the key exists, so the first press cannot look like a dead loop.
		await writeFile(heartbeatFile(socket), "").catch(() => {});
		latest = await refresh();
		if (!latest) {
			await close(ctx);
			ctx.ui.notify(`Neovim at ${socket} does not answer. Goal not started.`, "error");
			return false;
		}
		const mapping = await installMapping(socket);
		if (mapping === "failed") {
			await close(ctx);
			ctx.ui.notify(`Neovim at ${socket} did not take the ${TRIGGER_KEY} mapping. Goal not started.`, "error");
			return false;
		}
		// A key someone else owns does not stop the loop: :PiOptions still asks for options.
		if (!mapping.mapped) {
			ctx.ui.notify(
				mapping.command
					? `${TRIGGER_KEY} is already mapped in Neovim; use :PiOptions to ask for options.`
					: `${TRIGGER_KEY} is already mapped and :PiOptions is your own command; set PI_NVIM_GOAL_KEY to another key.`,
				"warning",
			);
		}
		setStatus(ctx, footer(latest));
		showQueue(ctx);
		pollTimer = setInterval(() => void tick(ctx), POLL_MS);
		triggerTimer = setInterval(() => void checkTrigger(), TRIGGER_POLL_MS);
		if (mapping.mapped) {
			const asks = mapping.command ? `${TRIGGER_KEY} or :PiOptions asks` : `${TRIGGER_KEY} asks`;
			ctx.ui.notify(`Goal loop on ${describe(focusOf(latest))}: ${goal}. ${asks} for options.`, "info");
		}
		return true;
	}

	async function select(choice: {
		options: string[];
		files: string[];
		lines: number[];
		prompt?: string;
		details?: string[];
		multi?: boolean;
		signal?: AbortSignal;
	}): Promise<{ chosen: string[] } | { feedback: string } | undefined> {
		const socket = run!.socket;
		const targets = choice.options.map((_, index) => ({ file: choice.files[index], line: choice.lines[index] }));
		const picker = pickerFile(socket);
		await writeFile(picker, PICKER_LUA);
		const lua = `dofile(${JSON.stringify(picker)})(_A[1], _A[2], _A[3], _A[4], _A[5])`;
		const args = [
			luaJson(choice.options),
			vimlString(choice.prompt ?? ""),
			luaJson(choice.details ?? []),
			choice.multi ? "1" : "0",
			luaJson(targets),
		].join(", ");
		const expr = `json_encode(luaeval(${vimlString(lua)}, [${args}]))`;
		const answer = JSON.parse(await nvimExpr(socket, expr, SELECT_TIMEOUT_MS, choice.signal)) as {
			indexes?: number[];
			text?: string;
		} | null;
		if (!answer) return undefined;
		if (answer.text) return { feedback: answer.text };
		const chosen: string[] = [];
		for (const index of answer.indexes ?? []) {
			const one = choice.options[index - 1];
			if (one !== undefined && !chosen.includes(one)) chosen.push(one);
		}
		return chosen.length ? { chosen } : undefined;
	}

	async function installMapping(socket: string): Promise<{ mapped: boolean; command: boolean } | "failed"> {
		// luaeval takes an expression, so the statements live inside an immediately invoked function.
		// No Lua comment may sit inside it: vimlString() flattens newlines, and -- would swallow
		// the rest of the install.
		const install = `(function()
			local key, file, beat, maxAge, desc, cmdDesc, block = _A[1], _A[2], _A[3], _A[4], _A[5], _A[6], _A[7]
			local function ask()
				local seen = vim.fn.getftime(beat)
				if seen < 0 or os.time() - seen > maxAge then
					vim.notify("pi: no /goal loop is listening here; run /goal again", vim.log.levels.WARN)
					return
				end
				local mode = vim.fn.mode()
				local visual = mode:match("^[vV]") ~= nil or mode:sub(1, 1) == block
				local first = visual and math.min(vim.fn.line("v"), vim.fn.line(".")) or vim.fn.line(".")
				local last = visual and math.max(vim.fn.line("v"), vim.fn.line(".")) or vim.fn.line(".")
				vim.fn.writefile({ vim.fn.expand("%:p") .. "\t" .. first .. "\t" .. last }, file, "a")
				if visual then
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
				end
				vim.notify("pi: options requested", vim.log.levels.INFO)
			end
			local cmd = vim.api.nvim_get_commands({}).PiOptions
			local own = cmd == nil or cmd.definition == cmdDesc
			if own then
				vim.api.nvim_create_user_command("PiOptions", ask, { force = true, desc = cmdDesc })
			end
			local existing = vim.fn.maparg(key, "n", false, true)
			if next(existing) ~= nil and existing.desc ~= desc then
				vim.notify("pi: " .. key .. " is taken, use :PiOptions", vim.log.levels.WARN)
				return { mapped = false, command = own }
			end
			vim.keymap.set({ "n", "i", "v" }, key, ask, { desc = desc, silent = true })
			return { mapped = true, command = own }
		end)()`;
		const args = [
			vimlString(TRIGGER_KEY),
			vimlString(triggerFile(socket)),
			vimlString(heartbeatFile(socket)),
			HEARTBEAT_MAX_S,
			vimlString(MAP_DESC),
			vimlString(CMD_DESC),
			vimlString(BLOCK_VISUAL),
		].join(", ");
		const expr = `json_encode(luaeval(${vimlString(install)}, [${args}]))`;
		try {
			const answer = JSON.parse(await nvimExpr(socket, expr)) as { mapped: boolean; command: boolean } | null;
			if (!answer) return "failed";
			return { mapped: answer.mapped, command: answer.command };
		} catch {
			return "failed";
		}
	}

	async function removeMapping(socket: string): Promise<void> {
		const remove = `(function()
			local key, desc, cmdDesc = _A[1], _A[2], _A[3]
			local existing = vim.fn.maparg(key, "n", false, true)
			if existing.desc == desc then
				pcall(vim.keymap.del, { "n", "i", "v" }, key)
			end
			local cmd = vim.api.nvim_get_commands({}).PiOptions
			if cmd ~= nil and cmd.definition == cmdDesc then
				pcall(vim.api.nvim_del_user_command, "PiOptions")
			end
		end)()`;
		const args = [vimlString(TRIGGER_KEY), vimlString(MAP_DESC), vimlString(CMD_DESC)].join(", ");
		const expr = `luaeval(${vimlString(remove)}, [${args}])`;
		await nvimExpr(socket, expr).catch(() => {});
	}

	pi.on("agent_settled", () => {
		answering = undefined;
		wake();
	});

	pi.on("before_agent_start", (event) => {
		if (!run || !latest) return;
		const anchor = `Neovim focus: ${describe(focusOf(latest))}.`;
		event.systemPromptOptions.sections.goal = `${protocol(TRIGGER_KEY)}\nActive goal, in the user's own words: ${run.goal}\n${anchor}`;
	});

	pi.on("session_shutdown", (_event, ctx) => {
		sessionCtx = undefined;
		void close(ctx);
	});

	pi.registerCommand("goal", {
		description: "Run one goal in Neovim: /goal <goal> (free text), or /goal stop",
		handler: async (args, ctx) => {
			sessionCtx = ctx;
			const goal = args.trim();
			if (goal === "stop") {
				if (!run) {
					ctx.ui.notify("No goal loop is running", "info");
					return;
				}
				await close(ctx);
				ctx.ui.notify("Goal loop stopped; Neovim connection closed", "info");
				return;
			}
			if (!goal) {
				ctx.ui.notify(run ? `Active goal: ${run.goal}` : "Usage: /goal <goal> | /goal stop", "info");
				return;
			}
			await close(ctx);
			if (!(await enable(ctx, goal))) return;
			pi.sendUserMessage(`Goal: ${goal}`);
		},
	});

	pi.registerTool({
		name: "nvim_select",
		label: "Neovim select",
		description:
			"Ask the user to pick one option in their running Neovim: a panel opens on the bottom edge, they move with j/k or the arrow keys, see the preview of the highlighted option, and confirm with Enter (Esc cancels). While an option is highlighted the buffer jumps to its file and line; once the user answers, the buffer and view return to where they were. A final row (or i / e) lets them type instead. The call blocks until they answer.",
		parameters: {
			type: "object",
			properties: {
				prompt: { type: "string", description: "Question shown above the options in Neovim." },
				options: { type: "array", items: { type: "string" }, description: "Options to choose from, one line each." },
				multi: {
					type: "boolean",
					description:
						"Let the user pick several options: Space or x toggles the highlighted one, Enter confirms all of them.",
				},
				details: {
					type: "array",
					items: { type: "string" },
					description:
						"Optional preview per option, same order: the resulting code or a short -/+ diff, one row per line. Shown under the list while that option is highlighted.",
				},
				lines: {
					type: "array",
					items: { type: "number" },
					description:
						"The line that option changes, one per option in the same order.",
				},
				files: {
					type: "array",
					items: { type: "string" },
					description:
						"The file that line belongs to, one absolute path per option in the same order.",
				},
			},
			required: ["options", "lines", "files"],
			additionalProperties: false,
		},
		annotations: { readOnlyHint: true },
		async execute(_toolCallId, raw, signal) {
			if (!run) throw new Error("Run /goal <goal> first: no Neovim connection is open.");
			const args = raw as {
				prompt?: string;
				options?: unknown;
				details?: unknown;
				lines?: unknown;
				files?: unknown;
				multi?: unknown;
			};
			const options = Array.isArray(args.options) ? args.options.map((option) => String(option)) : [];
			if (options.length === 0) throw new Error("nvim_select needs at least one option.");
			const details = Array.isArray(args.details) ? args.details.map((detail) => String(detail)) : undefined;
			const files = Array.isArray(args.files) ? args.files.map((file) => String(file)) : [];
			const lines = Array.isArray(args.lines) ? args.lines.map((line) => Number(line)) : [];
			if (files.length !== options.length || lines.length !== options.length || lines.some((line) => !Number.isFinite(line))) {
				throw new Error(
					`nvim_select needs one file and one line per option: ${options.length} options, ${files.length} files, ${lines.length} lines.`,
				);
			}
			const picked = await select({ options, prompt: args.prompt, details, files, lines, multi: args.multi === true, signal });
			const text = !picked
				? "The user cancelled the selection in Neovim."
				: "feedback" in picked
					? `The user typed instead of picking: ${picked.feedback}`
					: `The user selected: ${picked.chosen.join("; ")}`;
			return { content: [{ type: "text", text }], details: undefined };
		},
	});

	pi.registerTool({
		name: "goal_done",
		label: "Goal done",
		description:
			"Close the active Neovim goal loop: report the summary to the user, unmap the key and close the connection.",
		parameters: {
			type: "object",
			properties: { summary: { type: "string", description: "What was achieved, or why the loop stops." } },
			required: ["summary"],
			additionalProperties: false,
		},
		async execute(_toolCallId, raw) {
			const summary = String((raw as { summary?: string }).summary ?? "").trim();
			if (!run) return { content: [{ type: "text", text: "No goal loop is active." }], details: undefined };
			// The loop has nothing to close before the first key press; only /goal stop ends it then.
			if (lastWakeAt === 0) {
				return {
					content: [{ type: "text", text: `The loop is still waiting for ${TRIGGER_KEY}; nothing to close.` }],
					details: undefined,
				};
			}
			await close(sessionCtx);
			pi.sendMessage({ customType: "goal-done", content: `Goal closed: ${summary}`, display: true });
			return { content: [{ type: "text", text: "Goal loop closed." }], details: undefined };
		},
	});
}
