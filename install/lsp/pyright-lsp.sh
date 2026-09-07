#!/bin/bash
# 安装 pyright LSP 到 ~/.local/pyright
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/pyright"
BIN_DIR="${HOME}/.local/bin"
NPM="${BIN_DIR}/npm"
PYRIGHT="${BIN_DIR}/pyright"
PYRIGHT_LANGSERVER="${BIN_DIR}/pyright-langserver"

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove) REMOVE=1 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "pyright LSP" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_file "$PYRIGHT"
    remove_file "$PYRIGHT_LANGSERVER"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" && ! -x "$PYRIGHT_LANGSERVER" ]]; then
    echo "未安装，跳过: $PYRIGHT_LANGSERVER"
    exit 0
fi

VERSION="1.1.413"

if [[ -x "$PYRIGHT_LANGSERVER" && "${UPDATE:-}" != "1" ]]; then
    echo "pyright-langserver 已安装"
    exit 0
fi

if [[ ! -x "$NPM" ]]; then
    if command -v npm &>/dev/null; then
        NPM="$(command -v npm)"
    else
        echo "错误: npm 未安装"
        echo "请先运行 install/compiler/node.sh 安装 Node.js"
        exit 1
    fi
fi

if [[ "${UPDATE:-}" == "1" ]]; then
    installed_version="$("$PYRIGHT" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "pyright 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "pyright: ${installed_version:-unknown} -> $VERSION" || exit 0
fi

echo "安装 pyright LSP"

mkdir -p "$BIN_DIR"
mkdir -p "$INSTALL_DIR"

"$NPM" install --prefix "$INSTALL_DIR" "pyright@$VERSION"

ln -sf "$INSTALL_DIR/node_modules/.bin/pyright" "$PYRIGHT"
ln -sf "$INSTALL_DIR/node_modules/.bin/pyright-langserver" "$PYRIGHT_LANGSERVER"

echo ""
echo "pyright LSP 安装完成:"
echo "  pyright: $PYRIGHT"
echo "  pyright-langserver: $PYRIGHT_LANGSERVER"
