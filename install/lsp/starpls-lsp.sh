#!/bin/bash
# 安装 starpls (Starlark/Bazel LSP) 到 ~/.local/bin
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
BINARY="${BIN_DIR}/starpls"
VERSION="v0.1.22"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove]

选项:
  --remove  卸载 starpls

环境变量:
  CN=1     通过国内代理下载 GitHub Release 文件
EOF
}

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE=1
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
    confirm_remove "starpls" || exit 0
    remove_file "$BINARY"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" ]]; then
    installed_version="v$("$BINARY" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "starpls 已安装: $BINARY ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "starpls 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 starpls: $installed_version -> $VERSION"
    confirm_update "starpls: $installed_version -> $VERSION" || exit 0
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="aarch64" ;;
    *) echo "错误: 不支持的架构 $ARCH"; exit 1 ;;
esac

ASSET="starpls-linux-${ARCH}"
DOWNLOAD_URL="https://github.com/withered-magic/starpls/releases/download/${VERSION}/${ASSET}"
if [[ "${CN:-}" == "1" ]]; then
    DOWNLOAD_URL="${GITHUB_RELEASE_PROXY}${DOWNLOAD_URL}"
fi

echo "安装 starpls $VERSION (${ARCH})"

mkdir -p "$BIN_DIR"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

curl -fL "$DOWNLOAD_URL" -o "${TMPDIR}/starpls"
install -m 755 "${TMPDIR}/starpls" "$BINARY"

echo ""
echo "starpls 安装完成:"
echo "  starpls: $BINARY"
echo "  version: $("$BINARY" version)"
