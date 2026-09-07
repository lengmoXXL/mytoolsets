#!/bin/bash
# 安装 tree-sitter 到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"

VERSION="0.27.0"

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
    confirm_remove "tree-sitter" || exit 0
    RUST_DIR="${HOME}/.local/rust"
    CARGO=""
    if [[ -x "$RUST_DIR/bin/cargo" ]]; then
        export RUSTUP_HOME="$RUST_DIR/rustup"
        export CARGO_HOME="$RUST_DIR"
        CARGO="$RUST_DIR/bin/cargo"
    elif command -v cargo &>/dev/null; then
        CARGO="$(command -v cargo)"
    fi
    if [[ -n "$CARGO" ]]; then
        "$CARGO" uninstall tree-sitter-cli || true
    fi
    remove_file "$BIN_DIR/tree-sitter"
    exit 0
fi

echo "安装目录: $BIN_DIR/tree-sitter"

if [[ "$UPDATE" == "1" && ! -x "$BIN_DIR/tree-sitter" ]]; then
    echo "未安装，跳过: $BIN_DIR/tree-sitter"
    exit 0
fi

if [[ -x "$BIN_DIR/tree-sitter" ]]; then
    installed_version="$("$BIN_DIR/tree-sitter" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$UPDATE" != "1" ]]; then
        echo "tree-sitter 已安装: $installed_version"
        exit 0
    fi
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "tree-sitter 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "tree-sitter: ${installed_version:-unknown} -> $VERSION" || exit 0
fi

RUST_DIR="${HOME}/.local/rust"
if [[ -x "$RUST_DIR/bin/cargo" ]]; then
    export RUSTUP_HOME="$RUST_DIR/rustup"
    export CARGO_HOME="$RUST_DIR"
    CARGO="$RUST_DIR/bin/cargo"
elif command -v cargo &>/dev/null; then
    CARGO="$(command -v cargo)"
else
    echo "错误: 缺少 cargo，请先运行 install/compiler/rust.sh" >&2
    exit 1
fi

mkdir -p "$BIN_DIR"

echo "编译安装 tree-sitter-cli..."
"$CARGO" install tree-sitter-cli --version "$VERSION"

ln -sf "$(dirname "$CARGO")/tree-sitter" "$BIN_DIR/tree-sitter"

echo ""
echo "安装完成: $BIN_DIR/tree-sitter"
$BIN_DIR/tree-sitter --version