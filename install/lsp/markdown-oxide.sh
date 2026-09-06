#!/bin/bash
# 安装 markdown-oxide LSP Server
# 从 fork 源码编译安装: https://github.com/lengmoXXL/markdown-oxide

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

REPO_URL="https://github.com/lengmoXXL/markdown-oxide.git"
PINNED_COMMIT="d99a2deb32a4de3b2026a1d65373f52ebb72930d"  # fork HEAD，即上游 0.25.12 + GitHub slug 标题链接解析
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"
RUST_DIR="${HOME}/.local/rust"
INSTALL_ROOT="${HOME}/.local/markdown-oxide"
BIN_DIR="${HOME}/.local/bin"
CARGO="${RUST_DIR}/bin/cargo"
BINARY="${BIN_DIR}/markdown-oxide"

usage() {
    cat << EOF
用法: $0

环境变量:
  CN=1     通过国内代理 clone GitHub 仓库
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ "${CN:-}" == "1" ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

export RUSTUP_DIST_SERVER="https://mirrors.aliyun.com/rustup"
export RUSTUP_UPDATE_ROOT="https://mirrors.aliyun.com/rustup/rustup"

if [[ -x "$CARGO" ]]; then
    export RUSTUP_HOME="${RUST_DIR}/rustup"
    export CARGO_HOME="${RUST_DIR}"
elif command -v cargo &>/dev/null; then
    CARGO="$(command -v cargo)"
else
    echo "错误: cargo 未安装"
    echo "请先运行 install/compiler/rust.sh 安装 Rust"
    exit 1
fi

VERSIONS_DIR="$HOME/.local/share/configs-setup/versions"
MARKER="$VERSIONS_DIR/markdown-oxide"

if [[ "${UPDATE:-}" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" && "${UPDATE:-}" != "1" ]]; then
    echo "markdown-oxide 已安装: $("$BINARY" --version)"
    exit 0
fi

if [[ -x "$BINARY" && "$(cat "$MARKER" 2>/dev/null)" == "$PINNED_COMMIT" ]]; then
    echo "markdown-oxide 已是最新: $VERSION"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" ]]; then
    confirm_update "markdown-oxide -> $VERSION" || exit 0
fi

echo "从源码安装 markdown-oxide"
echo "  repo: $REPO_URL"
echo "  tag: $VERSION"

mkdir -p "$BIN_DIR" "$INSTALL_ROOT"

"$CARGO" install \
    --git "$REPO_URL" \
    --rev "$PINNED_COMMIT" \
    --locked \
    --force \
    --root "$INSTALL_ROOT"

ln -sf "${INSTALL_ROOT}/bin/markdown-oxide" "$BINARY"

mkdir -p "$VERSIONS_DIR"
echo "$PINNED_COMMIT" > "$MARKER"

echo ""
echo "markdown-oxide LSP 安装完成:"
echo "  markdown-oxide: $BINARY"
echo "  version: $("$BINARY" --version)"
