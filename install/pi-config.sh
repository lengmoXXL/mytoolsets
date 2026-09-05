#!/bin/bash
# 安装 Pi 配置与自研 extensions 到 ~/.pi/agent
# 单文件配置用 write_file_if_changed；themes/agents/extensions 目录用 rsync 镜像

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/../configs/pi"
TARGET="$HOME/.pi/agent"

if ! command -v rsync &>/dev/null; then
    echo "错误: 缺少依赖 rsync" >&2
    exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -d "$TARGET" ]]; then
    echo "未安装，跳过: $TARGET"
    exit 0
fi

mkdir -p "$TARGET"

for name in models.json settings.json pi-plan-mode.json zentui.json; do
    tmp_config="$(mktemp)"
    cp "$SOURCE/$name" "$tmp_config"
    write_file_if_changed "$TARGET/$name" "$tmp_config"
done

sync_dir() {
    local src="$1" dest="$2" desc="$3" changes
    changes="$(rsync -nai --delete "$src/" "$dest/" 2>/dev/null)"
    if [[ -z "$changes" ]]; then
        echo "$dest 未变化"
        return
    fi
    if [[ "${UPDATE:-}" == "1" ]] && ! confirm_update "$desc"; then
        return
    fi
    mkdir -p "$dest"
    rsync -ai --delete "$src/" "$dest/"
    echo "$dest 已更新"
}

sync_dir "$SOURCE/themes" "$TARGET/themes" "pi themes"
sync_dir "$SOURCE/agents" "$TARGET/agents" "pi agents"

# 只镜像自研 *.ts（node_modules、tsconfig 等编辑器辅助文件不装）；
# 目标目录里 pi 包管理的文件（subagent/ 等）被 exclude 保护，不会被 --delete 删除
ext_changes="$(rsync -nai --delete --include='*.ts' --exclude='*' "$SOURCE/extensions/" "$TARGET/extensions/")"
if [[ -n "$ext_changes" ]]; then
    echo "$ext_changes"
    if [[ "${UPDATE:-}" != "1" ]] || confirm_update "pi extensions"; then
        rsync -ai --delete --include='*.ts' --exclude='*' "$SOURCE/extensions/" "$TARGET/extensions/"
        echo "pi extensions 已更新: $TARGET/extensions"
    fi
else
    echo "$TARGET/extensions 未变化"
fi
