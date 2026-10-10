#!/bin/bash
# 安装/更新 Codex refine 循环：Stop hook 脚本、结构化评审 schema、codex-refine 命令，
# 并把 Stop hook 合并进 ~/.codex/hooks.json（与已有的 hook 共存）
# 依赖 Codex CLI（install/codex.sh）；hook 首次生效需要在 Codex 里确认 hook 信任

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../configs/codex-refine"

HOOK_DIR="$HOME/.codex/hooks"
STATE_DIR="$HOME/.codex/refine"
HOOKS_JSON="$HOME/.codex/hooks.json"
REFINE_BIN="$HOME/.local/bin/codex-refine"
BLOCK_NAME="codex-refine"

HOOK_SCRIPT="$HOOK_DIR/refine-stop.sh"
HOOK_COMMAND="bash '$HOOK_SCRIPT'"

usage() {
    cat <<EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 refine 循环（hooks.json 里的声明、hook 脚本、codex-refine 与状态目录）
  --update  更新已安装的部分（未安装则跳过）
EOF
}

UPDATE=0
REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE=1
            ;;
        --update)
            UPDATE=1
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

# merge_hooks_json <merge|remove>: 在 hooks.json 里增删我们的 Stop hook 条目，
# 其余 hook 原样保留；内容一致跳过，--update 下不一致先确认
merge_hooks_json() {
    local mode="$1" tmp status
    tmp="$(mktemp)"
    set +e
    python3 - "$HOOKS_JSON" "$HOOK_COMMAND" "$mode" "$tmp" <<'PY'
import json, os, sys

path, command, mode, out_path = sys.argv[1:5]

if not os.path.exists(path):
    if mode == "remove":
        sys.exit(0)
    data = {}
else:
    with open(path) as handle:
        text = handle.read()
    data = json.loads(text) if text.strip() else {}

stop_groups = data.get("hooks", {}).get("Stop", [])
kept = [
    group
    for group in stop_groups
    if not any(command in hook.get("command", "") for hook in group.get("hooks", []))
]
groups = kept
if mode == "merge":
    groups = kept + [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": command,
                    "timeout": 3600,
                    "statusMessage": "refine: checking the acceptance criteria",
                }
            ]
        }
    ]

if data.get("hooks", {}).get("Stop", []) == groups:
    sys.exit(0)

data.setdefault("hooks", {})["Stop"] = groups
with open(out_path, "w") as handle:
    handle.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
sys.exit(3)
PY
    status=$?
    set -e
    case "$status" in
        0)
            rm -f "$tmp"
            if [[ "$REMOVE" == "1" ]] && [[ ! -f "$HOOKS_JSON" ]]; then
                return
            fi
            echo "$HOOKS_JSON ($BLOCK_NAME) 未变化"
            ;;
        3)
            if [[ "$UPDATE" == "1" ]] && ! confirm_update "$HOOKS_JSON ($BLOCK_NAME)"; then
                rm -f "$tmp"
                return
            fi
            mv "$tmp" "$HOOKS_JSON"
            echo "$HOOKS_JSON ($BLOCK_NAME) 已更新"
            ;;
        *)
            rm -f "$tmp"
            echo "错误: 合并 $HOOKS_JSON 失败" >&2
            exit 1
            ;;
    esac
}

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "Codex refine 循环" || exit 0
    merge_hooks_json remove
    remove_file "$REFINE_BIN"
    remove_file "$HOOK_SCRIPT"
    remove_file "$HOOK_DIR/findings.schema.json"
    remove_dir "$STATE_DIR"
    exit 0
fi

for dep in python3 mktemp; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

if ! command -v codex &>/dev/null && [[ ! -x "$HOME/.local/bin/codex" ]]; then
    echo "错误: 缺少 Codex CLI，请先运行 install/codex.sh"
    exit 1
fi

if [[ "$UPDATE" == "1" ]] && [[ ! -e "$REFINE_BIN" ]]; then
    echo "未安装，跳过: codex-refine"
    exit 0
fi

# install_file <源> <目标> <权限>: 内容一致跳过，--update 下不一致先确认
install_file() {
    local source="$1" dest="$2" mode="$3" tmp
    tmp="$(mktemp)"
    cp "$source" "$tmp"
    write_file_if_changed "$dest" "$tmp"
    chmod "$mode" "$dest"
}

mkdir -p "$HOOK_DIR" "$STATE_DIR" "$(dirname "$REFINE_BIN")"
install_file "$SOURCE_DIR/refine-stop.sh" "$HOOK_SCRIPT" 755
install_file "$SOURCE_DIR/findings.schema.json" "$HOOK_DIR/findings.schema.json" 644
install_file "$SOURCE_DIR/codex-refine" "$REFINE_BIN" 755

merge_hooks_json merge

echo "Codex 首次启动会要求确认这个 hook 的信任，之后用 codex-refine start '<验收标准>' 开启循环"
