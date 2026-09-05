// Flat Codex-like input editor for pi.
// Always padded with one empty row above and below,
// "› " prompt on the first content row, gray background block.

import { CustomEditor, UserMessageComponent, type ExtensionAPI, type KeybindingsManager, type Theme } from "@earendil-works/pi-coding-agent";
import { visibleWidth, type EditorTheme, type TUI } from "@earendil-works/pi-tui";

const PROMPT = "› ";
const BG = "\x1b[48;2;51;51;51m"; // #333333
const BG_RESET = "\x1b[49m";
const SGR_RESET = "\x1b[0m";

// There is no extension hook for the built-in user message component, so patch the
// shared class prototype. The record lives on the prototype (keyed by Symbol.for)
// so an extension reload swaps the theme getter instead of stacking wrappers.
const USER_MESSAGE_PATCH = Symbol.for("flat-editor.user-message-patch");

type UserMessagePatch = { getTheme: () => Theme };

function patchUserMessageComponent(ui: { readonly theme: Theme }) {
	const proto = UserMessageComponent.prototype as {
		render(width: number): string[];
		[USER_MESSAGE_PATCH]?: UserMessagePatch;
	};
	const record = proto[USER_MESSAGE_PATCH];
	if (record) {
		record.getTheme = () => ui.theme;
		return;
	}
	const original = proto.render;
	proto[USER_MESSAGE_PATCH] = { getTheme: () => ui.theme };
	proto.render = function (width: number): string[] {
		const patch = proto[USER_MESSAGE_PATCH]!;
		// The component already left-pads content by outputPad (0 or 1); reserve only the
		// remaining columns so prompt + padding total 2, matching the editor's "› "
		const { outputPad } = this as { outputPad?: number };
		const prefixWidth = Math.max(0, PROMPT.length - (typeof outputPad === "number" ? outputPad : 1));
		const lines = original.call(this, Math.max(1, width - prefixWidth));
		return lines.map((line, i) => {
			// pi puts OSC 133 markers on the first and last rendered rows; keep them at line start
			let osc = "";
			if (i === 0 || i === lines.length - 1) {
				const match = line.match(/^(\x1b\]133;[ABC]\x07)+/);
				if (match) {
					osc = match[0];
					line = line.slice(osc.length);
				}
			}
			// Row 0 is the top padding row; the prompt sits on the first content row
			const prefix = (i === 1 ? PROMPT : " ".repeat(PROMPT.length)).slice(0, prefixWidth);
			return osc + (prefix ? patch.getTheme().bg("userMessageBg", prefix) : "") + line;
		});
	};
}

// On exit pi overwrites the fake cursor cell with a plain space (default background),
// which punches a black hole in the gray block; repaint that space with our background.
const TUI_STOP_PATCH = Symbol.for("flat-editor.tui-stop-patch");

function patchTuiStop(tui: TUI) {
	const patched = tui as TUI & { [TUI_STOP_PATCH]?: boolean };
	if (patched[TUI_STOP_PATCH]) return;
	patched[TUI_STOP_PATCH] = true;
	const original = tui.stop.bind(tui);
	tui.stop = (options): void => {
		const { terminal } = tui;
		const originalWrite = terminal.write.bind(terminal);
		terminal.write = (data: string) => originalWrite(data === " " ? BG + " " + BG_RESET : data);
		try {
			original(options);
		} finally {
			terminal.write = originalWrite;
		}
	};
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		patchUserMessageComponent(ctx.ui);
		class FlatEditor extends CustomEditor {
			constructor(tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) {
				super(tui, theme, keybindings, { paddingX: 0 });
			}

			render(width: number): string[] {
				const promptWidth = 2; // "› "
				const textWidth = Math.max(1, width - promptWidth);
				const raw = super.render(textWidth);
				// Default editor emits [top border, ...content, bottom border, ...autocomplete rows];
				// borders sit at fixed positions: first line, and right before the autocomplete rows
				const { autocompleteState, autocompleteList } = this as unknown as {
					autocompleteState?: unknown;
					autocompleteList?: { render(width: number): string[] };
				};
				const autocompleteRows =
					autocompleteState && autocompleteList ? autocompleteList.render(textWidth).length : 0;
				const bottomBorder = raw.length - autocompleteRows - 1;
				let content = [...raw.slice(1, bottomBorder), ...raw.slice(bottomBorder + 1)];

				// Always keep one empty row above and below so the block breathes;
				// padding wraps the whole block, so the autocomplete menu stays attached to the text
				content = ["", ...content, ""];

				// Prompt fixed on the first text row (row 0 is padding)
				const promptRow = 1;

				return content.map((line, i) => {
					const prompt = i === promptRow ? PROMPT : "  ";
					// Inner SGR resets would clear our background; re-apply it after each one
					const restored = line.replaceAll(SGR_RESET, SGR_RESET + BG);
					const pad = " ".repeat(Math.max(0, textWidth - visibleWidth(line)));
					return BG + prompt + restored + BG + pad + BG_RESET;
				});
			}
		}

		ctx.ui.setEditorComponent((tui, theme, keybindings) => {
			patchTuiStop(tui);
			return new FlatEditor(tui, theme, keybindings);
		});
	});
}
