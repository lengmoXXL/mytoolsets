#!/bin/bash
# 安装 Ghostty 配置到 ~/.config/ghostty/config
# 可重入：内容变化才写入

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHOSTTY_SOURCE="$SCRIPT_DIR/../configs/ghostty/config"
GHOSTTY_DIR="$HOME/.config/ghostty"
GHOSTTY_DEST="$GHOSTTY_DIR/config"

usage() {
    cat << EOF
用法: $0 [--remove]

安装 Ghostty 配置到 ~/.config/ghostty/config。

选项:
  --remove  卸载 Ghostty 配置
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
    confirm_remove "Ghostty 配置" || exit 0
    remove_file "$GHOSTTY_DEST"
    exit 0
fi

if [[ ! -f "$GHOSTTY_SOURCE" ]]; then
    echo "错误: 源配置不存在: $GHOSTTY_SOURCE"
    exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -e "$GHOSTTY_DEST" ]]; then
    echo "未安装，跳过: $GHOSTTY_DEST"
    exit 0
fi

tmp_config="$(mktemp)"
cp "$GHOSTTY_SOURCE" "$tmp_config"
write_file_if_changed "$GHOSTTY_DEST" "$tmp_config"

if ! command -v ghostty &>/dev/null; then
    echo "提示: ghostty 未安装"
    exit 0
fi

if ghostty +validate-config --config-file="$GHOSTTY_DEST" &>/dev/null; then
    echo "配置校验通过"
else
    echo "警告: 配置校验未通过，请运行 ghostty +validate-config 查看详情"
fi
