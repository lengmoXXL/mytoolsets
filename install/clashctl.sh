#!/bin/bash
# Install clashctl from wnlen/clash-for-linux.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

REPO_URL="https://github.com/wnlen/clash-for-linux.git"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"
BRANCH="master"
INSTALL_DIR="${CLASH_FOR_LINUX_DIR:-${HOME}/.local/share/clash-for-linux}"
SUBSCRIPTION_PAGE="https://access.fengcheyun.com/#/dashboard"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 clash-for-linux
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理 clone GitHub 仓库
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
    confirm_remove "clash-for-linux" || exit 0
    remove_dir "$INSTALL_DIR"
    echo "提示: 官方 install.sh 做的系统级改动未清理，请按需手动处理"
    exit 0
fi

if ! command -v git &>/dev/null; then
    echo "错误: 缺少依赖 git"
    exit 1
fi

if [[ "${CN:-}" == "1" ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

if [[ "$UPDATE" == "1" && ! -d "$INSTALL_DIR/.git" ]]; then
    echo "未安装，跳过: $INSTALL_DIR"
    exit 0
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "clash-for-linux 仓库已存在: $INSTALL_DIR"
elif [[ -e "$INSTALL_DIR" ]]; then
    echo "错误: 目标路径已存在但不是 git 仓库: $INSTALL_DIR"
    exit 1
else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    echo "克隆 clash-for-linux 到: $INSTALL_DIR"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

if [[ "$UPDATE" == "1" ]]; then
    confirm_update "clashctl（重跑官方安装流程）" || exit 0
fi

echo "订阅后台: $SUBSCRIPTION_PAGE"
echo "请从页面复制订阅链接，并粘贴到接下来的安装提示中。"

if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe &>/dev/null; then
    cmd.exe /c start "" "$SUBSCRIPTION_PAGE" >/dev/null 2>&1 &
elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v xdg-open &>/dev/null; then
    xdg-open "$SUBSCRIPTION_PAGE" >/dev/null 2>&1 &
elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v gio &>/dev/null; then
    gio open "$SUBSCRIPTION_PAGE" >/dev/null 2>&1 &
else
    echo "未检测到可用的图形浏览器，请手动打开上面的链接。"
fi

echo "执行 clash-for-linux 官方安装脚本..."
bash "$INSTALL_DIR/install.sh"
