#!/bin/bash

# 安装 lua-language-server 到 ~/.local/lua-language-server
# 可重入：已安装时跳过

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/lua-language-server"
BIN_DIR="${HOME}/.local/bin"
BINARY="$BIN_DIR/lua-language-server"
VERSION="3.19.1"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 lua-language-server
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
    confirm_remove "lua-language-server" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_file "$BINARY"
    exit 0
fi

if [[ "$UPDATE" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" ]]; then
    installed_version="$("$BINARY" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$UPDATE" != "1" ]]; then
        echo "lua-language-server 已安装 ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "$VERSION" ]]; then
        echo "lua-language-server 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 lua-language-server: ${installed_version:-unknown} -> $VERSION"
    confirm_update "lua-language-server: ${installed_version:-unknown} -> $VERSION" || exit 0
fi

echo "安装 lua-language-server $VERSION"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux | darwin) ;;
    *) echo "不支持的操作系统: $OS"; exit 1 ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="x64" ;;
    arm64 | aarch64) ARCH="arm64" ;;
    *)       echo "不支持的架构: $ARCH"; exit 1 ;;
esac
mkdir -p "$BIN_DIR"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"

TARBALL="lua-language-server-$VERSION-$OS-$ARCH.tar.gz"
DOWNLOAD_URL="https://github.com/LuaLS/lua-language-server/releases/download/$VERSION/$TARBALL"
if [[ "${CN:-}" == "1" ]]; then
    DOWNLOAD_URL="${GITHUB_RELEASE_PROXY}${DOWNLOAD_URL}"
fi
curl -fL "$DOWNLOAD_URL" -o "$TARBALL"

mkdir -p "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$INSTALL_DIR"
# 不能用符号链接：macOS 上二进制按 argv[0] 定位 main.lua，经链接调用会找错目录
cat > "$BINARY" << EOF
#!/bin/sh
exec "$INSTALL_DIR/bin/lua-language-server" "\$@"
EOF
chmod +x "$BINARY"

echo ""
echo "lua-language-server 安装完成: $BINARY"
