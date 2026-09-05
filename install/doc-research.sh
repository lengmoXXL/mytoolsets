#!/bin/bash
# 安装/更新 doc-research CLI（PDF/EPUB/网页 → Markdown，Markdown → HTML 站点）
# PINNED_COMMIT 固定安装版本；升级时人工更新此常量后重跑

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

REPO_URL="${REPO_URL:-https://github.com/lengmoXXL/doc-research.git}"
PINNED_COMMIT="584d66edecd954b0b153456be8814736b0d94729"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [本地仓库路径]

环境变量:
  CN=1     通过国内代理访问 GitHub

给定本地路径时以 editable 模式安装（本地修改即时生效），跳过远端对比
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

if ! command -v uv &>/dev/null; then
    echo "错误: 缺少 uv，请先运行 $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uv.sh" >&2
    exit 1
fi

if [[ -n "${LOCAL_PATH:-}" ]]; then
    uv tool install --force --editable "$LOCAL_PATH"
    echo "Installed doc-research CLI (editable: $LOCAL_PATH)"
    exit 0
fi

if [[ "${CN:-}" == "1" && "$REPO_URL" == https://github.com/* ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

VERSIONS_DIR="$HOME/.local/share/configs-setup/versions"
MARKER="$VERSIONS_DIR/doc-research"

if [[ "${UPDATE:-}" == "1" ]] && ! uv tool list 2>/dev/null | grep -q "^doc-research "; then
    echo "未安装，跳过: doc-research"
    exit 0
fi

if uv tool list 2>/dev/null | grep -q "^doc-research " \
    && [[ "$(cat "$MARKER" 2>/dev/null)" == "$PINNED_COMMIT" ]]; then
    echo "doc-research 已是最新: ${PINNED_COMMIT:0:12}"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" ]]; then
    confirm_update "doc-research 到固定版本 ${PINNED_COMMIT:0:12}" || exit 0
fi

uv tool install --force "git+${REPO_URL}@${PINNED_COMMIT}"
mkdir -p "$VERSIONS_DIR"
echo "$PINNED_COMMIT" > "$MARKER"

echo "Installed doc-research CLI ($PINNED_COMMIT)"
