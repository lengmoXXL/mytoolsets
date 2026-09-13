#!/bin/bash
# 安装/更新 pnpm 到 ~/.local（dsh plugin 管理 profile 依赖用）
# 固定版本写在 PNPM_VERSION；升级前用 tools/latest-version.sh pnpm 查上游
# 不加 --ignore-scripts：pnpm 的 pre/postinstall 会把 bin 换成宿主原生二进制，
# 被 npm 拦下时 bin 回退为 node 包装脚本，仍可用（仅启动略慢）

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
NPM_PREFIX="${HOME}/.local"
PNPM_PACKAGE="pnpm"
PNPM_VERSION="12.4.1"
PNPM_BIN="${BIN_DIR}/pnpm"
MIN_NODE_MAJOR="18"
NPM_REGISTRY=""

usage() {
    cat << EOF
用法: $0 [--registry URL] [--remove] [--update]

选项:
  --registry URL  使用指定 npm registry
  --remove        卸载 pnpm
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
    confirm_remove "pnpm" || exit 0
    if command -v npm &>/dev/null; then
        npm uninstall -g --prefix "$NPM_PREFIX" "$PNPM_PACKAGE"
    else
        remove_file "$PNPM_BIN"
        remove_file "${BIN_DIR}/pn"
        remove_file "${BIN_DIR}/pnpx"
        remove_file "${BIN_DIR}/pnx"
        remove_dir "$NPM_PREFIX/lib/node_modules/pnpm"
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
            process.exit(Number(process.versions.node.split(".")[0]) >= Number(process.argv[1]) ? 0 : 1);
        ' "$MIN_NODE_MAJOR" &>/dev/null
}

if ! node_ready; then
    echo "错误: pnpm 需要 Node.js ${MIN_NODE_MAJOR}+ 和 npm，请先运行 install/compiler/node.sh" >&2
    echo "当前 node: $(node --version 2>/dev/null || echo missing)" >&2
    echo "当前 npm: $(npm --version 2>/dev/null || echo missing)" >&2
    exit 1
fi

local_version=""
if [[ -x "$PNPM_BIN" ]]; then
    local_version="$("$PNPM_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi

if [[ "$UPDATE" == "1" && ! -x "$PNPM_BIN" ]]; then
    echo "未安装，跳过: pnpm"
    exit 0
fi

if [[ "$local_version" == "$PNPM_VERSION" ]]; then
    echo "pnpm ${PNPM_VERSION} 已安装: $PNPM_BIN"
    exit 0
fi

if [[ -n "$local_version" ]]; then
    echo "当前 pnpm: ${local_version} (${PNPM_BIN})"
    echo "目标 pnpm: ${PNPM_VERSION}"
    confirm_update "pnpm: ${local_version} -> ${PNPM_VERSION}" || exit 0
else
    echo "pnpm 未安装，将安装目标版本 ${PNPM_VERSION}"
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

npm_args+=("${PNPM_PACKAGE}@${PNPM_VERSION}")

echo "安装 pnpm ${PNPM_VERSION}..."
npm "${npm_args[@]}"

echo "pnpm 安装完成: $PNPM_BIN"
"$PNPM_BIN" --version
