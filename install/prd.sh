#!/bin/bash
# sync: skip

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/../tools/prd"
SOURCE_PATH="${PROJECT_DIR}/dist/prd.cjs"
TARGET_PATH="${BIN_DIR}/prd"

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
    confirm_remove "prd" || exit 0
    remove_file "$TARGET_PATH"
    exit 0
fi

if [[ ! -f "${PROJECT_DIR}/package.json" ]]; then
    echo "Error: prd package not found: ${PROJECT_DIR}" >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "Error: node is required to install prd" >&2
    exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm is required to install prd" >&2
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -e "$TARGET_PATH" ]]; then
    echo "未安装，跳过: $TARGET_PATH"
    exit 0
fi

if [[ "$UPDATE" == "1" ]]; then
    confirm_update "prd" || exit 0
fi

echo "Updating prd dependencies..."
npm --prefix "${PROJECT_DIR}" install

echo "Building prd bundle..."
npm --prefix "${PROJECT_DIR}" run build

if [[ ! -f "${SOURCE_PATH}" ]]; then
    echo "Error: Build output not found: ${SOURCE_PATH}" >&2
    exit 1
fi

mkdir -p "${BIN_DIR}"
install -m 755 "${SOURCE_PATH}" "${TARGET_PATH}"

echo "Installed prd to ${TARGET_PATH}"
echo "Run it with: prd <file>"
echo "Default server: http://127.0.0.1:7000/"

if ! command -v markdown-oxide >/dev/null 2>&1; then
    echo "Note: markdown-oxide not found; install it (install/lsp/markdown-oxide.sh) to resolve [[wiki]] links"
fi
