#!/bin/bash
# 安装 typos-lsp (拼写检查 LSP)
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

MODE="binary"
VERSION="0.1.56"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--binary|--source] [--remove]

选项:
  --binary  从 GitHub Release 下载预编译包 (默认)
  --source  从源码编译
  --remove  卸载 typos-lsp

环境变量:
  CN=1     通过国内代理访问 GitHub
EOF
}

REMOVE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --binary) MODE="binary"; shift ;;
        --source) MODE="source"; shift ;;
        --remove) REMOVE=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

BIN_DIR="${HOME}/.local/bin"
BINARY="$BIN_DIR/typos-lsp"

VERSIONS_DIR="$HOME/.local/share/configs-setup/versions"
MARKER="$VERSIONS_DIR/typos-lsp"

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "typos-lsp" || exit 0
    remove_file "$BINARY"
    remove_file "$MARKER"
    remove_file "$HOME/.local/rust/bin/typos-lsp"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" ]]; then
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "typos-lsp 已安装"
        exit 0
    fi
    if [[ "$(cat "$MARKER" 2>/dev/null)" == "$VERSION" ]]; then
        echo "typos-lsp 已是最新: $VERSION"
        exit 0
    fi
    confirm_update "typos-lsp -> $VERSION" || exit 0
fi

mkdir -p "$BIN_DIR"

if [[ "$MODE" == "binary" ]]; then
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="x86_64-unknown-linux-musl" ;;
        aarch64) ARCH="aarch64-unknown-linux-musl" ;;
        *) echo "错误: 不支持的架构 $ARCH"; exit 1 ;;
    esac

    URL="https://github.com/tekumara/typos-lsp/releases/download/v${VERSION}/typos-lsp-v${VERSION}-${ARCH}.tar.gz"
    if [[ "${CN:-}" == "1" ]]; then
        URL="${GITHUB_PROXY_PREFIX}${URL}"
    fi
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    echo "下载 typos-lsp v${VERSION} (${ARCH})"
    curl -fsSL "$URL" | tar -xzf - -C "$TMPDIR"

    find "$TMPDIR" -name typos-lsp -type f -exec mv {} "$BINARY" \;
    chmod +x "$BINARY"
else
    RUST_DIR="${HOME}/.local/rust"
    export RUSTUP_HOME="$RUST_DIR/rustup"
    export CARGO_HOME="$RUST_DIR"

    if [[ ! -x "$RUST_DIR/bin/cargo" ]]; then
        echo "错误: Rust 未安装，请先运行 install/compiler/rust.sh 或使用 --binary 模式"
        exit 1
    fi

    echo "从源码编译 typos-lsp"
    REPO_URL="https://github.com/tekumara/typos-lsp"
    if [[ "${CN:-}" == "1" ]]; then
        REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
    fi
    "$RUST_DIR/bin/cargo" install --git "$REPO_URL" --tag "v${VERSION}" --locked
    ln -sf "$RUST_DIR/bin/typos-lsp" "$BINARY"
fi

mkdir -p "$VERSIONS_DIR"
echo "$VERSION" > "$MARKER"

echo ""
echo "typos-lsp 安装完成: $BINARY"
