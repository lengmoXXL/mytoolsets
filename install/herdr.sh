#!/bin/bash
# 安装/更新 Herdr（GitHub Release 固定版本）及其配置（~/.config/herdr/config.toml）
# 固定版本写在 HERDR_VERSION；升级前用 tools/latest-version.sh herdr 查上游

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${HOME}/.local/bin"
HERDR_BIN="${BIN_DIR}/herdr"
HERDR_VERSION="v0.9.0"
HERDR_SOURCE="$SCRIPT_DIR/../configs/herdr/config.toml"
HERDR_DEST="$HOME/.config/herdr/config.toml"
CURL_USER_AGENT="configs-install-herdr"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 herdr 及其配置
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
    confirm_remove "herdr（CLI + 配置）" || exit 0
    remove_file "$HERDR_BIN"
    remove_file "$HERDR_DEST"
    exit 0
fi

for dep in curl head install mktemp sed uname; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

# ---- herdr ----

target_version="${HERDR_VERSION#v}"

local_herdr=""
if [[ -x "$HERDR_BIN" ]]; then
    local_herdr="$HERDR_BIN"
fi

local_version=""
if [[ -n "$local_herdr" ]]; then
    local_version=$("$local_herdr" --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\).*/\1/p' | head -1)
fi

need_install=1
if [[ -z "$local_herdr" || -z "$local_version" ]]; then
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: herdr"
        exit 0
    fi
    echo "Herdr 未安装，将安装目标版本 ${HERDR_VERSION}"
elif [[ "$local_version" == "$target_version" ]]; then
    echo "Herdr ${target_version} 已安装: $HERDR_BIN"
    need_install=0
else
    echo "当前 Herdr: ${local_version} (${local_herdr})"
    echo "目标 Herdr: ${target_version}"
    confirm_update "herdr: ${local_version} -> ${target_version}" || exit 0
fi

if [[ "$need_install" == "1" ]]; then
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
fi

# ---- 配置 ----

if [[ ! -f "$HERDR_SOURCE" ]]; then
    echo "错误: 源配置不存在: $HERDR_SOURCE"
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -e "$HERDR_DEST" ]]; then
    echo "未安装，跳过: $HERDR_DEST"
    exit 0
fi

tmp_config="$(mktemp)"
cp "$HERDR_SOURCE" "$tmp_config"
write_file_if_changed "$HERDR_DEST" "$tmp_config"

if "$HERDR_BIN" status server &>/dev/null; then
    "$HERDR_BIN" server reload-config >/dev/null
    echo "运行中的 Herdr server 已重新加载配置"
else
    echo "未检测到运行中的 Herdr server，配置将在下次启动时生效"
fi
