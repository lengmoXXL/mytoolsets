#!/usr/bin/env python3
# sync: skip
"""配置 dsh 的 provider API key（只动 refs 段里 REFS 表列出的那些行）。

dsh 的凭据文档是 $DSH_HOME/.credentials.yaml（version: 1 的 refs / records 两段，dsh 监听其变化）。
本脚本只替换表里列出的 ref 行，其余内容原样保留；密钥从 .secrets 解析：

    python3 install/dsh-auth.py                             # 补齐表里所有 ref（已有则不动）
    python3 install/dsh-auth.py --ref QWEN_TOKEN_PLAN_CN_API_KEY
    python3 install/dsh-auth.py --update                    # 与 .secrets 不一致时确认后覆盖
    python3 install/dsh-auth.py --remove [--ref NAME]       # 删除（不给 --ref 则删表里所有）
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# dsh refs 段里的名字 -> .secrets/ai-providers.json 里的键
REFS = {
    "DEEPSEEK_API_KEY": "deepseek",
    "QWEN_TOKEN_PLAN_CN_API_KEY": "qwen-token-plan-cn",
}
FILE_MODE = 0o600


def credentials_path() -> Path:
    return Path(os.environ.get("DSH_HOME") or "~/.dsh").expanduser() / ".credentials.yaml"


def secrets_path() -> Path:
    root = Path(__file__).resolve().parents[1]
    return Path(os.environ.get("SECRETS_DIR", root / ".secrets")).expanduser() / "ai-providers.json"


def secrets_key(name: str) -> str:
    with secrets_path().open("r", encoding="utf-8") as fh:
        keys = json.load(fh)
    api_key = keys.get(name)
    if not isinstance(api_key, str) or not api_key:
        raise ValueError(f"缺少密钥 {name}")
    return api_key


def ref_line(ref: str, value: str) -> str:
    return f"  {ref}: '{value.replace(chr(39), chr(39) * 2)}'\n"


def read_ref(lines: list[str], ref: str) -> str | None:
    for line in lines:
        if line.startswith(f"  {ref}:"):
            value = line.split(":", 1)[1].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
                value = value[1:-1].replace("''", "'")
            return value
    return None


def drop_empty_refs(lines: list[str]) -> list[str]:
    """refs 段清空后删掉 `refs:` 这一行：YAML 里空值不是空映射。"""
    for index, line in enumerate(lines):
        if line.rstrip() != "refs:":
            continue
        following = [item for item in lines[index + 1 :] if item.strip()]
        if following and following[0].startswith("  "):
            return lines
        return lines[:index] + lines[index + 1 :]
    return lines


def confirm(prompt: str) -> bool:
    try:
        answer = input(prompt)
    except EOFError:
        answer = ""
    return answer.strip().lower() in ("y", "yes")


def write_document(target: Path, lines: list[str]) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".yaml.tmp")
    temporary.write_text("".join(lines), encoding="utf-8")
    temporary.chmod(FILE_MODE)
    os.replace(temporary, target)


def remove(target: Path, lines: list[str], refs: list[str]) -> int:
    present = [ref for ref in refs if read_ref(lines, ref) is not None]
    if not present:
        print(f"未安装: {target} 中没有 {', '.join(refs)}")
        return 0
    print(f"将删除: {', '.join(present)}")
    if not confirm("确认删除以上 key? [y/N] "):
        print("已取消")
        return 0
    kept = [line for line in lines if not any(line.startswith(f"  {ref}:") for ref in present)]
    write_document(target, drop_empty_refs(kept))
    print(f"removed: {target}")
    return 0


def install(target: Path, lines: list[str], refs: list[str], update: bool) -> int:
    if update and not target.exists():
        print(f"未安装，跳过: {target}")
        return 0

    additions: list[tuple[str, str]] = []
    overrides: list[tuple[str, str]] = []
    for ref in refs:
        api_key = secrets_key(REFS[ref])
        current = read_ref(lines, ref)
        if current == api_key:
            print(f"已是最新: {ref}")
        elif current is None:
            print(f"将补充: {ref}")
            additions.append((ref, api_key))
        elif not update:
            print(f"{target} 中的 {ref} 与 .secrets 不一致，用 --update 覆盖")
        else:
            print(f"将覆盖: {ref}")
            if confirm(f"应用 {ref} 的变更? [y/N] "):
                overrides.append((ref, api_key))
            else:
                print("已取消")

    if not additions and not overrides:
        return 0

    for ref, api_key in overrides:
        for index, line in enumerate(lines):
            if line.startswith(f"  {ref}:"):
                lines[index] = ref_line(ref, api_key)
                break

    if additions:
        for index, line in enumerate(lines):
            if line.rstrip() == "refs:":
                lines[index + 1 : index + 1] = [ref_line(ref, key) for ref, key in additions]
                break
        else:
            if lines and lines[-1].strip() != "":
                lines.append("\n")
            if not any(line.startswith("version:") for line in lines):
                lines.insert(0, "version: 1\n")
            lines.append("refs:\n")
            lines.extend(ref_line(ref, key) for ref, key in additions)

    write_document(target, lines)
    print(f"installed: {target}")
    return 0


def main() -> int:
    try:
        args = sys.argv[1:]
        names: list[str] = []
        for index, arg in enumerate(args):
            if arg == "--ref":
                names.append(args[index + 1])
            elif arg.startswith("--ref="):
                names.append(arg.split("=", 1)[1])
        unknown = [name for name in names if name not in REFS]
        if unknown:
            raise ValueError(f"未知 ref: {', '.join(unknown)}（可选: {', '.join(REFS)}）")
        refs = names or list(REFS)

        target = credentials_path()
        lines: list[str] = []
        if target.exists():
            lines = target.read_text(encoding="utf-8").splitlines(keepends=True)
        if "--remove" in args:
            return remove(target, lines, refs)
        return install(target, lines, refs, "--update" in args)
    except (OSError, ValueError, TypeError, IndexError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
