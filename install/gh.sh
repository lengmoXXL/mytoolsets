#!/bin/bash
# 安装 GitHub CLI (gh) 到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
GH_VERSION="v2.100.0"
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

if [[ "${UPDATE:-}" == "1" && ! -x "$BIN_DIR/gh" ]]; then
    echo "未安装，跳过: gh"
    exit 0
fi

if [[ -x "$BIN_DIR/gh" ]]; then
    installed_version="$("$BIN_DIR/gh" --version | head -1 | awk '{print $3}')"
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "gh 已安装: $BIN_DIR/gh ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "${GH_VERSION#v}" ]]; then
        echo "gh 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 gh: $installed_version -> ${GH_VERSION#v}"
    confirm_update "gh: $installed_version -> ${GH_VERSION#v}" || exit 0
fi

os=$(uname -s)
case "$os" in
    Darwin) os_name="macOS" ;;
    Linux) os_name="linux" ;;
    *) echo "错误: 不支持的系统 $os"; exit 1 ;;
esac

arch=$(uname -m)
case "$arch" in
    x86_64) arch_name="amd64" ;;
    aarch64 | arm64) arch_name="arm64" ;;
    *) echo "错误: 不支持的架构 $arch"; exit 1 ;;
esac

gh_ver_num="${GH_VERSION#v}"

if [[ "$os_name" == "macOS" ]]; then
    for dep in curl unzip; do
        if ! command -v "$dep" &>/dev/null; then
            echo "错误: 缺少依赖 $dep"
            exit 1
        fi
    done
    archive="gh_${gh_ver_num}_${os_name}_${arch_name}.zip"
else
    if ! command -v tar &>/dev/null; then
        echo "错误: 缺少依赖 tar"
        exit 1
    fi
    archive="gh_${gh_ver_num}_${os_name}_${arch_name}.tar.gz"
fi

tmp_dir=$(mktemp -d)
archive_path="${tmp_dir}/${archive}"
url="https://github.com/cli/cli/releases/download/${GH_VERSION}/${archive}"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

echo "下载 gh ${GH_VERSION}..."
curl -fL "$url" -o "$archive_path"

if [[ "$os_name" == "macOS" ]]; then
    unzip -q "$archive_path" -d "$tmp_dir"
else
    tar -xzf "$archive_path" -C "$tmp_dir"
fi

gh_bin=$(find "$tmp_dir" -type f -name gh | head -1)
if [[ -z "$gh_bin" ]]; then
    echo "错误: 压缩包中没有找到 gh"
    rm -rf "$tmp_dir"
    exit 1
fi

install -m 755 "$gh_bin" "$BIN_DIR/gh"
rm -rf "$tmp_dir"

echo "gh 安装完成: $BIN_DIR/gh"
"$BIN_DIR/gh" --version | head -1
