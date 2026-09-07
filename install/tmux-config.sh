#!/bin/bash
# 安装 tmux 配置到 ~/.tmux.conf
# 可重入：内容变化才写入

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_SOURCE="$SCRIPT_DIR/../configs/tmux/tmux.conf"
TMUX_DEST="$HOME/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"
TPM_REPO="https://github.com/tmux-plugins/tpm.git"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove]

选项:
  --remove  卸载 tmux 配置与 TPM

环境变量:
  CN=1     通过国内代理 clone GitHub 仓库
EOF
}

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE=1
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
    confirm_remove "tmux 配置与 TPM" || exit 0
    remove_file "$TMUX_DEST"
    remove_dir "$TPM_DIR"
    exit 0
fi

if [[ "${CN:-}" == "1" ]]; then
    TPM_REPO="${GITHUB_PROXY_PREFIX}${TPM_REPO}"
fi

if [[ ! -f "$TMUX_SOURCE" ]]; then
    echo "错误: 源配置不存在: $TMUX_SOURCE"
    exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -d "$TPM_DIR" && ! -f "$TMUX_DEST" ]]; then
    echo "未安装，跳过: $TMUX_DEST"
    exit 0
fi

if ! command -v git &>/dev/null; then
    echo "错误: 缺少依赖 git"
    exit 1
fi

if [[ -d "$TPM_DIR/.git" ]]; then
    if [[ "${UPDATE:-}" == "1" ]] && ! confirm_update "TPM 到最新"; then
        echo "跳过 TPM 更新"
    else
        echo "更新 TPM: $TPM_DIR"
        git -C "$TPM_DIR" remote set-url origin "$TPM_REPO"
        git -C "$TPM_DIR" pull --ff-only
    fi
elif [[ "${UPDATE:-}" == "1" ]]; then
    echo "TPM 未安装，跳过"
elif [[ ! -e "$TPM_DIR" ]]; then
    echo "安装 TPM: $TPM_DIR"
    git clone --depth 1 "$TPM_REPO" "$TPM_DIR"
else
    echo "错误: TPM 目录已存在但不是 git 仓库: $TPM_DIR"
    exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -e "$TMUX_DEST" ]]; then
    echo "未安装，跳过: $TMUX_DEST"
    exit 0
fi

tmp_config="$(mktemp)"
cp "$TMUX_SOURCE" "$tmp_config"
write_file_if_changed "$TMUX_DEST" "$tmp_config"
