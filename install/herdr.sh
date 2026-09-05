#!/bin/bash
# Install or update Herdr from GitHub Releases.
# The installed release tag is pinned here; use tools/github-release-latest.sh to check updates.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
HERDR_BIN="${BIN_DIR}/herdr"
HERDR_VERSION="v0.8.2"
CURL_USER_AGENT="configs-install-herdr"
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

for dep in curl head install mktemp sed uname; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

target_version="${HERDR_VERSION#v}"

local_herdr=""
if [[ -x "$HERDR_BIN" ]]; then
    local_herdr="$HERDR_BIN"
fi

local_version=""
if [[ -n "$local_herdr" ]]; then
    local_version=$("$local_herdr" --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\).*/\1/p' | head -1)
fi

if [[ -z "$local_herdr" || -z "$local_version" ]]; then
    if [[ "${UPDATE:-}" == "1" ]]; then
        echo "未安装，跳过: herdr"
        exit 0
    fi
    echo "Herdr 未安装，将安装目标版本 ${HERDR_VERSION}"
else
    echo "当前 Herdr: ${local_version} (${local_herdr})"
    echo "目标 Herdr: ${target_version}"

    if [[ "$local_version" == "$target_version" ]]; then
        echo "Herdr 已是目标版本"
        exit 0
    fi

    echo "Herdr 版本不匹配，将重装目标版本 ${HERDR_VERSION}"
    confirm_update "herdr: ${local_version} -> ${target_version}" || exit 0
fi

os=$(uname -s)
arch=$(uname -m)

case "$os:$arch" in
    Linux:x86_64) target="herdr-linux-x86_64" ;;
    Linux:aarch64 | Linux:arm64) target="herdr-linux-aarch64" ;;
    Darwin:x86_64) target="herdr-macos-x86_64" ;;
    Darwin:arm64 | Darwin:aarch64) target="herdr-macos-aarch64" ;;
    *) echo "错误: 不支持的平台 ${os}/${arch}"; exit 1 ;;
esac

tmp_dir=$(mktemp -d)
download="${tmp_dir}/herdr"
url="https://github.com/herdrdev/herdr/releases/download/${HERDR_VERSION}/${target}"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "下载 Herdr ${HERDR_VERSION} (${target})..."
curl -fL -H "User-Agent: ${CURL_USER_AGENT}" "$url" -o "$download"

mkdir -p "$BIN_DIR"
install -m 755 "$download" "$HERDR_BIN"

echo "Herdr 安装完成: $HERDR_BIN"
"$HERDR_BIN" --version
