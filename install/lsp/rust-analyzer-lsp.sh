#!/bin/bash
# 安装 rust-analyzer LSP
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

RUST_DIR="${HOME}/.local/rust"
BIN_DIR="${HOME}/.local/bin"
RUSTUP="${BIN_DIR}/rustup"
RUST_ANALYZER="${BIN_DIR}/rust-analyzer"

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
    confirm_remove "rust-analyzer" || exit 0
    if [[ -x "$RUSTUP" ]]; then
        "$RUSTUP" component remove rust-analyzer || true
    fi
    remove_file "$RUST_ANALYZER"
    exit 0
fi

export RUSTUP_HOME="${RUST_DIR}/rustup"
export CARGO_HOME="${RUST_DIR}"
export RUSTUP_DIST_SERVER="https://mirrors.aliyun.com/rustup"
export RUSTUP_UPDATE_ROOT="https://mirrors.aliyun.com/rustup/rustup"

if [[ "$UPDATE" == "1" && ! -x "$RUST_ANALYZER" ]]; then
    echo "未安装，跳过: $RUST_ANALYZER"
    exit 0
fi

if [[ -x "$RUST_ANALYZER" ]]; then
    if [[ "$UPDATE" == "1" ]]; then
        echo "rust-analyzer 随 rust 工具链更新（见 compiler/rust.sh），跳过"
    else
        echo "rust-analyzer 已安装: $("$RUST_ANALYZER" --version)"
    fi
    exit 0
fi

if [[ ! -x "$RUSTUP" ]]; then
    if command -v rustup &>/dev/null; then
        RUSTUP="$(command -v rustup)"
    else
        echo "错误: rustup 未安装"
        echo "请先运行 install/compiler/rust.sh 安装 Rust"
        exit 1
    fi
fi

echo "安装 rust-analyzer LSP"

mkdir -p "$BIN_DIR"
"$RUSTUP" component add rust-analyzer

if [[ -x "${RUST_DIR}/bin/rust-analyzer" ]]; then
    ln -sf "${RUST_DIR}/bin/rust-analyzer" "$RUST_ANALYZER"
fi

if [[ ! -x "$RUST_ANALYZER" ]] && command -v rust-analyzer &>/dev/null; then
    ln -sf "$(command -v rust-analyzer)" "$RUST_ANALYZER"
fi

if [[ ! -x "$RUST_ANALYZER" ]]; then
    echo "错误: rust-analyzer 安装失败"
    exit 1
fi

echo ""
echo "rust-analyzer LSP 安装完成:"
echo "  rust-analyzer: $RUST_ANALYZER"
echo "  version: $("$RUST_ANALYZER" --version)"
