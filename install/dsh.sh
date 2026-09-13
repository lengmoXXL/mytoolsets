#!/bin/bash
# 安装/更新 DeepSeek Harness CLI（dsh）到 ~/.local
# 固定版本写在 DSH_VERSION；升级前用 tools/latest-version.sh dsh 查上游（next 通道）

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
NPM_PREFIX="${HOME}/.local"
DSH_PACKAGE="@deepseek-ai/dsh"
DSH_VERSION="0.1.5-rc.2"
DSH_BIN="${BIN_DIR}/dsh"
MIN_NODE_VERSION="22.19.0"
NPM_REGISTRY=""

usage() {
    cat << EOF
用法: $0 [--registry URL] [--remove] [--update]

选项:
  --registry URL  使用指定 npm registry
  --remove        卸载 dsh
  --update        更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     使用 npmmirror npm registry
EOF
}

UPDATE=0
REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry)
            if [[ $# -lt 2 ]]; then
                usage
                exit 1
            fi
            NPM_REGISTRY="$2"
            shift
            ;;
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
    confirm_remove "dsh" || exit 0
    if command -v npm &>/dev/null; then
        npm uninstall -g --prefix "$NPM_PREFIX" "$DSH_PACKAGE"
    else
        remove_file "$DSH_BIN"
        remove_dir "$NPM_PREFIX/lib/node_modules/@deepseek-ai/dsh"
    fi
    exit 0
fi

if [[ "${CN:-}" == "1" && -z "$NPM_REGISTRY" ]]; then
    NPM_REGISTRY="https://registry.npmmirror.com"
fi

node_ready() {
    command -v node &>/dev/null &&
        command -v npm &>/dev/null &&
        node -e '
            const [major, minor, patch] = process.versions.node.split(".").map(Number);
            process.exit(major > 22 || (major === 22 && (minor > 19 || (minor === 19 && patch >= 0))) ? 0 : 1);
        ' &>/dev/null
}

if ! node_ready; then
    echo "错误: dsh 需要 Node.js ${MIN_NODE_VERSION}+ 和 npm，请先运行 install/compiler/node.sh" >&2
    echo "当前 node: $(node --version 2>/dev/null || echo missing)" >&2
    echo "当前 npm: $(npm --version 2>/dev/null || echo missing)" >&2
    exit 1
fi

local_version=""
if [[ -x "$DSH_BIN" ]]; then
    local_version="$("$DSH_BIN" --version 2>/dev/null | tr -d '[:space:]')"
fi

if [[ "$UPDATE" == "1" && ! -x "$DSH_BIN" ]]; then
    echo "未安装，跳过: dsh"
    exit 0
fi

if [[ "$local_version" == "$DSH_VERSION" ]]; then
    echo "dsh ${DSH_VERSION} 已安装: $DSH_BIN"
    exit 0
fi

if [[ -n "$local_version" ]]; then
    echo "当前 dsh: ${local_version} (${DSH_BIN})"
    echo "目标 dsh: ${DSH_VERSION}"
    confirm_update "dsh: ${local_version} -> ${DSH_VERSION}" || exit 0
else
    echo "dsh 未安装，将安装目标版本 ${DSH_VERSION}"
fi

mkdir -p "$BIN_DIR"

npm_args=(
    install -g
    --min-release-age=0
    --prefix "$NPM_PREFIX"
    --no-fund
    --no-audit
    --loglevel=error
    --progress=false
)

if [[ -n "$NPM_REGISTRY" ]]; then
    npm_args+=(--registry "$NPM_REGISTRY")
fi

npm_args+=("${DSH_PACKAGE}@${DSH_VERSION}")

echo "安装 dsh ${DSH_VERSION}..."
npm "${npm_args[@]}"

echo "dsh 安装完成: $DSH_BIN"
"$DSH_BIN" --version
echo "提示: 可运行 ./install/dsh-plugins.sh 安装 dsh 插件"
