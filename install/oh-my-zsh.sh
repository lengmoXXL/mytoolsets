#!/bin/bash
# 安装 Oh My Zsh 并配置 ~/.zshrc（theme、env.d 加载、PATH）
# sync: skip

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

GITHUB_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 Oh My Zsh 及 .zshrc 配置
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理下载 GitHub 文件与克隆仓库
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
    confirm_remove "Oh My Zsh" || exit 0
    remove_dir "$HOME/.oh-my-zsh"
    remove_managed_block "$HOME/.zshrc" zshrc
    exit 0
fi

proxy_url() {
    if [[ "${CN:-}" == "1" ]]; then
        echo "${GITHUB_PROXY}$1"
    else
        echo "$1"
    fi
}


omz_dir="$HOME/.oh-my-zsh"
omz_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
omz_repo="https://github.com/ohmyzsh/ohmyzsh.git"
rcfile="$HOME/.zshrc"
theme="refined"

if [[ -d "$omz_dir" ]]; then
    echo "Oh My Zsh 已安装: $omz_dir"
    if [[ "$UPDATE" == "1" ]]; then
        if confirm_update "Oh My Zsh 到最新"; then
            git -C "$omz_dir" pull --ff-only
        fi
    fi
else
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: Oh My Zsh"
        exit 0
    fi
    echo "安装 Oh My Zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes REMOTE="$(proxy_url "$omz_repo")" \
        sh -c "$(curl -fsSL "$(proxy_url "$omz_url")")"
fi


block="$(mktemp)"
{
    echo "export ZSH=\"$omz_dir\""
    echo "ZSH_THEME=\"$theme\""
    echo "plugins=(git)"
    echo 'source "$ZSH/oh-my-zsh.sh"'
    echo ""
    echo "# 加载环境变量配置"
    echo 'for env_file in "$HOME/.config/env.d"/*.sh(N); do'
    echo '    source "$env_file"'
    echo 'done'
    echo ""
    echo "# 配置 PATH"
    echo 'case ":$PATH:" in'
    echo '    *":$HOME/.local/bin:"*) ;;'
    echo '    *) export PATH="$HOME/.local/bin:$PATH" ;;'
    echo 'esac'
} > "$block"

write_managed_block "$rcfile" zshrc "$block"
rm -f "$block"

echo "Oh My Zsh 配置完成"
echo "  theme: $theme"
