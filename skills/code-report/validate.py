#!/usr/bin/env python3
"""校验 code-report 里的代码块引用。

用法: validate.py <report.md>
caption 形如 `path:start-end` 或 `path:line`（反引号包裹，独占一行，位于块上方）。
带语言标注的 fenced block 缺 caption、caption 目标文件不存在、行号越界、
或块内容与引用的源文件行不一致时，逐条列出并退出码 1。
"""
import os
import re
import sys

CAPTION = re.compile(r"`([^`\s]+):(\d+)(?:-(\d+))?`")
CAPTION_LINE = re.compile(r"^[\s`*_]*`([^`\s]+):(\d+)(?:-(\d+))?`[\s`*_]*$")
FENCE = re.compile(r"^\s*(`{3,}|~{3,})\s*(\S*)")


def caption_line_above(lines, idx):
    for prev in reversed(lines[:idx]):
        if prev.strip():
            return CAPTION_LINE.match(prev)
    return None


def check_body(cap, body, base, problems):
    path, start, end, report_line = cap
    full = os.path.join(base, path)
    if not os.path.isfile(full):
        return  # caption 行已报告目标不存在
    with open(full, encoding="utf-8", errors="replace") as f:
        src = f.read().splitlines()
    if start > end or end > len(src):
        return  # caption 行已报告行号越界
    cited = src[start - 1 : end]
    if len(body) != len(cited):
        problems.append(
            (
                report_line,
                f"行数不一致: {path}:{start}-{end} 引用 {len(cited)} 行, 块内 {len(body)} 行",
            )
        )
        return
    for k, (block_line, src_line) in enumerate(zip(body, cited)):
        if block_line != src_line:
            problems.append(
                (
                    report_line,
                    f"内容不一致: {path}:{start}-{end} 块内第 {k + 1} 行与源文件不符",
                )
            )
            return


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: validate.py <report.md>")
    report = sys.argv[1]
    base = os.path.dirname(os.path.abspath(report))
    problems = []
    with open(report, encoding="utf-8") as f:
        lines = f.read().splitlines()

    in_block = False
    body = []
    cap = None
    for i, line in enumerate(lines):
        fence = FENCE.match(line)
        if fence:
            if not in_block:
                m = caption_line_above(lines, i)
                if fence.group(2) and not m:
                    problems.append((i + 1, "代码块缺少 caption"))
                if m:
                    cap = (m.group(1), int(m.group(2)), int(m.group(3) or m.group(2)), i + 1)
                else:
                    cap = None
                body = []
            elif cap:
                check_body(cap, body, base, problems)
            in_block = not in_block
            continue
        if in_block:
            body.append(line)
            continue
        for path, start, end in CAPTION.findall(line):
            if "://" in path:
                continue
            start, end = int(start), int(end or start)
            full = os.path.join(base, path)
            if not os.path.isfile(full):
                problems.append((i + 1, f"目标不存在: {path}"))
                continue
            with open(full, encoding="utf-8", errors="replace") as f:
                total = sum(1 for _ in f)
            if start > end or end > total:
                problems.append(
                    (i + 1, f"行号越界: {path}:{start}-{end} (文件共 {total} 行)")
                )

    for line_no, msg in problems:
        print(f"{report}:{line_no}: {msg}")
    if problems:
        sys.exit(1)
    print(f"OK: 全部代码块引用有效 ({report})")


if __name__ == "__main__":
    main()
