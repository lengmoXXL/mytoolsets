#!/bin/bash
# 安装 typescript-language-server 到 ~/.local/typescript-language-server
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/typescript-language-server"
BIN_DIR="${HOME}/.local/bin"
BINARY="$BIN_DIR/typescript-language-server"

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
    confirm_remove "typescript-language-server" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_file "$BINARY"
    remove_file "$BIN_DIR/tsserver"
    exit 0
fi

if [[ "$UPDATE" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" && "$UPDATE" != "1" ]]; then
    echo "typescript-language-server 已安装"
    exit 0
fi

if ! command -v npm &>/dev/null; then
    echo "错误: npm 未安装"
    exit 1
fi

VERSION="6.0.0"

if [[ "$UPDATE" == "1" ]]; then
    installed_version="$("$BINARY" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "typescript-language-server 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "typescript-language-server: ${installed_version:-unknown} -> $VERSION" || exit 0
fi

echo "安装 typescript-language-server"

mkdir -p "$BIN_DIR"
mkdir -p "$INSTALL_DIR"

npm install --prefix "$INSTALL_DIR" typescript@^6 "typescript-language-server@$VERSION"

ln -sf "$INSTALL_DIR/node_modules/.bin/typescript-language-server" "$BINARY"
ln -sf "$INSTALL_DIR/node_modules/.bin/tsserver" "$BIN_DIR/tsserver"

echo ""
echo "typescript-language-server 安装完成: $BINARY"