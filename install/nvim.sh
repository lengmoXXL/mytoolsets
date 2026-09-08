#!/bin/bash
# 安装固定版本的 Neovim；升级时先用 tools/latest-version.sh 查询最新 tag，再改 VERSION
#   macOS: 官方预编译包（无需 cmake/gettext）
#   Linux: 源码编译

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
NVIM_BIN="${BIN_DIR}/nvim"
VERSION="v0.12.5"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 Neovim 及其 env.d 配置
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  CN=1     通过国内代理下载 GitHub Release 文件
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
    confirm_remove "Neovim" || exit 0
    remove_file "$NVIM_BIN"
    remove_file "$INSTALL_DIR/share/man/man1/nvim.1"
    remove_dir "$INSTALL_DIR/lib/nvim"
    remove_dir "$INSTALL_DIR/share/nvim"
    remove_managed_block "$HOME/.config/env.d/alias.sh" nvim-alias
    exit 0
fi

require_deps() {
    for dep in "$@"; do
        if ! command -v "$dep" &>/dev/null; then
            echo "错误: 缺少依赖 $dep"
            exit 1
        fi
    done
}

TMP_DIR=""
cleanup() {
    if [[ -n "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

exit_if_same_version_or_confirm_upgrade() {
    if [[ ! -x "$NVIM_BIN" ]]; then
        if [[ "$UPDATE" == "1" ]]; then
            echo "未安装，跳过: $NVIM_BIN"
            exit 0
        fi
        return 0
    fi

    local installed_version
    installed_version="$("$NVIM_BIN" --version | head -1 | awk '{print $2}')"

    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "Neovim ${VERSION} 已安装: $NVIM_BIN"
        exit 0
    fi

    echo "检测到已安装 Neovim: ${installed_version:-unknown}"
    echo "目标版本: ${VERSION}"

    confirm_update "nvim: ${installed_version:-unknown} -> ${VERSION}" || exit 0
}

# 下载并解压到临时目录，输出解压后的根目录路径
download_release() {
    local url="$1"
    if [[ "${CN:-}" == "1" ]]; then
        url="${GITHUB_RELEASE_PROXY}${url}"
    fi

    TMP_DIR="$(mktemp -d)"
    local tarball="${TMP_DIR}/neovim.tar.gz"

    echo "下载 Neovim ${VERSION}..." >&2
    curl -fL "$url" -o "$tarball"
    tar -xzf "$tarball" -C "$TMP_DIR"

    find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1
}

install_macos() {
    local url="https://github.com/neovim/neovim/releases/download/${VERSION}/nvim-macos-$(uname -m).tar.gz"
    local nvim_root
    nvim_root="$(download_release "$url")"

    if [[ ! -x "$nvim_root/bin/nvim" ]]; then
        echo "错误: 发布包中没有找到 nvim 可执行文件"
        exit 1
    fi

    echo "安装中..."
    mkdir -p "$INSTALL_DIR"
    cp -R "$nvim_root/"* "$INSTALL_DIR/"
}

install_linux() {
    require_deps cmake gettext make nproc

    local url="https://github.com/neovim/neovim/archive/refs/tags/${VERSION}.tar.gz"
    local nvim_root
    nvim_root="$(download_release "$url")"

    if [[ ! -f "$nvim_root/Makefile" ]]; then
        echo "错误: Neovim 源码包中没有找到 Makefile"
        exit 1
    fi

    echo "编译中..."
    make -C "$nvim_root" \
        CMAKE_BUILD_TYPE=Release \
        CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}" \
        -j"$(nproc)"

    echo "安装中..."
    make -C "$nvim_root" install
}

setup_alias() {
    if [[ "$UPDATE" == "1" && ! -x "$NVIM_BIN" ]]; then
        return 0
    fi

    local env_dir="${HOME}/.config/env.d"
    local alias_file="${env_dir}/alias.sh"

    mkdir -p "$env_dir"

    # 旧版无 guard 的写法直接删除，改用 managed block
    if ! grep -qF '# BEGIN configs nvim-alias' "$alias_file" 2>/dev/null \
        && grep -q '^alias v=' "$alias_file" 2>/dev/null; then
        local tmp_alias
        tmp_alias="$(mktemp)"
        sed '/^alias v=/d' "$alias_file" > "$tmp_alias"
        mv "$tmp_alias" "$alias_file"
    fi

    local block
    block="$(mktemp)"
    echo 'alias v="nvim"' > "$block"
    write_managed_block "$alias_file" nvim-alias "$block"
    rm -f "$block"

    echo ""
    echo "已配置 alias v='nvim' 在 $alias_file"
}

require_deps awk curl find head mktemp sed tar
setup_alias
exit_if_same_version_or_confirm_upgrade

case "$(uname -s)" in
    Darwin) install_macos ;;
    *) install_linux ;;
esac

echo ""
echo "Neovim ${VERSION} 安装完成"
echo "  binary: $NVIM_BIN"
echo "  clipboard: OSC 52 (终端协议，无需额外工具)"
"$NVIM_BIN" --version | head -1
