#!/bin/bash
# 调整 herdr pane 的分栏比例，默认单步幅度为 herdr 键位步长的一半
# herdr 键位步长硬编码 0.05（split ratio）且不可配置，只有 CLI 的 --amount 能传自定义幅度

set -euo pipefail

usage() {
    cat << EOF
用法: herdr-resize <方向> [步数] [选项]

方向: left|right|up|down 或 h|l|k|j
步数: 正整数，默认 1；实际幅度 = 步数 x 单步幅度

选项:
  -a, --amount <float>  单步幅度，默认 0.025（herdr 键位步长 0.05 的一半）
  -p, --pane <id>       目标 pane，默认当前 pane
  -h, --help            显示帮助
EOF
}

step="0.025"
pane=""
direction=""
count=1

need_value() {
    if [[ $# -lt 2 || -z "$2" ]]; then
        echo "错误: $1 需要一个参数" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a | --amount)
            need_value "$@"
            step="$2"
            shift 2
            ;;
        -p | --pane)
            need_value "$@"
            pane="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            echo "错误: 未知参数 $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$direction" ]]; then
                direction="$1"
            elif [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]; then
                count="$1"
            else
                echo "错误: 未知参数 $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

case "$direction" in
    h | left) direction="left" ;;
    l | right) direction="right" ;;
    k | up) direction="up" ;;
    j | down) direction="down" ;;
    "")
        echo "错误: 缺少方向" >&2
        usage >&2
        exit 1
        ;;
    *)
        echo "错误: 无效方向 $direction" >&2
        exit 1
        ;;
esac

if ! [[ "$step" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    echo "错误: 幅度不是数字: $step" >&2
    exit 1
fi

if ! command -v herdr &>/dev/null; then
    echo "错误: 缺少依赖 herdr，请先运行 install/herdr.sh" >&2
    exit 1
fi

amount="$(awk -v s="$step" -v c="$count" 'BEGIN { printf "%.4f", s * c }')"

if [[ -n "$pane" ]]; then
    herdr pane resize --direction "$direction" --amount "$amount" --pane "$pane" >/dev/null
else
    herdr pane resize --direction "$direction" --amount "$amount" --current >/dev/null
fi
