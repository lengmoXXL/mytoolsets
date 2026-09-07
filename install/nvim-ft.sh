#!/bin/bash

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PATH="${SCRIPT_DIR}/../tools/nvim_ft.py"
TARGET_PATH="${BIN_DIR}/nvim-ft"

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
    confirm_remove "nvim-ft" || exit 0
    remove_file "$TARGET_PATH"
    exit 0
fi

if [[ ! -f "${SOURCE_PATH}" ]]; then
    echo "Error: Source script not found: ${SOURCE_PATH}" >&2
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
    confirm_update "nvim-ft" || exit 0
fi

mkdir -p "${BIN_DIR}"
install -m 755 "${SOURCE_PATH}" "${TARGET_PATH}"

echo "Installed nvim-ft to ${TARGET_PATH}"
echo "Run it with: nvim-ft set <file> <filetype>"
echo "Config file: ${XDG_DATA_HOME:-${HOME}/.local/share}/nvim/filetypes.json"
