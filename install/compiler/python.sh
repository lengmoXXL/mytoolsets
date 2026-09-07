#!/bin/bash
# 使用 uv 创建隔离的 Python 3.11 虚拟环境到 ~/.local/python3.11
# 可重入：已创建时跳过

set -e

INSTALL_DIR="${HOME}/.local/python3.11"
BIN_DIR="${HOME}/.local/bin"
ENV_DIR="$HOME/.config/env.d"
UV_BIN="${BIN_DIR}/uv"

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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "Python 3.11 虚拟环境" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_file "$BIN_DIR/python3"
    remove_file "$BIN_DIR/pip3"
    remove_file "$ENV_DIR/python.sh"
    echo "提示: uv 安装的 python 3.11 运行时未删除，可用 'uv python uninstall 3.11' 手动清理"
    exit 0
fi

mkdir -p "$BIN_DIR"

if [[ ! -x "$UV_BIN" ]]; then
    echo "错误: 缺少 uv，请先运行 $(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/uv.sh" >&2
    exit 1
fi

UV_CMD="$UV_BIN"

if [[ "$UPDATE" == "1" && ! -x "$INSTALL_DIR/bin/python3" ]]; then
    echo "未安装，跳过: $INSTALL_DIR/bin/python3"
    exit 0
fi

tmp_env="$(mktemp)"
cat > "$tmp_env" << 'EOF'
# Python 环境配置
export PATH="$HOME/.local/python3.11/bin:$PATH"
EOF
write_file_if_changed "$ENV_DIR/python.sh" "$tmp_env"

if [[ -x "$INSTALL_DIR/bin/python3" ]]; then
    echo "Python 3.11 虚拟环境已存在: $($INSTALL_DIR/bin/python3 --version)"
    exit 0
fi

echo "创建 Python 3.11 虚拟环境: $INSTALL_DIR"

"$UV_CMD" python install 3.11
"$UV_CMD" venv --seed --python 3.11 "$INSTALL_DIR"

ln -sf "$INSTALL_DIR/bin/python3" "$BIN_DIR/python3"
if [[ -x "$INSTALL_DIR/bin/pip3" ]]; then
    ln -sf "$INSTALL_DIR/bin/pip3" "$BIN_DIR/pip3"
elif [[ -x "$INSTALL_DIR/bin/pip" ]]; then
    ln -sf "$INSTALL_DIR/bin/pip" "$BIN_DIR/pip3"
fi

echo ""
echo "Python 3.11 虚拟环境创建完成"
echo "  python: $($INSTALL_DIR/bin/python3 --version)"
if [[ -x "$INSTALL_DIR/bin/pip3" ]]; then
    echo "  pip: $($INSTALL_DIR/bin/pip3 --version | head -1)"
elif [[ -x "$INSTALL_DIR/bin/pip" ]]; then
    echo "  pip: $($INSTALL_DIR/bin/pip --version | head -1)"
fi
echo "  uv: $("$UV_CMD" --version)"
echo ""
echo "请运行 'source ~/.bashrc' 使环境变量生效"
