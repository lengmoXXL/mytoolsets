#!/bin/bash
# 安装 Oh My Bash 并配置 ~/.bashrc（theme、env.d 加载、PATH）
# sync: skip

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

GITHUB_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 Oh My Bash 及 .bashrc 配置
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
    confirm_remove "Oh My Bash" || exit 0
    remove_dir "$HOME/.oh-my-bash"
    remove_managed_block "$HOME/.bashrc" bashrc
    exit 0
fi

proxy_url() {
    if [[ "${CN:-}" == "1" ]]; then
        echo "${GITHUB_PROXY}$1"
    else
        echo "$1"
    fi
}


omb_dir="$HOME/.oh-my-bash"
omb_url="https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh"
omb_repo="https://github.com/ohmybash/oh-my-bash.git"
rcfile="$HOME/.bashrc"
theme="purity"

if [[ -d "$omb_dir" ]]; then
    echo "Oh My Bash 已安装: $omb_dir"
    if [[ "$UPDATE" == "1" ]]; then
        if confirm_update "Oh My Bash 到最新"; then
            git -C "$omb_dir" pull --ff-only
        fi
    fi
else
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: Oh My Bash"
        exit 0
    fi
    echo "安装 Oh My Bash..."
    REMOTE="$(proxy_url "$omb_repo")" \
        bash -c "$(curl -fsSL "$(proxy_url "$omb_url")")"
fi


block="$(mktemp)"
{
    echo "OSH_THEME=\"$theme\""
    echo ""
    echo "# 加载环境变量配置"
    echo 'for env_file in "$HOME/.config/env.d"/*.sh; do'
    echo '    [ -f "$env_file" ] || continue'
    echo '    source "$env_file"'
    echo 'done'
    echo ""
    echo "# 配置 PATH"
    echo 'case ":$PATH:" in'
    echo '    *":$HOME/.local/bin:"*) ;;'
    echo '    *) export PATH="$HOME/.local/bin:$PATH" ;;'
    echo 'esac'
} > "$block"

# Oh My Bash 安装器生成的 bashrc 会 source oh-my-bash.sh，block 需插到它之前让 OSH_THEME 先生效
write_managed_block "$rcfile" bashrc "$block" 'oh-my-bash\.sh'
rm -f "$block"

echo "Oh My Bash 配置完成"
echo "  theme: $theme"
