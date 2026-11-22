#!/bin/bash
# 安装 pj 仓库命令工具到 ~/.config/env.d
# 可重入：重复执行会更新托管文件

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$HOME/.config/env.d"

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
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
    shift
done

pj_source="$SCRIPT_DIR/../tools/pj/pj.sh"
pj_dest="$ENV_DIR/pj.sh"

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "pj" || exit 0
    remove_file "$pj_dest"
    remove_dir "$HOME/.pjs"
    exit 0
fi

if ! command -v fzf &>/dev/null; then
    echo "错误: fzf 未安装，请先运行 install/fzf.sh"
    exit 1
fi

if [[ "$UPDATE" == "1" ]]; then
    if [[ ! -e "$pj_dest" ]]; then
        echo "未安装，跳过: $pj_dest"
        exit 0
    fi
    if cmp -s "$pj_source" "$pj_dest"; then
        echo "已是最新: $pj_dest"
        exit 0
    fi
    confirm_update "pj" || exit 0
fi

if [[ ! -f "$pj_source" ]]; then
    echo "错误: 源文件不存在: $pj_source"
    exit 1
fi

mkdir -p "$ENV_DIR" "$HOME/.pjs"

cp "$pj_source" "$pj_dest"
echo "已安装: $pj_source -> $pj_dest"

echo ""
echo "pj 安装完成"
echo "请开一个新 shell 使配置生效"
