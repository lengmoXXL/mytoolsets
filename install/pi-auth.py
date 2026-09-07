#!/usr/bin/env python3
# sync: skip
"""Install Pi auth (configs/pi/auth.json → ~/.pi/agent/auth.json)，密钥从 .secrets 解析。

合并语义：只补充目标缺失的 provider 条目，不覆盖已有条目——auth.json 里的
token/刷新状态由 pi 运行时维护，覆盖会丢掉已登录状态。需要更新时手动执行：

    python3 install/pi-auth.py --update

卸载（删除本脚本管理的 key，保留其余条目）：

    python3 install/pi-auth.py --remove
"""

import json
import os
import sys
from pathlib import Path

UPDATE = "--update" in sys.argv


def remove() -> int:
    """从 ~/.pi/agent/auth.json 删除 configs/pi/auth.json 列出的所有 key。"""
    try:
        root = Path(__file__).resolve().parents[1]
        source = root / "configs" / "pi" / "auth.json"

        with source.open("r", encoding="utf-8") as fh:
            auth = json.load(fh)

        target = Path.home() / ".pi" / "agent" / "auth.json"
        if not target.exists():
            print(f"未安装: {target}")
            return 0
        with target.open("r", encoding="utf-8") as fh:
            existing = json.load(fh)

        found = [name for name in auth if name in existing]
        if not found:
            print(f"未安装: {target} 中没有本脚本管理的 key")
            return 0
        print(f"将删除: {', '.join(sorted(found))}")
        try:
            answer = input("确认删除以上 key? [y/N] ")
        except EOFError:
            answer = ""
        if answer.strip().lower() not in ("y", "yes"):
            print("已取消")
            return 0

        for name in found:
            del existing[name]
        target.write_text(
            json.dumps(existing, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        target.chmod(0o600)
        print(f"removed: {target}")
        return 0
    except (KeyError, OSError, TypeError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


def main() -> int:
    if "--remove" in sys.argv[1:]:
        return remove()
    try:
        root = Path(__file__).resolve().parents[1]
        source = root / "configs" / "pi" / "auth.json"
        secrets_dir = Path(os.environ.get("SECRETS_DIR", root / ".secrets")).expanduser()

        with (secrets_dir / "ai-providers.json").open("r", encoding="utf-8") as fh:
            api_keys = json.load(fh)
        with source.open("r", encoding="utf-8") as fh:
            auth = json.load(fh)

        def resolve(reference: str, owner: str) -> str:
            if (
                not isinstance(reference, str)
                or not reference.startswith("${")
                or not reference.endswith("}")
            ):
                raise ValueError(f"{owner}: apiKey must be a ${{provider}} reference")
            api_key = api_keys.get(reference[2:-1])
            if not isinstance(api_key, str) or not api_key:
                raise ValueError(f"{owner}: missing API key {reference[2:-1]}")
            return api_key

        for auth_name, entry in auth.items():
            entry["key"] = resolve(entry["key"], f"auth {auth_name}")

        target_dir = Path.home() / ".pi" / "agent"
        if UPDATE and not target_dir.exists():
            print(f"未安装，跳过: {target_dir}")
            return 0
        target = target_dir / "auth.json"
        existing = {}
        if target.exists():
            with target.open("r", encoding="utf-8") as fh:
                existing = json.load(fh)

        additions = {name: entry for name, entry in auth.items() if name not in existing}
        if not additions:
            print(f"已是最新: {target}")
            return 0
        print(f"将补充: {', '.join(sorted(additions))}")
        if UPDATE:
            try:
                answer = input("应用以上变更? [y/N] ")
            except EOFError:
                answer = ""
            if answer.strip().lower() not in ("y", "yes"):
                print("已取消")
                return 0

        merged = {**existing, **additions}
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        target.chmod(0o600)
        print(f"installed: {target}")
        return 0
    except (KeyError, OSError, TypeError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
