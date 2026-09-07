#!/bin/bash
# 安装 clang/clangd - 使用 yum
# 可重入：已安装时跳过

set -e

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

UPDATE=0
REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove) REMOVE=1 ;;
        --update) UPDATE=1 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "clang" || exit 0
    sudo yum remove -y clang clang-tools-extra
    exit 0
fi

if [[ "$UPDATE" == "1" ]] && ! rpm -q clang &>/dev/null; then
    echo "未安装，跳过: clang"
    exit 0
fi

if rpm -q clang &>/dev/null; then
    echo "clang 已安装"
    clang --version | head -1
    exit 0
fi

echo "安装 clang..."
sudo yum install -y clang clang-tools-extra

echo ""
echo "clang 安装完成"
clang --version | head -1