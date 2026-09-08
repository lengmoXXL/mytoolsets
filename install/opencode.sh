#!/bin/bash
# Install opencode from GitHub Releases.
# The installed version is pinned here; use tools/latest-version.sh to check updates.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
OPENCODE_BIN="${BIN_DIR}/opencode"
OPENCODE_VERSION="1.18.27"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 opencode
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
    confirm_remove "opencode" || exit 0
    remove_file "$OPENCODE_BIN"
    exit 0
fi

for dep in curl find grep head install mktemp uname; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

if [[ "$UPDATE" == "1" && ! -x "$OPENCODE_BIN" ]]; then
    echo "未安装，跳过: $OPENCODE_BIN"
    exit 0
fi

if [[ -x "$OPENCODE_BIN" ]]; then
    installed_version="$("$OPENCODE_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$UPDATE" != "1" ]]; then
        echo "opencode 已安装: $OPENCODE_BIN ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "$OPENCODE_VERSION" ]]; then
        echo "opencode 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 opencode: ${installed_version:-unknown} -> $OPENCODE_VERSION"
    confirm_update "opencode: ${installed_version:-unknown} -> $OPENCODE_VERSION" || exit 0
fi

os=$(uname -s)
arch=$(uname -m)

case "$os:$arch" in
    Linux:x86_64)
        target="linux-x64"
        if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
            target="linux-x64-baseline"
        fi
        ;;
    Linux:aarch64 | Linux:arm64)
        target="linux-arm64"
        ;;
    Darwin:x86_64)
        target="darwin-x64"
        if [[ "$(sysctl -n hw.optional.avx2_0 2>/dev/null || echo 0)" != "1" ]]; then
            target="darwin-x64-baseline"
        fi
        ;;
    Darwin:arm64 | Darwin:aarch64)
        target="darwin-arm64"
        ;;
    *)
        echo "错误: 不支持的平台 ${os}/${arch}"
        exit 1
        ;;
esac

archive_ext="zip"
if [[ "$os" == "Linux" ]]; then
    archive_ext="tar.gz"
    if [[ -f /etc/alpine-release ]] || { command -v ldd &>/dev/null && ldd --version 2>&1 | grep -qi musl; }; then
        target="${target}-musl"
    fi

    if ! command -v tar &>/dev/null; then
        echo "错误: 缺少依赖 tar"
        exit 1
    fi
elif ! command -v unzip &>/dev/null; then
    echo "错误: 缺少依赖 unzip"
    exit 1
fi

tmp_dir=$(mktemp -d)
archive="${tmp_dir}/opencode.${archive_ext}"
url="https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-${target}.${archive_ext}"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "下载 opencode ${OPENCODE_VERSION} (${target})..."
curl -fL "$url" -o "$archive"

if [[ "$archive_ext" == "tar.gz" ]]; then
    tar -xzf "$archive" -C "$tmp_dir"
else
    unzip -q "$archive" -d "$tmp_dir"
fi

opencode_binary=$(find "$tmp_dir" -type f -name opencode | head -1)
if [[ -z "$opencode_binary" ]]; then
    echo "错误: opencode 压缩包中没有找到二进制文件"
    exit 1
fi

mkdir -p "$BIN_DIR"
install -m 755 "$opencode_binary" "$OPENCODE_BIN"

echo "opencode 安装完成: $OPENCODE_BIN"
"$OPENCODE_BIN" --version
