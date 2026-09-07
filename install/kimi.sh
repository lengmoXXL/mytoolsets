#!/bin/bash
# Install or update Kimi Code CLI via the official install script:
#   curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash
# The script downloads the latest native binary, verifies its checksum,
# writes ~/.kimi-code/bin to PATH, and migrates any legacy Python `kimi-cli`
# shim on PATH to `kimi-legacy`.
# Set KIMI_VERSION to install a pinned version, KIMI_NO_MODIFY_PATH to skip
# the PATH update (see the header of the official script).

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

KIMI_VERSION="0.41.0"
KIMI_BIN="$HOME/.kimi-code/bin/kimi"

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

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "kimi" || exit 0
    remove_dir "$HOME/.kimi-code"
    echo "提示: 官方安装器写入 shell rc 的 PATH 配置未清理，请手动检查 ~/.bashrc、~/.zshrc 等"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" && ! -x "$KIMI_BIN" ]]; then
    echo "未安装，跳过: kimi"
    exit 0
fi

if [[ -x "$KIMI_BIN" ]]; then
    installed_version="$("$KIMI_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "kimi 已安装: $installed_version"
        exit 0
    fi
    if [[ "$installed_version" == "$KIMI_VERSION" ]]; then
        echo "kimi 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "kimi: ${installed_version:-unknown} -> $KIMI_VERSION" || exit 0
fi

curl -fsSL https://code.kimi.com/kimi-code/install.sh | KIMI_VERSION="$KIMI_VERSION" bash

"$KIMI_BIN" --version
