#!/bin/bash
# 安装旺财配置到 ~/.config/wangcai/init.ts；local.ts（机器相关）缺失才生成、不覆盖
# 可重入：内容变化才写入

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WANGCAI_SOURCE="$SCRIPT_DIR/../configs/wangcai/init.ts"
WANGCAI_DEST="$HOME/.config/wangcai/init.ts"
WANGCAI_LOCAL_SOURCE="$SCRIPT_DIR/../configs/wangcai/local.ts"
WANGCAI_LOCAL_DEST="$HOME/.config/wangcai/local.ts"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

安装旺财配置到 ~/.config/wangcai/init.ts；local.ts（network、machines，机器相关）缺失才生成、不覆盖。

选项:
  --remove  卸载旺财配置
  --update  更新已安装的工具（未安装则跳过）
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
    confirm_remove "旺财配置" || exit 0
    remove_file "$WANGCAI_DEST"
    remove_file "$WANGCAI_LOCAL_DEST"
    exit 0
fi

if [[ ! -f "$WANGCAI_SOURCE" ]]; then
    echo "错误: 源配置不存在: $WANGCAI_SOURCE"
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -e "$WANGCAI_DEST" ]]; then
    echo "未安装，跳过: $WANGCAI_DEST"
    exit 0
fi

tmp_config="$(mktemp)"
cp "$WANGCAI_SOURCE" "$tmp_config"
write_file_if_changed "$WANGCAI_DEST" "$tmp_config"

# local.ts 是机器相关配置（network、machines）：缺失才生成，已存在不覆盖、不同步
if [[ -e "$WANGCAI_LOCAL_DEST" ]]; then
    echo "$WANGCAI_LOCAL_DEST 已存在，跳过（机器相关配置）"
else
    if [[ ! -f "$WANGCAI_LOCAL_SOURCE" ]]; then
        echo "错误: 源配置不存在: $WANGCAI_LOCAL_SOURCE"
        exit 1
    fi
    cp "$WANGCAI_LOCAL_SOURCE" "$WANGCAI_LOCAL_DEST"
    echo "$WANGCAI_LOCAL_DEST 已生成（机器相关配置，之后不覆盖）"
fi

# 静态 import .ts 需 tsconfig 开 allowImportingTsExtensions（app 不校验类型，仅编辑器用）；缺失才补
tsconfig="$HOME/.config/wangcai/tsconfig.json"
if [[ -f "$tsconfig" ]] && ! grep -q '"allowImportingTsExtensions"' "$tsconfig"; then
    tmp_tsconfig="$(mktemp)"
    awk '/"compilerOptions"[[:space:]]*:[[:space:]]*\{/ && !inserted { print; print "    \"allowImportingTsExtensions\": true,"; inserted=1; next } { print }' "$tsconfig" > "$tmp_tsconfig"
    if grep -q '"allowImportingTsExtensions"' "$tmp_tsconfig"; then
        mv "$tmp_tsconfig" "$tsconfig"
        echo "$tsconfig 已补 allowImportingTsExtensions"
    else
        rm -f "$tmp_tsconfig"
    fi
fi

if [[ ! -d "/Applications/旺财.app" ]]; then
    echo "提示: 旺财未安装（https://github.com/lengmoXXL/WangCai/releases）"
fi
