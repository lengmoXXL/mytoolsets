#!/bin/bash
# 一键初始化：--init 基础配置，其余为场景（需先 --init）

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_MARKER="$HOME/.local/share/configs-setup/initialized"
MODE="init"

usage() {
    cat << EOF
用法: $0 [--init | --nvim]

环境变量:
  CN=1     子脚本使用国内代理/镜像

模式:
  --init   基础配置: secrets、shell 环境（env.d）、pi agent（含配置与 extensions）、python、系统配置（默认）
  --nvim   编辑场景: Neovim + 配置（需先 --init）
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        --init)
            MODE="init"
            ;;
        --nvim)
            MODE="nvim"
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
    shift
done

run() {
    echo ""
    echo "==> $*"
    "$@"
}

case "$MODE" in
    init)
        # 基础配置: secrets、shell 环境（env.d）、pi agent、python
        run "$ROOT/tools/secrets.sh" init
        if [[ "$(uname -s)" == "Darwin" ]]; then
            run "$ROOT/install/oh-my-zsh.sh"
        else
            run "$ROOT/install/oh-my-bash.sh"
        fi
        run "$ROOT/install/compiler/node.sh"
        run "$ROOT/install/pi.sh"
        run python3 "$ROOT/install/pi-auth.py"
        run "$ROOT/install/uv.sh"
        run "$ROOT/install/compiler/python.sh"

        # 系统配置
        if [[ "$(uname -s)" == "Darwin" ]]; then
            run "$ROOT/install/fonts.sh"
            if [[ -d "/Applications/Ghostty.app" ]]; then
                echo "Ghostty 已安装"
            else
                echo "Ghostty 未安装，打开下载页面，请手动下载并安装到 /Applications"
                open "https://ghostty.org/download"
                read -rp "安装完成后按回车继续... "
                if [[ ! -d "/Applications/Ghostty.app" ]]; then
                    echo "错误: 未检测到 /Applications/Ghostty.app" >&2
                    exit 1
                fi
            fi
            run "$ROOT/install/ghostty-config.sh"
        else
            run "$ROOT/install/ghostty-terminfo.sh"
        fi

        mkdir -p "$(dirname "$INIT_MARKER")"
        touch "$INIT_MARKER"
        ;;
    nvim)
        if [[ ! -f "$INIT_MARKER" ]]; then
            echo "错误: 尚未初始化，请先运行 $0 --init" >&2
            exit 1
        fi
        run "$ROOT/install/nvim.sh"
        ;;
esac

# ${MODE} 花括号必需：bash 3.2 会把 $MODE 后紧贴的多字节字符首字节并进变量名（展开为空并吞字节）
echo ""
echo "setup 完成（${MODE}）"
