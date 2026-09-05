#!/bin/bash
# 安装 ripgrep 到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
RIPGREP_VERSION="15.2.0"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0

环境变量:
  CN=1     通过国内代理下载 GitHub Release 文件
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

mkdir -p "$BIN_DIR"

for dep in curl tar find install; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

existing_rg=""
if [[ -x "$BIN_DIR/rg" ]]; then
    existing_rg="$BIN_DIR/rg"
fi

if [[ "${UPDATE:-}" == "1" && -z "$existing_rg" ]]; then
    echo "未安装，跳过: rg"
    exit 0
fi

if [[ -n "$existing_rg" ]]; then
    installed_version="$("$existing_rg" --version | head -1 | awk '{print $2}')"
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "rg 已安装: $existing_rg ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "$RIPGREP_VERSION" ]]; then
        echo "rg 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 rg: $installed_version -> $RIPGREP_VERSION"
    confirm_update "rg: $installed_version -> $RIPGREP_VERSION" || exit 0
fi

version="$RIPGREP_VERSION"

os=$(uname -s)
arch=$(uname -m)
case "${os}-${arch}" in
    Darwin-x86_64) target="x86_64-apple-darwin" ;;
    Darwin-arm64) target="aarch64-apple-darwin" ;;
    Linux-x86_64) target="x86_64-unknown-linux-musl" ;;
    Linux-aarch64 | Linux-arm64) target="aarch64-unknown-linux-gnu" ;;
    *) echo "错误: 不支持的平台 ${os}-${arch}"; exit 1 ;;
esac

tmp_dir=$(mktemp -d)
tarball="${tmp_dir}/ripgrep.tar.gz"
url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/ripgrep-${version}-${target}.tar.gz"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

echo "下载 ripgrep ${version}..."
curl -fL "$url" -o "$tarball"
tar -xzf "$tarball" -C "$tmp_dir"

rg_bin=$(find "$tmp_dir" -type f -name rg | head -1)
if [[ -z "$rg_bin" ]]; then
    echo "错误: ripgrep 压缩包中没有找到 rg"
    rm -rf "$tmp_dir"
    exit 1
fi

install -m 755 "$rg_bin" "$BIN_DIR/rg"
rm -rf "$tmp_dir"

echo "rg 安装完成: $BIN_DIR/rg"
"$BIN_DIR/rg" --version | head -1
