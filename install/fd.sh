#!/bin/bash
# 安装 fd 到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
FD_VERSION="v10.5.0"
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

existing_fd=""
if [[ -x "$BIN_DIR/fd" ]]; then
    existing_fd="$BIN_DIR/fd"
fi

if [[ "${UPDATE:-}" == "1" && -z "$existing_fd" ]]; then
    echo "未安装，跳过: fd"
    exit 0
fi

version="$FD_VERSION"

os=$(uname -s)
arch=$(uname -m)
case "${os}-${arch}" in
    Darwin-x86_64) target="x86_64-apple-darwin" ;;
    Darwin-arm64 | Darwin-aarch64) target="aarch64-apple-darwin" ;;
    Linux-x86_64) target="x86_64-unknown-linux-musl" ;;
    Linux-aarch64 | Linux-arm64) target="aarch64-unknown-linux-gnu" ;;
    *) echo "错误: 不支持的平台 ${os}-${arch}"; exit 1 ;;
esac

if [[ -n "$existing_fd" ]]; then
    installed_version="$("$existing_fd" --version | head -1 | awk '{print $2}')"
    if [[ "$installed_version" == "${version#v}" ]]; then
        echo "fd 已是最新: $installed_version"
        exit 0
    fi
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "fd 已安装: $existing_fd ($installed_version)"
        exit 0
    fi
    echo "更新 fd: $installed_version -> ${version#v}"
    confirm_update "fd: $installed_version -> ${version#v}" || exit 0
fi

tmp_dir=$(mktemp -d)
tarball="${tmp_dir}/fd.tar.gz"
url="https://github.com/sharkdp/fd/releases/download/${version}/fd-${version}-${target}.tar.gz"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

echo "下载 fd ${version}..."
curl -fL "$url" -o "$tarball"
tar -xzf "$tarball" -C "$tmp_dir"

fd_bin=$(find "$tmp_dir" -type f -name fd | head -1)
if [[ -z "$fd_bin" ]]; then
    echo "错误: fd 压缩包中没有找到 fd"
    rm -rf "$tmp_dir"
    exit 1
fi

install -m 755 "$fd_bin" "$BIN_DIR/fd"
rm -rf "$tmp_dir"

echo "fd 安装完成: $BIN_DIR/fd"
"$BIN_DIR/fd" --version | head -1
