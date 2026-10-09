#!/bin/bash
# Install or update the Codex CLI release package from GitHub Releases.
# The CLI only works as a complete release package (codex-package.json plus
# codex-resources), so install the whole tree into PACKAGE_DIR and expose the
# ~/.local/bin entries as symlinks into it.
# The installed version is pinned here; use tools/latest-version.sh to check updates.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
PACKAGE_DIR="${HOME}/.local/share/codex"
CODEX_BIN="${BIN_DIR}/codex"
CODE_MODE_HOST_BIN="${BIN_DIR}/codex-code-mode-host"
CODEX_VERSION="0.162.0"
CURL_USER_AGENT="configs-install-codex"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 codex
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
    confirm_remove "codex" || exit 0
    remove_file "$CODEX_BIN"
    remove_file "$CODE_MODE_HOST_BIN"
    remove_dir "$PACKAGE_DIR"
    exit 0
fi

for dep in curl sed tar rsync uname mktemp; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

target_tag="rust-v${CODEX_VERSION}"

local_codex=""
if [[ -x "$CODEX_BIN" ]]; then
    local_codex="$CODEX_BIN"
fi

local_version=""
if [[ -n "$local_codex" ]]; then
    local_version=$("$local_codex" --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\).*/\1/p' | head -1)
fi

compare_versions() {
    local left="$1"
    local right="$2"
    local IFS=.
    local left_parts right_parts index left_part right_part

    read -r -a left_parts <<< "$left"
    read -r -a right_parts <<< "$right"

    for index in 0 1 2; do
        left_part="${left_parts[$index]:-0}"
        right_part="${right_parts[$index]:-0}"
        left_part="${left_part%%[^0-9]*}"
        right_part="${right_part%%[^0-9]*}"
        left_part="${left_part:-0}"
        right_part="${right_part:-0}"

        if ((10#$left_part < 10#$right_part)); then
            echo -1
            return
        fi
        if ((10#$left_part > 10#$right_part)); then
            echo 1
            return
        fi
    done

    echo 0
}

if [[ -z "$local_codex" || -z "$local_version" ]]; then
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: codex"
        exit 0
    fi
    echo "Codex 未安装，将安装目标版本 ${CODEX_VERSION}"
else
    echo "当前 Codex: ${local_version} (${local_codex})"
    echo "目标 Codex: ${CODEX_VERSION}"

    version_cmp=$(compare_versions "$local_version" "$CODEX_VERSION")
    if [[ "$version_cmp" == "0" ]]; then
        if [[ -f "${PACKAGE_DIR}/codex-package.json" && -x "$CODE_MODE_HOST_BIN" ]]; then
            echo "Codex 已是目标版本"
            exit 0
        fi
        echo "Codex 已是目标版本，但本地包不完整，将重新安装"
        confirm_update "codex 包修复安装" || exit 0
    elif [[ "$version_cmp" == "1" ]]; then
        echo "本地 Codex 版本高于目标版本，不执行更新"
        exit 0
    else
        confirm_update "codex: ${local_version} -> ${CODEX_VERSION}" || exit 0
    fi
fi

os=$(uname -s)
arch=$(uname -m)

case "$os:$arch" in
    Linux:x86_64) target="x86_64-unknown-linux-musl" ;;
    Linux:aarch64 | Linux:arm64) target="aarch64-unknown-linux-musl" ;;
    Darwin:x86_64) target="x86_64-apple-darwin" ;;
    Darwin:arm64 | Darwin:aarch64) target="aarch64-apple-darwin" ;;
    *) echo "错误: 不支持的平台 ${os}/${arch}"; exit 1 ;;
esac

tmp_dir=$(mktemp -d)
tarball="${tmp_dir}/codex-package.tar.gz"
url="https://github.com/openai/codex/releases/download/${target_tag}/codex-package-${target}.tar.gz"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "下载 Codex ${CODEX_VERSION} (${target})..."
curl -fL -H "User-Agent: ${CURL_USER_AGENT}" "$url" -o "$tarball"
package_src="${tmp_dir}/pkg"
mkdir -p "$package_src"
tar -xzf "$tarball" -C "$package_src"

if [[ ! -f "${package_src}/codex-package.json" || ! -f "${package_src}/bin/codex" || ! -f "${package_src}/bin/codex-code-mode-host" ]]; then
    echo "错误: Codex 压缩包中缺少 codex-package.json 或二进制文件"
    exit 1
fi

mkdir -p "$PACKAGE_DIR" "$BIN_DIR"
rsync -ai --delete "${package_src}/" "${PACKAGE_DIR}/" > /dev/null
ln -sfn "${PACKAGE_DIR}/bin/codex" "$CODEX_BIN"
ln -sfn "${PACKAGE_DIR}/bin/codex-code-mode-host" "$CODE_MODE_HOST_BIN"

echo "Codex 安装完成: $CODEX_BIN"
"$CODEX_BIN" --version
