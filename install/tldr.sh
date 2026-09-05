#!/bin/bash
# 安装 tldr 命令行帮助工具到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

TLDR_VERSION="3.4.4"

BIN_DIR="${HOME}/.local/bin"
PYTHON_DIR="${HOME}/.local/python3.11"
UV_BIN="${BIN_DIR}/uv"

mkdir -p "$BIN_DIR"

if [[ "${UPDATE:-}" == "1" && ! -x "$BIN_DIR/tldr" ]]; then
    echo "未安装，跳过: tldr"
    exit 0
fi

if [[ -x "$BIN_DIR/tldr" && "${UPDATE:-}" != "1" ]]; then
    echo "tldr 已安装: $BIN_DIR/tldr"
    exit 0
fi

if [[ ! -x "$PYTHON_DIR/bin/python3" ]]; then
    echo "错误: Python 3.11 环境未安装"
    echo "请先运行 install/compiler/python.sh"
    exit 1
fi

if [[ ! -x "$UV_BIN" ]]; then
    echo "错误: 缺少 uv，请先运行 install/uv.sh" >&2
    exit 1
fi

UV_CMD="$UV_BIN"

if [[ "${UPDATE:-}" == "1" ]]; then
    installed_version=$("$UV_CMD" pip list --python "$PYTHON_DIR/bin/python3" 2>/dev/null | awk '$1 == "tldr" {print $2}')
    if [[ "$installed_version" == "$TLDR_VERSION" ]]; then
        echo "tldr 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "tldr: ${installed_version:-unknown} -> $TLDR_VERSION" || exit 0
fi

echo "安装 tldr $TLDR_VERSION 到 Python 3.11 环境..."
"$UV_CMD" pip install --python "$PYTHON_DIR/bin/python3" "tldr==$TLDR_VERSION"

if [[ ! -x "$PYTHON_DIR/bin/tldr" ]]; then
    echo "错误: tldr 安装后未找到: $PYTHON_DIR/bin/tldr"
    exit 1
fi

ln -sf "$PYTHON_DIR/bin/tldr" "$BIN_DIR/tldr"

echo ""
echo "tldr 安装完成"
echo "  tldr: $BIN_DIR/tldr"
"$PYTHON_DIR/bin/tldr" --version
