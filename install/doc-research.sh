#!/bin/bash
# 安装/更新 doc-research CLI（PDF/EPUB/网页 → Markdown，Markdown → HTML 站点）与 doc-research-init 辅助脚本
# PINNED_COMMIT 固定 CLI 版本；升级时人工更新此常量后重跑。辅助脚本来自 tools/doc-research-init.sh

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_URL="${REPO_URL:-https://github.com/lengmoXXL/doc-research.git}"
PINNED_COMMIT="fe3e77052686137120080b80bd3c98670028e86e"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"

BIN_DIR="${HOME}/.local/bin"
INIT_SOURCE="$SCRIPT_DIR/../tools/doc-research-init.sh"
INIT_TARGET="$BIN_DIR/doc-research-init"
VERSIONS_DIR="$HOME/.local/share/configs-setup/versions"
MARKER="$VERSIONS_DIR/doc-research"

usage() {
    cat << EOF
用法: $0 [本地仓库路径] [--remove] [--update]

选项:
  --remove  卸载 doc-research CLI 与 doc-research-init
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理访问 GitHub

给定本地路径时以 editable 模式安装（本地修改即时生效），跳过远端对比
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
            if [[ -d "$1" && -z "${LOCAL_PATH:-}" ]]; then
                LOCAL_PATH="$1"
            else
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "doc-research（CLI + doc-research-init）" || exit 0
    if command -v uv &>/dev/null; then
        uv tool uninstall doc-research || true
    fi
    remove_file "$MARKER"
    remove_file "$INIT_TARGET"
    exit 0
fi

if ! command -v uv &>/dev/null; then
    echo "错误: 缺少 uv，请先运行 $SCRIPT_DIR/uv.sh" >&2
    exit 1
fi

# ---- doc-research CLI ----

cli_installed() {
    uv tool list 2>/dev/null | grep -q '^doc-research '
}

if [[ -n "${LOCAL_PATH:-}" ]]; then
    uv tool install --force --editable "$LOCAL_PATH"
    echo "Installed doc-research CLI (editable: $LOCAL_PATH)"
else
    if [[ "${CN:-}" == "1" && "$REPO_URL" == https://github.com/* ]]; then
        REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
    fi

    if [[ "$UPDATE" == "1" ]] && ! cli_installed; then
        echo "未安装，跳过: doc-research"
    elif cli_installed && [[ "$(cat "$MARKER" 2>/dev/null)" == "$PINNED_COMMIT" ]]; then
        echo "doc-research 已是最新: ${PINNED_COMMIT:0:12}"
    else
        if [[ "$UPDATE" == "1" ]]; then
            confirm_update "doc-research 到固定版本 ${PINNED_COMMIT:0:12}" || exit 0
        fi

        uv tool install --force "git+${REPO_URL}@${PINNED_COMMIT}"
        mkdir -p "$VERSIONS_DIR"
        echo "$PINNED_COMMIT" > "$MARKER"

        echo "Installed doc-research CLI (${PINNED_COMMIT:0:12})"
    fi
fi

# ---- doc-research-init ----

if [[ "$UPDATE" == "1" && ! -e "$INIT_TARGET" ]]; then
    echo "未安装，跳过: $INIT_TARGET"
elif [[ "$UPDATE" == "1" ]] && cmp -s "$INIT_SOURCE" "$INIT_TARGET"; then
    echo "已是最新: $INIT_TARGET"
else
    if [[ "$UPDATE" == "1" ]]; then
        confirm_update "doc-research-init" || exit 0
    fi

    mkdir -p "$BIN_DIR"
    install -m 755 "$INIT_SOURCE" "$INIT_TARGET"

    echo "Installed doc-research-init to $INIT_TARGET"
fi

echo "Run it with: doc-research-init [目标目录]"
