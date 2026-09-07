#!/bin/bash
# 安装 nvim 配置到 ~/.config/nvim
# 可重入：内容变化才写入

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_SOURCE="$SCRIPT_DIR/../configs/nvim"
NVIM_DEST="$HOME/.config/nvim"

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
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "nvim 配置" || exit 0
    remove_dir "$NVIM_DEST"
    exit 0
fi

if [[ ! -d "$NVIM_SOURCE" ]]; then
    echo "错误: 源目录不存在: $NVIM_SOURCE"
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -d "$NVIM_DEST" ]]; then
    echo "未安装，跳过: $NVIM_DEST"
    exit 0
fi

if ! command -v rsync &>/dev/null; then
    echo "错误: 缺少依赖 rsync" >&2
    exit 1
fi

if [[ "$UPDATE" == "1" ]]; then
    changes="$(rsync -nai --delete "$NVIM_SOURCE/" "$NVIM_DEST/")"
    if [[ -z "$changes" ]]; then
        echo "已是最新: $NVIM_DEST"
        exit 0
    fi
    echo "$changes"
    confirm_update "nvim 配置" || exit 0
fi
rsync -ai --delete "$NVIM_SOURCE/" "$NVIM_DEST/"
echo "nvim 配置已安装: $NVIM_DEST"