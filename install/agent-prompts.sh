#!/bin/bash
# 安装/更新各工具的 AGENTS.md 规则
# 脚本末尾的 install_mode 调用显式声明每个目标文件由哪些 prompt 文件按顺序组合而成
# 无需参数；可重入：重复执行会替换 managed block，保留块外其它内容

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="${PROMPTS_DIR:-$SCRIPT_DIR/../configs/agents}"

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE=1
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# remove_mode <mode> <dest>: 删除 install_mode 写入的 HTML 注释 managed block（含标记行），
# block 不存在则跳过（common.sh 的 remove_managed_block 只认 # 注释，这里单独用 awk）
remove_mode() {
    local mode="$1" dest="$2"
    local begin_marker="<!-- BEGIN configs $mode AGENTS -->"
    local end_marker="<!-- END configs $mode AGENTS -->"
    [[ -f "$dest" ]] || return 0
    grep -qF "$begin_marker" "$dest" || return 0
    local tmp_dest
    tmp_dest="$(mktemp)"
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { in_block = 1; next }
        $0 == end { in_block = 0; next }
        !in_block { print }
    ' "$dest" > "$tmp_dest"
    mv "$tmp_dest" "$dest"
    echo "已删除: $dest ($mode)"
}

install_mode() {
    local mode="$1" dest="$2"
    shift 2
    local begin_marker="<!-- BEGIN configs $mode AGENTS -->"
    local end_marker="<!-- END configs $mode AGENTS -->"

    local managed_block tmp_dest
    managed_block="$(mktemp)"
    tmp_dest="$(mktemp)"
    trap 'rm -f "$managed_block" "$tmp_dest"' RETURN

    {
        echo "$begin_marker"
        local prompt
        for prompt in "$@"; do
            prompt="$PROMPTS_DIR/$prompt"
            if [[ ! -f "$prompt" ]]; then
                echo "错误: 缺少提示词文件: $prompt" >&2
                exit 1
            fi
            cat "$prompt"
            echo
        done
        echo "$end_marker"
    } > "$managed_block"

    mkdir -p "$(dirname "$dest")"

    if [[ -f "$dest" ]] && grep -qF "$begin_marker" "$dest" && grep -qF "$end_marker" "$dest"; then
        awk -v begin="$begin_marker" -v end="$end_marker" -v block="$managed_block" '
            BEGIN {
                while ((getline line < block) > 0) {
                    replacement = replacement line ORS
                }
            }
            $0 == begin {
                printf "%s", replacement
                in_block = 1
                next
            }
            $0 == end {
                in_block = 0
                next
            }
            !in_block {
                print
            }
        ' "$dest" > "$tmp_dest"
    elif [[ "${UPDATE:-}" == "1" ]]; then
        echo "未安装，跳过: $dest"
        return
    elif [[ -f "$dest" && -s "$dest" ]]; then
        cp "$dest" "$tmp_dest"
        echo "" >> "$tmp_dest"
        cat "$managed_block" >> "$tmp_dest"
    else
        cp "$managed_block" "$tmp_dest"
    fi

    if [[ -f "$dest" ]] && cmp -s "$tmp_dest" "$dest"; then
        echo "已是最新 ($mode): $dest"
        return
    fi
    if [[ "${UPDATE:-}" == "1" ]]; then
        confirm_update "$dest ($mode)" || return
    fi
    mv "$tmp_dest" "$dest"
    echo "AGENTS.md 已更新 ($mode): $dest"
}

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "AGENTS.md 规则" || exit 0
    remove_mode codex "${CODEX_AGENTS_DEST:-$HOME/.codex/AGENTS.md}"
    remove_mode opencode "${OPENCODE_AGENTS_DEST:-$HOME/.config/opencode/AGENTS.md}"
    remove_mode pi "${PI_AGENTS_DEST:-$HOME/.pi/agent/AGENTS.md}"
    exit 0
fi

# 目标文件 <- 按顺序组合的 prompt 文件（prompt 按语义命名，与 agent 的关联只在这里声明）
install_mode codex "${CODEX_AGENTS_DEST:-$HOME/.codex/AGENTS.md}" \
    inline-functions.md

install_mode opencode "${OPENCODE_AGENTS_DEST:-$HOME/.config/opencode/AGENTS.md}" \
    git-safety.md inline-functions.md

install_mode pi "${PI_AGENTS_DEST:-$HOME/.pi/agent/AGENTS.md}" \
    response-style.md git-safety.md editing-constraints.md inline-functions.md
