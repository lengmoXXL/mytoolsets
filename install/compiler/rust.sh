#!/bin/bash
# 安装隔离的 Rust 环境到 ~/.local/rust
# 可重入：已安装时跳过；--update 时 rustup 更新到最新 stable

set -e

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/rust"
BIN_DIR="${HOME}/.local/bin"
RUST_VERSION="1.96.0"

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

ENV_DIR="$HOME/.config/env.d"

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "Rust" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_file "$BIN_DIR/cargo"
    remove_file "$BIN_DIR/rustc"
    remove_file "$BIN_DIR/rustup"
    remove_file "$ENV_DIR/rust.sh"
    exit 0
fi

export RUSTUP_HOME="$INSTALL_DIR/rustup"
export CARGO_HOME="$INSTALL_DIR"

export RUSTUP_DIST_SERVER="https://mirrors.aliyun.com/rustup"
export RUSTUP_UPDATE_ROOT="https://mirrors.aliyun.com/rustup/rustup"

if [[ "$UPDATE" == "1" && ! -x "$INSTALL_DIR/bin/cargo" ]]; then
    echo "未安装，跳过: $INSTALL_DIR/bin/cargo"
    exit 0
fi

tmp_config="$(mktemp)"
cat > "$tmp_config" << 'EOF'
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"

[net]
git-fetch-with-cli = true
EOF
write_file_if_changed "$INSTALL_DIR/config.toml" "$tmp_config"

tmp_env="$(mktemp)"
cat > "$tmp_env" << 'EOF'
# Rust 环境配置
export RUSTUP_HOME="$HOME/.local/rust/rustup"
export CARGO_HOME="$HOME/.local/rust"
export RUSTUP_DIST_SERVER="https://mirrors.aliyun.com/rustup"
export RUSTUP_UPDATE_ROOT="https://mirrors.aliyun.com/rustup/rustup"
EOF
write_file_if_changed "$ENV_DIR/rust.sh" "$tmp_env"

if [[ -x "$INSTALL_DIR/bin/cargo" ]]; then
    installed_version="$("$INSTALL_DIR/bin/rustc" --version | awk '{print $2}')"
    if [[ "$UPDATE" != "1" ]]; then
        echo "Rust 已安装: $installed_version"
        exit 0
    fi
    if [[ "$installed_version" == "$RUST_VERSION" ]]; then
        echo "Rust 已是最新: $installed_version"
        exit 0
    fi
    confirm_update "rust: $installed_version -> $RUST_VERSION" || exit 0
    "$INSTALL_DIR/bin/rustup" toolchain install "$RUST_VERSION"
    "$INSTALL_DIR/bin/rustup" default "$RUST_VERSION"
    echo "Rust 已更新: $($INSTALL_DIR/bin/rustc --version)"
    exit 0
fi

echo "安装 Rust 到: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain "$RUST_VERSION"

ln -sf "$INSTALL_DIR/bin/cargo" "$BIN_DIR/cargo"
ln -sf "$INSTALL_DIR/bin/rustc" "$BIN_DIR/rustc"
ln -sf "$INSTALL_DIR/bin/rustup" "$BIN_DIR/rustup"

echo ""
echo "Rust 安装完成"
echo "  rustc: $($INSTALL_DIR/bin/rustc --version)"
echo "  cargo: $($INSTALL_DIR/bin/cargo --version)"
echo ""
echo "请运行 'source ~/.bashrc' 使环境变量生效"
