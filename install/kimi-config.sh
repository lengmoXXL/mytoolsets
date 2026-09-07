#!/bin/bash
# 安装 Kimi Code 主题到 ${KIMI_CODE_HOME:-~/.kimi-code}/themes/
# 可重入：内容变化才写入

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_SOURCE="$SCRIPT_DIR/../configs/kimi/themes"
KIMI_HOME="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
THEMES_DEST="$KIMI_HOME/themes"

usage() {
    cat << EOF
用法: $0 [--remove]

安装 Kimi Code 主题到 ${KIMI_CODE_HOME:-~/.kimi-code}/themes/。

选项:
  --remove  卸载 Kimi Code 主题
EOF
}

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE=1
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

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "Kimi Code 主题" || exit 0
    remove_dir "$THEMES_DEST"
    exit 0
fi

if [[ ! -d "$THEMES_SOURCE" ]]; then
    echo "错误: 源目录不存在: $THEMES_SOURCE"
    exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -d "$THEMES_DEST" ]]; then
    echo "未安装，跳过: $THEMES_DEST"
    exit 0
fi

if ! command -v rsync &>/dev/null; then
    echo "错误: 缺少依赖 rsync" >&2
    exit 1
fi

mkdir -p "$THEMES_DEST"
if [[ "${UPDATE:-}" == "1" ]]; then
    changes="$(rsync -nai --delete "$THEMES_SOURCE/" "$THEMES_DEST/")"
    if [[ -z "$changes" ]]; then
        echo "已是最新: $THEMES_DEST"
        exit 0
    fi
    echo "$changes"
    confirm_update "kimi 主题" || exit 0
fi
rsync -ai --delete "$THEMES_SOURCE/" "$THEMES_DEST/"
echo "Kimi Code 主题已安装: $THEMES_DEST"
