#!/bin/bash
# 安装 dsh 用户设置（configs/dsh/settings.yaml → $DSH_HOME/settings.yaml）
# 单文件用 write_file_if_changed；密钥不在这里管（见 install/dsh-auth.py）

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/../configs/dsh/settings.yaml"
TARGET="${DSH_HOME:-$HOME/.dsh}/settings.yaml"

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

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "dsh 用户设置" || exit 0
    remove_file "$TARGET"
    exit 0
fi

if [[ ! -f "$SOURCE" ]]; then
    echo "错误: 缺少 $SOURCE" >&2
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -f "$TARGET" ]]; then
    echo "未安装，跳过: $TARGET"
    exit 0
fi

tmp_config="$(mktemp)"
cp "$SOURCE" "$tmp_config"
write_file_if_changed "$TARGET" "$tmp_config"

echo "提示: dsh 以本文件为准，它自己写的运行态字段（ui-onboarding 等）不会保留"
