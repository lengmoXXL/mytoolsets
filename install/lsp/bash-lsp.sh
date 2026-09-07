#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

BIN_DIR="$HOME/.local/bin"
NPM="$BIN_DIR/npm"
BINARY="$BIN_DIR/bash-language-server"

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove) REMOVE=1 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "bash-language-server" || exit 0
    if [[ -x "$NPM" ]]; then
        "$NPM" uninstall -g bash-language-server
    else
        remove_file "$BINARY"
    fi
    exit 0
fi

if [[ ! -x "$NPM" ]]; then
    echo "错误: npm 未安装在 $NPM"
    echo "请先运行 install/compiler/node.sh 安装 Node.js"
    exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

VERSION="5.6.0"

if [[ -x "$BINARY" && "${UPDATE:-}" != "1" ]]; then
    echo "bash-language-server 已安装"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" ]]; then
    installed_version="$("$BINARY" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "bash-language-server 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "bash-language-server: ${installed_version:-unknown} -> $VERSION" || exit 0
fi

echo "==> Installing bash-language-server..."
"$NPM" install -g "bash-language-server@$VERSION"

echo "==> Done! bash-language-server installed to $BIN_DIR"
