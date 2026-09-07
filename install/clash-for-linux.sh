#!/bin/bash
# 安装 clash-for-linux-install 到 ~/.local/share/clash-for-linux-install

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

REPO_URL="https://github.com/nelvko/clash-for-linux-install.git"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"
BRANCH="master"
SHARE_DIR="${HOME}/.local/share"
INSTALL_DIR="${SHARE_DIR}/clash-for-linux-install"

usage() {
    cat << EOF
用法: $0 [--remove]

选项:
  --remove  卸载 clash-for-linux 及 .bashrc 配置

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
    confirm_remove "clash-for-linux" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_managed_block "$HOME/.bashrc" noclobber-off
    echo "提示: 官方 install.sh 做的系统级改动（/opt、systemd 等）未清理，请按需手动处理"
    exit 0
fi

if [[ "${CN:-}" == "1" ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

mkdir -p "$SHARE_DIR"

if [[ "${UPDATE:-}" == "1" && ! -d "$INSTALL_DIR/.git" ]]; then
    echo "未安装，跳过: $INSTALL_DIR"
    exit 0
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL"
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
    if [[ "${UPDATE:-}" == "1" ]]; then
        local_head="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
        remote_head="$(git -C "$INSTALL_DIR" rev-parse "origin/$BRANCH")"
        if [[ "$local_head" == "$remote_head" ]]; then
            echo "clash-for-linux 已是最新: ${local_head:0:12}"
            exit 0
        fi
        confirm_update "clash-for-linux: ${local_head:0:12} -> ${remote_head:0:12}" || exit 0
    else
        echo "仓库已存在，更新到最新 ${BRANCH}: $INSTALL_DIR"
    fi
    git -C "$INSTALL_DIR" checkout "$BRANCH"
    git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
elif [[ -e "$INSTALL_DIR" ]]; then
    echo "错误: 目标路径已存在但不是 git 仓库: $INSTALL_DIR"
    exit 1
else
    echo "克隆仓库到: $INSTALL_DIR"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

echo "执行安装脚本..."
cd "$INSTALL_DIR"
bash install.sh

# 在 .bashrc 中关闭 noclobber（oh-my-bash 默认开启会导致文件覆盖报错）
BASHRC="${HOME}/.bashrc"

# 旧版标记不同名，直接删除，改用 managed block
if ! grep -qF '# BEGIN configs noclobber-off' "$BASHRC" 2>/dev/null \
    && grep -qF '# noclobber-off START' "$BASHRC" 2>/dev/null; then
    strip_block "$BASHRC" '^# noclobber-off START$' '^# noclobber-off END$'
fi

noclobber_block="$(mktemp)"
cat > "$noclobber_block" << 'EOF'
# 关闭 noclobber，允许 > 覆盖已存在文件
set +o noclobber
EOF
write_managed_block "$BASHRC" noclobber-off "$noclobber_block"
rm -f "$noclobber_block"

