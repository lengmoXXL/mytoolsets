#!/bin/bash
# 安装 pj 仓库命令工具到 ~/.config/env.d
# 可重入：重复执行会更新托管文件

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$HOME/.config/env.d"

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE=1
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
    shift
done

ensure_envd_loader() {
    local bashrc="$HOME/.bashrc"

    # 旧版无 guard 的写法直接删除，改用 managed block
    if ! grep -qF '# BEGIN configs envd-loader' "$bashrc" 2>/dev/null \
        && grep -qF '# 加载环境变量配置' "$bashrc" 2>/dev/null; then
        strip_block "$bashrc" '^# 加载环境变量配置$' '^done$'
    fi

    mkdir -p "$ENV_DIR"
    local block
    block="$(mktemp)"
    cat > "$block" << 'EOF'
# 加载环境变量配置
for env_file in "$HOME/.config/env.d"/*.sh; do
    [ -f "$env_file" ] && source "$env_file"
done
EOF
    write_managed_block "$bashrc" envd-loader "$block"
    rm -f "$block"
}

pj_source="$SCRIPT_DIR/../tools/pj/pj.sh"
pj_dest="$ENV_DIR/pj.sh"

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "pj" || exit 0
    remove_file "$pj_dest"
    remove_dir "$HOME/.pjs"
    echo "提示: ~/.bashrc 中的 envd-loader 配置为共享设施，未删除"
    exit 0
fi

if ! command -v fzf &>/dev/null; then
    echo "错误: fzf 未安装，请先运行 install/fzf.sh"
    exit 1
fi

if [[ "${UPDATE:-}" == "1" ]]; then
    if [[ ! -e "$pj_dest" ]]; then
        echo "未安装，跳过: $pj_dest"
        exit 0
    fi
    if cmp -s "$pj_source" "$pj_dest"; then
        echo "已是最新: $pj_dest"
        exit 0
    fi
    confirm_update "pj" || exit 0
fi

ensure_envd_loader

if [[ ! -f "$pj_source" ]]; then
    echo "错误: 源文件不存在: $pj_source"
    exit 1
fi

mkdir -p "$HOME/.pjs"

cp "$pj_source" "$pj_dest"
echo "已安装: $pj_source -> $pj_dest"

echo ""
echo "pj 安装完成"
echo "请运行 'source ~/.bashrc' 使配置生效"
