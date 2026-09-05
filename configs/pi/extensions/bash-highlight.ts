// bash-highlight - 给内置 bash 工具的调用显示加上 shell 关键词高亮。
// 执行逻辑完全委托内置 bash 工具（createBashTool），只覆盖 renderCall；
// renderResult 省略，自动沿用内置渲染（输出、耗时、截断提示等）。
//
// 高亮是手写的轻量 tokenizer（关键词/内建命令/命令名/字符串/注释/变量/数字），
// 颜色全部取自当前主题的 syntax* 键，无第三方依赖。

import { createBashTool, type ExtensionAPI, type Theme } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

const KEYWORDS = new Set([
	"if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
	"case", "esac", "in", "function", "select", "time", "coproc",
]);

const BUILTINS = new Set([
	"echo", "printf", "cd", "pwd", "export", "local", "declare", "typeset", "readonly",
	"set", "unset", "shift", "return", "exit", "source", "alias", "unalias",
	"bg", "fg", "jobs", "kill", "wait", "trap", "eval", "exec", "umask", "test",
	"read", "let", "true", "false", "type", "hash", "pushd", "popd", "dirs",
	"command", "builtin", "getopts", "break", "continue",
]);

// 顺序即优先级：注释 > 字符串 > 变量 > 命令分隔符 > 重定向 > ! [ ] > 数字 > 单词
const TOKEN_RE =
	/(#.*$)|('[^']*'|"(?:[^"\\]|\\.)*")|(\$(?:\w+|\{[^}]*\}|\S))|(\|\||&&|[|;&()])|(\d*(?:>>|<<|<|>)\&?\d*)|(!|\[|\])|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][\w.-]*)/y;

function highlightShell(code: string, theme: Theme): string {
	let out = "";
	for (const line of code.split("\n")) {
		let expectCommand = true; // 行首、命令分隔符之后的一个词是命令名
		let cursor = 0;

		while (cursor < line.length) {
			TOKEN_RE.lastIndex = cursor;
			const m = TOKEN_RE.exec(line);
			if (!m) {
				// 空格、通配符等非 token 字符原样跳过
				out += line[cursor];
				cursor++;
				continue;
			}
			const [raw, comment, str, variable, separator, redirect, bracket, number, word] = m;
			if (comment !== undefined) {
				out += theme.fg("syntaxComment", raw);
				break; // 注释到行尾
			} else if (str !== undefined) {
				out += theme.fg("syntaxString", raw);
				expectCommand = false;
			} else if (variable !== undefined) {
				out += theme.fg("syntaxVariable", raw);
				expectCommand = false;
			} else if (separator !== undefined) {
				out += theme.fg("syntaxOperator", raw);
				expectCommand = true;
			} else if (redirect !== undefined) {
				out += theme.fg("syntaxOperator", raw);
				expectCommand = false; // 重定向后跟的是文件名
			} else if (bracket !== undefined) {
				out += bracket === "!" ? theme.fg("syntaxKeyword", raw) : theme.fg("syntaxType", raw);
			} else if (number !== undefined) {
				out += theme.fg("syntaxNumber", raw);
				expectCommand = false;
			} else if (word !== undefined) {
				if (expectCommand && KEYWORDS.has(word)) {
					out += theme.fg("syntaxKeyword", raw);
				} else if (expectCommand && BUILTINS.has(word)) {
					out += theme.fg("syntaxType", raw);
				} else if (expectCommand) {
					out += theme.fg("syntaxFunction", raw);
				} else {
					out += raw;
				}
				expectCommand = false;
			}
			cursor = TOKEN_RE.lastIndex;
		}
		out += "\n";
	}
	return out.slice(0, -1);
}

export default function (pi: ExtensionAPI) {
	const bash = createBashTool(process.cwd());

	pi.registerTool({
		name: "bash",
		label: bash.label,
		description: bash.description,
		parameters: bash.parameters,
		promptSnippet: (bash as any).promptSnippet,
		promptGuidelines: (bash as any).promptGuidelines,

		async execute(toolCallId, params, signal, onUpdate, _ctx) {
			return bash.execute(toolCallId, params, signal, onUpdate);
		},

		renderCall(args, theme, context) {
			// 与内置 renderCall 一致：记录执行开始时间，供内置 renderResult 显示耗时
			const state = context.state;
			if (context.executionStarted && state.startedAt === undefined) {
				state.startedAt = Date.now();
				state.endedAt = undefined;
			}

			const command = typeof args?.command === "string" ? args.command : "";
			const timeout = typeof args?.timeout === "number" ? args.timeout : undefined;

			const prefix = theme.fg("muted", theme.bold("\uf120 "));
			const body = command ? highlightShell(command, theme) : theme.fg("toolOutput", "...");
			const suffix = timeout ? theme.fg("muted", ` (timeout ${timeout}s)`) : "";
			return new Text(prefix + body + suffix, 0, 0);
		},
	});
}
