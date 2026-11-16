#!/bin/bash

# 安装 clice (C/C++ LSP) 到 ~/.local/clice
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/clice"
BIN_DIR="${HOME}/.local/bin"
BINARY="$BIN_DIR/clice"
VERSION="1.0.0"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 clice
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理下载 GitHub Release 文件
EOF
}

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

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "clice" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_file "$BINARY"
    exit 0
fi

if [[ "$UPDATE" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" ]]; then
    installed_version="$("$BINARY" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$UPDATE" != "1" ]]; then
        echo "clice 已安装 ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "clice 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 clice: ${installed_version:-unknown} -> $VERSION"
    confirm_update "clice: ${installed_version:-unknown} -> $VERSION" || exit 0
fi

OS=$(uname -s)
ARCH=$(uname -m)
case "$OS/$ARCH" in
    Darwin/x86_64) TARGET="x86_64-apple-darwin" ;;
    Darwin/arm64) TARGET="aarch64-apple-darwin" ;;
    Linux/x86_64) TARGET="x86_64-unknown-linux-gnu" ;;
    Linux/aarch64) TARGET="aarch64-unknown-linux-gnu" ;;
    *) echo "不支持的平台: $OS/$ARCH"; exit 1 ;;
esac

echo "安装 clice $VERSION ($TARGET)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

TARBALL="clice-$VERSION.$TARGET.tar.gz"
DOWNLOAD_URL="https://github.com/clice-io/clice/releases/download/v$VERSION/$TARBALL"
if [[ "${CN:-}" == "1" ]]; then
    DOWNLOAD_URL="${GITHUB_RELEASE_PROXY}${DOWNLOAD_URL}"
fi
curl -fL "$DOWNLOAD_URL" -o "$TMPDIR/$TARBALL"

# 整棵目录都要装：二进制按自身路径找 lib/clang/<版本> 里的内置头文件
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
tar -xzf "$TMPDIR/$TARBALL" -C "$INSTALL_DIR" --strip-components=1
ln -sf "$INSTALL_DIR/bin/clice" "$BINARY"

echo ""
echo "clice 安装完成: $BINARY"
echo "  $("$BINARY" --version)"