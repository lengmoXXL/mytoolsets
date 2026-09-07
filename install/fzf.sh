#!/bin/bash
# 安装 fzf 到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
FZF_VERSION="0.74.3"
ENV_DIR="${HOME}/.config/env.d"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 fzf 及其 env.d 配置
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
    confirm_remove "fzf" || exit 0
    remove_file "$BIN_DIR/fzf"
    remove_file "$ENV_DIR/fzf.sh"
    exit 0
fi

mkdir -p "$BIN_DIR"

for dep in curl tar install; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

fzf_bin=""
if [[ -x "$BIN_DIR/fzf" ]]; then
    fzf_bin="$BIN_DIR/fzf"
fi

download_needed=false
if [[ -z "$fzf_bin" ]]; then
    if [[ "$UPDATE" == "1" ]]; then
        echo "未安装，跳过: fzf"
        exit 0
    fi
    download_needed=true
else
    installed_version="$("$fzf_bin" --version | awk '{print $1}')"
    if [[ "$UPDATE" == "1" ]]; then
        if [[ "$installed_version" == "$FZF_VERSION" ]]; then
            echo "fzf 已是最新: $installed_version"
        else
            echo "更新 fzf: $installed_version -> $FZF_VERSION"
            confirm_update "fzf: $installed_version -> $FZF_VERSION" || exit 0
            download_needed=true
        fi
    else
        echo "fzf 已安装: $fzf_bin ($installed_version)"
    fi
fi

if [[ "$download_needed" == "true" ]]; then
    os=$(uname -s)
    arch=$(uname -m)
    case "${os}-${arch}" in
        Darwin-x86_64) target="darwin_amd64" ;;
        Darwin-arm64 | Darwin-aarch64) target="darwin_arm64" ;;
        Linux-x86_64) target="linux_amd64" ;;
        Linux-aarch64 | Linux-arm64) target="linux_arm64" ;;
        *) echo "错误: 不支持的平台 ${os}-${arch}"; exit 1 ;;
    esac

    url="https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${target}.tar.gz"
    if [[ "${CN:-}" == "1" ]]; then
        url="${GITHUB_RELEASE_PROXY}${url}"
    fi
    tmp_dir=$(mktemp -d)
    tarball="${tmp_dir}/fzf.tar.gz"

    echo "下载 fzf ${FZF_VERSION}..."
    curl -fL "$url" -o "$tarball"
    tar -xzf "$tarball" -C "$tmp_dir"
    install -m 755 "$tmp_dir/fzf" "$BIN_DIR/fzf"
    rm -rf "$tmp_dir"

    echo "fzf 安装完成: $BIN_DIR/fzf"
    "$BIN_DIR/fzf" --version
fi

tmp_env="$(mktemp)"
cat > "$tmp_env" << 'EOF'
# fzf key bindings
if command -v fzf &>/dev/null; then
    if [ -n "$ZSH_VERSION" ]; then
        eval "$(fzf --zsh)"
    else
        eval "$(fzf --bash)"
    fi
fi
EOF
write_file_if_changed "${ENV_DIR}/fzf.sh" "$tmp_env"
