#!/bin/bash
# 从源码编译安装 tmux 到 ~/.local
# 可重入：已安装目标版本时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
SRC_ROOT="${INSTALL_DIR}/src"
TMUX_BIN="${BIN_DIR}/tmux"
VERSION="3.7c"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 tmux 及编译源码目录
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
    confirm_remove "tmux" || exit 0
    remove_file "$TMUX_BIN"
    remove_file "$INSTALL_DIR/share/man/man1/tmux.1"
    remove_dir "$SRC_ROOT/tmux-$VERSION"
    exit 0
fi

run_with_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_build_deps() {
    echo "安装 tmux 编译依赖..."

    if command -v apt-get &>/dev/null; then
        run_with_sudo apt-get update
        run_with_sudo apt-get install -y \
            ca-certificates curl gcc make pkg-config tar \
            libevent-dev libncurses-dev bison
    elif command -v dnf &>/dev/null; then
        run_with_sudo dnf install -y \
            ca-certificates curl gcc make pkgconf-pkg-config tar \
            libevent-devel ncurses-devel bison
    elif command -v yum &>/dev/null; then
        run_with_sudo yum install -y \
            ca-certificates curl gcc make pkgconfig tar \
            libevent-devel ncurses-devel bison
    elif command -v pacman &>/dev/null; then
        run_with_sudo pacman -Sy --noconfirm \
            ca-certificates curl base-devel pkgconf tar \
            libevent ncurses bison
    elif command -v apk &>/dev/null; then
        run_with_sudo apk add \
            ca-certificates curl build-base pkgconf tar \
            libevent-dev ncurses-dev bison
    elif command -v zypper &>/dev/null; then
        run_with_sudo zypper install -y \
            ca-certificates curl gcc make pkg-config tar \
            libevent-devel ncurses-devel bison
    elif command -v brew &>/dev/null; then
        brew install pkg-config libevent ncurses bison
    else
        echo "错误: 未找到支持的包管理器，无法自动安装编译依赖"
        exit 1
    fi
}

build_deps_ready() {
    for dep in curl gcc make pkg-config tar bison; do
        if ! command -v "$dep" &>/dev/null; then
            return 1
        fi
    done

    pkg-config --exists libevent ncurses
}

make_jobs() {
    if command -v nproc &>/dev/null; then
        nproc
    else
        getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2
    fi
}

if [[ "$UPDATE" == "1" && ! -x "$TMUX_BIN" ]]; then
    echo "未安装，跳过: $TMUX_BIN"
    exit 0
fi

if [[ -x "$TMUX_BIN" ]]; then
    INSTALLED_VERSION="$("$TMUX_BIN" -V | awk '{print $2}')"
    if [[ "$INSTALLED_VERSION" == "$VERSION" ]]; then
        echo "tmux ${VERSION} 已安装: $TMUX_BIN"
        exit 0
    fi

    echo "检测到已安装 tmux: ${INSTALLED_VERSION:-unknown}"
    echo "目标版本: $VERSION"
    confirm_update "tmux: ${INSTALLED_VERSION:-unknown} -> $VERSION" || exit 0
fi

if build_deps_ready; then
    echo "tmux 编译依赖已满足"
else
    install_build_deps
fi

DOWNLOAD_URL="https://github.com/tmux/tmux/releases/download/${VERSION}/tmux-${VERSION}.tar.gz"
if [[ "${CN:-}" == "1" ]]; then
    DOWNLOAD_URL="${GITHUB_RELEASE_PROXY}${DOWNLOAD_URL}"
fi
SRC_DIR="${SRC_ROOT}/tmux-${VERSION}"
TMP_DIR="$(mktemp -d)"
TARBALL="${TMP_DIR}/tmux.tar.gz"

trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$BIN_DIR" "$SRC_ROOT"

echo "下载 tmux ${VERSION}..."
curl -fL "$DOWNLOAD_URL" -o "$TARBALL"

echo "解压源码到: $SRC_DIR"
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
tar -xzf "$TARBALL" -C "$SRC_DIR" --strip-components=1

cd "$SRC_DIR"

echo "配置编译参数..."
./configure --prefix="$INSTALL_DIR"

echo "编译中..."
make -j"$(make_jobs)"

echo "安装到: $INSTALL_DIR"
make install

echo ""
echo "tmux 安装完成: $TMUX_BIN"
"$TMUX_BIN" -V
echo "确保 $BIN_DIR 在 PATH 中"
