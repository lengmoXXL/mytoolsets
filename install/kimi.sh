#!/bin/bash
# 安装/更新 Kimi Code CLI（官方安装脚本，固定 KIMI_VERSION）及其主题
# 主题来源 configs/kimi/themes，镜像到 ${KIMI_CODE_HOME:-~/.kimi-code}/themes/

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KIMI_VERSION="0.41.0"
KIMI_BIN="$HOME/.kimi-code/bin/kimi"
KIMI_HOME="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
THEMES_SOURCE="$SCRIPT_DIR/../configs/kimi/themes"
THEMES_DEST="$KIMI_HOME/themes"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 Kimi Code 及其主题
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  KIMI_CODE_HOME  Kimi Code 数据目录，默认 ~/.kimi-code
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
    confirm_remove "kimi（CLI + 主题）" || exit 0
    remove_dir "$HOME/.kimi-code"
    [[ "$THEMES_DEST" == "$HOME/.kimi-code/themes" ]] || remove_dir "$THEMES_DEST"
    echo "提示: 官方安装器写入 shell rc 的 PATH 配置未清理，请手动检查 ~/.bashrc、~/.zshrc 等"
    exit 0
fi

for dep in curl rsync; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep" >&2
        exit 1
    fi
done

# ---- Kimi Code CLI ----

need_install=0
if [[ -x "$KIMI_BIN" ]]; then
    installed_version="$("$KIMI_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$UPDATE" != "1" ]]; then
        echo "kimi 已安装: ${installed_version:-unknown} ($KIMI_BIN)"
    elif [[ "$installed_version" == "$KIMI_VERSION" ]]; then
        echo "kimi 已是最新: ${installed_version}"
    else
        confirm_update "kimi: ${installed_version:-unknown} -> $KIMI_VERSION" || exit 0
        need_install=1
    fi
else
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: kimi"
        exit 0
    fi
    need_install=1
fi

if [[ "$need_install" == "1" ]]; then
    curl -fsSL https://code.kimi.com/kimi-code/install.sh | KIMI_VERSION="$KIMI_VERSION" bash
    "$KIMI_BIN" --version
fi

# ---- 主题 ----

if [[ ! -d "$THEMES_SOURCE" ]]; then
    echo "错误: 源目录不存在: $THEMES_SOURCE"
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -d "$THEMES_DEST" ]]; then
    echo "未安装，跳过: $THEMES_DEST"
    exit 0
fi

mkdir -p "$THEMES_DEST"
if [[ "$UPDATE" == "1" ]]; then
    changes="$(rsync -nai --delete "$THEMES_SOURCE/" "$THEMES_DEST/")"
    if [[ -z "$changes" ]]; then
        echo "已是最新: $THEMES_DEST"
        exit 0
    fi
    echo "$changes"
    confirm_update "kimi 主题" || exit 0
fi
rsync -ai --delete "$THEMES_SOURCE/" "$THEMES_DEST/"
echo "Kimi Code 主题已安装: $THEMES_DEST"
