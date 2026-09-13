#!/usr/bin/env python3
# sync: skip
"""配置 dsh 的 DeepSeek API key（只动 DEEPSEEK_API_KEY）。

dsh 的凭据文档是 $DSH_HOME/.credentials.yaml（version: 1 的 refs / records 两段，dsh 监听其变化）。
本脚本只替换 refs 段里的 DEEPSEEK_API_KEY 一行，其余内容原样保留；密钥从 .secrets 解析：

    python3 install/dsh-auth.py            # 补齐 DEEPSEEK_API_KEY（已有则不动）
    python3 install/dsh-auth.py --update   # 与 .secrets 不一致时确认后覆盖
    python3 install/dsh-auth.py --remove   # 删除 DEEPSEEK_API_KEY
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

REF_NAME = "DEEPSEEK_API_KEY"
SECRET_NAME = "deepseek"
FILE_MODE = 0o600


def credentials_path() -> Path:
    return Path(os.environ.get("DSH_HOME") or "~/.dsh").expanduser() / ".credentials.yaml"


def secrets_key() -> str:
    root = Path(__file__).resolve().parents[1]
    secrets_dir = Path(os.environ.get("SECRETS_DIR", root / ".secrets")).expanduser()
    with (secrets_dir / "ai-providers.json").open("r", encoding="utf-8") as fh:
        keys = json.load(fh)
    api_key = keys.get(SECRET_NAME)
    if not isinstance(api_key, str) or not api_key:
        raise ValueError(f"缺少密钥 {SECRET_NAME}")
    return api_key


def ref_line(value: str) -> str:
    return f"  {REF_NAME}: '{value.replace(chr(39), chr(39) * 2)}'\n"


def read_ref(lines: list[str]) -> str | None:
    for line in lines:
        if line.startswith(f"  {REF_NAME}:"):
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


def remove(target: Path, lines: list[str]) -> int:
    if read_ref(lines) is None:
        print(f"未安装: {target} 中没有 {REF_NAME}")
        return 0
    print(f"将删除: {REF_NAME}")
    if not confirm("确认删除以上 key? [y/N] "):
        print("已取消")
        return 0
    kept = [line for line in lines if not line.startswith(f"  {REF_NAME}:")]
    write_document(target, drop_empty_refs(kept))
    print(f"removed: {target}")
    return 0


def install(target: Path, lines: list[str], update: bool) -> int:
    if update and not target.exists():
        print(f"未安装，跳过: {target}")
        return 0

    api_key = secrets_key()
    current = read_ref(lines)
    if current == api_key:
        print(f"已是最新: {target}")
        return 0
    if current is not None:
        if not update:
            print(f"{target} 中的 {REF_NAME} 与 .secrets 不一致，用 --update 覆盖")
            return 0
        print(f"将覆盖: {REF_NAME}")
        if not confirm("应用以上变更? [y/N] "):
            print("已取消")
            return 0
    else:
        print(f"将补充: {REF_NAME}")

    if current is not None:
        for index, line in enumerate(lines):
            if line.startswith(f"  {REF_NAME}:"):
                lines[index] = ref_line(api_key)
                break
    else:
        for index, line in enumerate(lines):
            if line.rstrip() == "refs:":
                lines.insert(index + 1, ref_line(api_key))
                break
        else:
            if lines and lines[-1].strip() != "":
                lines.append("\n")
            if not any(line.startswith("version:") for line in lines):
                lines.insert(0, "version: 1\n")
            lines.append("refs:\n")
            lines.append(ref_line(api_key))

    write_document(target, lines)
    print(f"installed: {target}")
    return 0


def main() -> int:
    try:
        target = credentials_path()
        lines: list[str] = []
        if target.exists():
            lines = target.read_text(encoding="utf-8").splitlines(keepends=True)
        if "--remove" in sys.argv[1:]:
            return remove(target, lines)
        return install(target, lines, "--update" in sys.argv[1:])
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
