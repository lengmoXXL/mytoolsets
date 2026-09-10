#!/bin/bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PATH="${SCRIPT_DIR}/../tools/herdr-resize.sh"
TARGET_PATH="${BIN_DIR}/herdr-resize"

UPDATE=0
REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove) REMOVE=1 ;;
        --update) UPDATE=1 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "herdr-resize" || exit 0
    remove_file "$TARGET_PATH"
    exit 0
fi

if [[ ! -f "${SOURCE_PATH}" ]]; then
    echo "错误: 源脚本不存在: ${SOURCE_PATH}" >&2
    exit 1
fi

if [[ "$UPDATE" == "1" ]]; then
    if [[ ! -e "$TARGET_PATH" ]]; then
        echo "未安装，跳过: $TARGET_PATH"
        exit 0
    fi
    if cmp -s "$SOURCE_PATH" "$TARGET_PATH"; then
        echo "已是最新: $TARGET_PATH"
        exit 0
    fi
    confirm_update "herdr-resize" || exit 0
fi

if ! command -v herdr &>/dev/null; then
    echo "提示: herdr 未安装，可先运行 ./install/herdr.sh"
    exit 0
fi

mkdir -p "${BIN_DIR}"
install -m 755 "${SOURCE_PATH}" "${TARGET_PATH}"

echo "已安装 herdr-resize 到 ${TARGET_PATH}"
echo "在 herdr pane 内使用: herdr-resize right [步数] [-a 幅度]"
