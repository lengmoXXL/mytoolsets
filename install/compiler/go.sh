#!/bin/bash
# 安装 Go 到 ~/.local/go
# 可重入：已安装时跳过；--update 时对比固定版本按需更新

set -e

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/go"
BIN_DIR="${HOME}/.local/bin"
GO_VERSION="1.27.1"
GOPLS_VERSION="v0.23.0"

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

if [[ "$UPDATE" == "1" && ! -x "$INSTALL_DIR/bin/go" ]]; then
    echo "未安装，跳过: $INSTALL_DIR/bin/go"
    exit 0
fi

ENV_DIR="$HOME/.config/env.d"

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "Go" || exit 0
    remove_dir "$INSTALL_DIR"
    remove_dir "$HOME/.local/go-packages"
    remove_file "$BIN_DIR/go"
    remove_file "$BIN_DIR/gofmt"
    remove_file "$BIN_DIR/gopls"
    remove_file "$ENV_DIR/go.sh"
    exit 0
fi

tmp_env="$(mktemp)"
cat > "$tmp_env" << 'EOF'
# Go 环境配置
export GOPATH="$HOME/.local/go-packages"
export GOPROXY="https://goproxy.cn,direct"
EOF
write_file_if_changed "$ENV_DIR/go.sh" "$tmp_env"

should_install=false
if [[ ! -x "$INSTALL_DIR/bin/go" ]]; then
    should_install=true
elif [[ "$UPDATE" != "1" ]]; then
    echo "Go 已安装: $($INSTALL_DIR/bin/go version)"
else
    installed_version="$("$INSTALL_DIR/bin/go" version | awk '{print $3}' | sed 's/go//')"
    if [[ "$installed_version" == "$GO_VERSION" ]]; then
        echo "Go 已是最新: $installed_version"
    else
        confirm_update "go: $installed_version -> $GO_VERSION" || exit 0
        should_install=true
    fi
fi

if [[ "$should_install" == "true" ]]; then
    echo "安装 Go $GO_VERSION 到: $INSTALL_DIR"

    OS=$(uname -s)
    case "$OS" in
        Linux) OS="linux" ;;
        Darwin) OS="darwin" ;;
        *)
            echo "错误：不支持的系统: $OS"
            exit 1
            ;;
    esac

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac

    # 下载地址（使用 golang.google.cn 镜像）
    DOWNLOAD_URL="https://golang.google.cn/dl/go${GO_VERSION}.${OS}-${ARCH}.tar.gz"

    mkdir -p "$BIN_DIR"

    echo "下载中..."
    curl -fL "$DOWNLOAD_URL" -o /tmp/go.tar.gz

    echo "解压中..."
    tar -xzf /tmp/go.tar.gz -C "${HOME}/.local"
    rm /tmp/go.tar.gz

    ln -sf "$INSTALL_DIR/bin/go" "$BIN_DIR/go"
    ln -sf "$INSTALL_DIR/bin/gofmt" "$BIN_DIR/gofmt"
fi

if [[ -x "$BIN_DIR/gopls" ]]; then
    installed_gopls="$("$BIN_DIR/gopls" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$installed_gopls" == "$GOPLS_VERSION" ]]; then
        echo "gopls 已是最新: $installed_gopls"
        exit 0
    fi
    if [[ "$UPDATE" == "1" ]]; then
        confirm_update "gopls: ${installed_gopls:-unknown} -> $GOPLS_VERSION" || exit 0
    fi
fi

echo "安装 gopls $GOPLS_VERSION..."
GOPATH="$HOME/.local/go-packages" GOPROXY="https://goproxy.cn,direct" \
    "$INSTALL_DIR/bin/go" install "golang.org/x/tools/gopls@$GOPLS_VERSION"

GOPATH="$HOME/.local/go-packages" \
    ln -sf "$HOME/.local/go-packages/bin/gopls" "$BIN_DIR/gopls"

echo ""
echo "Go 安装完成"
echo "  go: $($INSTALL_DIR/bin/go version)"
echo "  gopls: $($BIN_DIR/gopls version 2>/dev/null | head -1)"
echo "  GOPATH: ~/.local/go-packages"
echo "  GOPROXY: https://goproxy.cn,direct"
echo ""
echo "请运行 'source ~/.bashrc' 使环境变量生效"
