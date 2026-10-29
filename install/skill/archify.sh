#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

REPO_URL="${REPO_URL:-https://github.com/tt-a1i/archify.git}"
PINNED_COMMIT="e3920894b0f30db7d5fc7d7d4ece57b304c17015"  # v3.2.0
SKILL_PATH="${SKILL_PATH:-archify}"
DEST_ROOT="${AGENTS_HOME:-$HOME/.agents}/skills"
DEST="$DEST_ROOT/archify"
TMP_DIR="$(mktemp -d)"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"

trap 'rm -rf "$TMP_DIR"' EXIT

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 archify skill
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理 clone GitHub 仓库
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

if [[ "$UPDATE" == "1" && ! -d "$DEST" ]]; then
    echo "未安装，跳过: $DEST"
    exit 0
fi

VERSIONS_DIR="$HOME/.local/share/configs-setup/versions"
MARKER="$VERSIONS_DIR/archify"

if [[ "$REMOVE" == "1" ]]; then
  confirm_remove "archify skill" || exit 0
  remove_dir "$DEST"
  remove_file "$MARKER"
  exit 0
fi

if [[ -d "$DEST" && "$UPDATE" != "1" ]]; then
    echo "archify 已安装: $DEST"
    exit 0
fi

if [[ "${CN:-}" == "1" && "$REPO_URL" == https://github.com/* ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

if [[ -d "$DEST" && "$(cat "$MARKER" 2>/dev/null)" == "$PINNED_COMMIT" ]]; then
    echo "archify 已是最新: ${PINNED_COMMIT:0:12}"
    exit 0
fi

if [[ "$UPDATE" == "1" ]]; then
    confirm_update "archify -> ${PINNED_COMMIT:0:12}" || exit 0
fi

if ! command -v node >/dev/null; then
    echo "错误: node 未安装"
    echo "请先运行 install/compiler/node.sh 安装 Node"
    exit 1
fi

echo "Cloning $REPO_URL @ ${PINNED_COMMIT:0:12}..."
git -C "$TMP_DIR" init repo
git -C "$TMP_DIR/repo" remote add origin "$REPO_URL"
git -C "$TMP_DIR/repo" sparse-checkout set "$SKILL_PATH"
git -C "$TMP_DIR/repo" fetch --filter=blob:none --depth 1 origin "$PINNED_COMMIT"
git -C "$TMP_DIR/repo" checkout FETCH_HEAD

SRC="$TMP_DIR/repo/$SKILL_PATH"
if [[ ! -f "$SRC/SKILL.md" ]]; then
    echo "Missing skill source: $SRC" >&2
    exit 1
fi

mkdir -p "$DEST_ROOT"
rm -rf "$DEST"
cp -a "$SRC" "$DEST"

mkdir -p "$VERSIONS_DIR"
echo "$PINNED_COMMIT" > "$MARKER"

echo "Installed archify to $DEST"
echo "Restart your agent to pick up new skills."
