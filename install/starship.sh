#!/bin/bash
# 安装 Starship 提示符与最简配置，并接管 shell 配置（macOS 写 ~/.zshrc，Linux 写 ~/.bashrc）
# 检测到 Oh My Zsh / Oh My Bash 先卸载：prompt 归 starship，两个框架不再需要

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

STARSHIP_VERSION="1.27.0"
GITHUB_RELEASE_PROXY="https://ghfast.top/"
BIN_DIR="$HOME/.local/bin"
CONFIG_FILE="$HOME/.config/starship.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SOURCE="$SCRIPT_DIR/../configs/starship/starship.toml"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

安装 Starship ${STARSHIP_VERSION} 到 ${BIN_DIR}/starship，同步最简配置到
${CONFIG_FILE}，并写入 shell 托管块（历史、补全、env.d 加载、PATH、starship init）。
检测到 Oh My Zsh / Oh My Bash 时先询问卸载。

选项:
  --remove  卸载二进制、配置与 shell 托管块
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理下载 GitHub 文件
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

for dep in curl tar uname awk; do
    command -v "$dep" > /dev/null 2>&1 || {
        echo "错误: 缺少 $dep" >&2
        exit 1
    }
done

if [[ "$(uname -s)" == "Darwin" ]]; then
    RC_FILE="$HOME/.zshrc"
    RC_NAME="zshrc"
    RC_SHELL="zsh"
else
    RC_FILE="$HOME/.bashrc"
    RC_NAME="bashrc"
    RC_SHELL="bash"
fi

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "Starship" || exit 0
    remove_file "$BIN_DIR/starship"
    remove_file "$CONFIG_FILE"
    remove_managed_block "$RC_FILE" "$RC_NAME"
    exit 0
fi

# 框架的托管块与 starship 的同名，必须先删掉再写自己的；
# 官方安装器把 export/source 写在托管块之外，一并删掉，否则新 shell 会报找不到文件
if [[ -d "$HOME/.oh-my-zsh" ]] && confirm_remove "Oh My Zsh（prompt 交给 starship）"; then
    remove_dir "$HOME/.oh-my-zsh"
    remove_managed_block "$HOME/.zshrc" zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        tmp_rc="$(mktemp)"
        awk '!/oh-my-zsh\.sh/ && !/^export ZSH=/' "$HOME/.zshrc" > "$tmp_rc"
        mv "$tmp_rc" "$HOME/.zshrc"
    fi
fi
if [[ -d "$HOME/.oh-my-bash" ]] && confirm_remove "Oh My Bash（prompt 交给 starship）"; then
    remove_dir "$HOME/.oh-my-bash"
    remove_managed_block "$HOME/.bashrc" bashrc
    if [[ -f "$HOME/.bashrc" ]]; then
        tmp_rc="$(mktemp)"
        awk '!/oh-my-bash\.sh/ && !/^export OSH=/' "$HOME/.bashrc" > "$tmp_rc"
        mv "$tmp_rc" "$HOME/.bashrc"
    fi
fi

current="$("$BIN_DIR/starship" --version 2>/dev/null | awk 'NR == 1 { print $2 }')"
install_it=0
if [[ -z "$current" ]]; then
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: Starship"
        exit 0
    fi
    echo "安装 Starship ${STARSHIP_VERSION}..."
    install_it=1
elif [[ "$current" == "$STARSHIP_VERSION" ]]; then
    echo "Starship 已安装: ${current}，已是目标版本"
elif [[ "$UPDATE" != "1" ]]; then
    echo "Starship 已安装: ${current}，目标 ${STARSHIP_VERSION}，更新请加 --update"
elif confirm_update "Starship 从 $current 到 ${STARSHIP_VERSION}"; then
    install_it=1
fi

if [[ "$install_it" == "1" ]]; then
    case "$(uname -s)/$(uname -m)" in
        Darwin/arm64) target="aarch64-apple-darwin" ;;
        Darwin/x86_64) target="x86_64-apple-darwin" ;;
        Linux/aarch64) target="aarch64-unknown-linux-musl" ;;
        Linux/x86_64) target="x86_64-unknown-linux-musl" ;;
        *)
            echo "错误: 不支持的平台 $(uname -s)/$(uname -m)" >&2
            exit 1
            ;;
    esac
    url="https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${target}.tar.gz"
    if [[ "${CN:-}" == "1" ]]; then
        url="${GITHUB_RELEASE_PROXY}${url}"
    fi
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    curl -fL --retry 3 -o "$tmp_dir/starship.tar.gz" "$url"
    tar -xzf "$tmp_dir/starship.tar.gz" -C "$tmp_dir"
    mkdir -p "$BIN_DIR"
    install -m 755 "$tmp_dir/starship" "$BIN_DIR/starship"
    echo "Starship 安装完成: $BIN_DIR/starship (${STARSHIP_VERSION})"
fi

tmp_config="$(mktemp)"
cp "$CONFIG_SOURCE" "$tmp_config"
write_file_if_changed "$CONFIG_FILE" "$tmp_config"

tmp_block="$(mktemp)"
if [[ "$RC_SHELL" == "zsh" ]]; then
    cat > "$tmp_block" << 'EOF'
# 历史、补全、按键
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS EXTENDED_HISTORY
setopt AUTO_CD INTERACTIVE_COMMENTS
autoload -Uz compinit && compinit -C
zstyle ':completion:*' menu select
bindkey -e

# 加载环境变量配置
for env_file in "$HOME/.config/env.d"/*.sh(N); do
    source "$env_file"
done
EOF
else
    # pj 旧版把 env.d 加载单独写一个块，接管后删掉，否则加载两遍
    remove_managed_block "$RC_FILE" envd-loader
    cat > "$tmp_block" << 'EOF'
# 历史、按键
HISTFILE="$HOME/.bash_history"
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=erasedups:ignoreboth
shopt -s histappend cmdhist checkwinsize interactive_comments
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# 补全走系统的 bash-completion
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

# 加载环境变量配置
for env_file in "$HOME/.config/env.d"/*.sh; do
    [ -f "$env_file" ] && source "$env_file"
done
EOF
fi
cat >> "$tmp_block" << EOF

# 配置 PATH
case ":\$PATH:" in
    *":\$HOME/.local/bin:"*) ;;
    *) export PATH="\$HOME/.local/bin:\$PATH" ;;
esac

eval "\$(starship init $RC_SHELL)"
EOF
write_managed_block "$RC_FILE" "$RC_NAME" "$tmp_block"
rm -f "$tmp_block"

echo "Starship 配置完成"
echo "  config: $CONFIG_FILE"
echo "  shell:  ${RC_FILE}（托管块 ${RC_NAME}）"
echo "开一个新 shell 生效；调配置用 starship config / explain / timings"