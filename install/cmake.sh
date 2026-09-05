#!/bin/bash
# 安装 CMake 到 ~/.local/cmake，符号链接到 ~/.local/bin

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
CMAKE_VERSION="4.4.3"
CMAKE_DIR="${HOME}/.local/cmake"
GITHUB_RELEASE_PROXY="https://gh-proxy.com/"

usage() {
    cat << EOF
用法: $0

环境变量:
  CN=1     通过国内代理下载 GitHub Release 文件
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

mkdir -p "$BIN_DIR"

for dep in curl tar ln; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

existing_cmake=""
if [[ -x "$BIN_DIR/cmake" ]]; then
    existing_cmake="$BIN_DIR/cmake"
fi

if [[ "${UPDATE:-}" == "1" && -z "$existing_cmake" ]]; then
    echo "未安装，跳过: cmake"
    exit 0
fi

if [[ -n "$existing_cmake" ]]; then
    installed_version="$("$existing_cmake" --version | head -1 | awk '{print $3}')"
    if [[ "${UPDATE:-}" != "1" ]]; then
        echo "cmake 已安装: $existing_cmake ($installed_version)"
        exit 0
    fi
    if [[ "$installed_version" == "$CMAKE_VERSION" ]]; then
        echo "cmake 已是最新: $installed_version"
        exit 0
    fi
    echo "更新 cmake: $installed_version -> $CMAKE_VERSION"
    confirm_update "cmake: $installed_version -> $CMAKE_VERSION" || exit 0
fi

version="$CMAKE_VERSION"

os=$(uname -s)
arch=$(uname -m)
case "$os" in
    Darwin)
        # macOS 官方只发布 universal 包
        target="macos-universal"
        ;;
    Linux)
        case "$arch" in
            x86_64) target="linux-x86_64" ;;
            aarch64 | arm64) target="linux-aarch64" ;;
            *) echo "错误: 不支持的架构 $arch"; exit 1 ;;
        esac
        ;;
    *)
        echo "错误: 不支持的系统 $os"
        exit 1
        ;;
esac

tmp_dir=$(mktemp -d)
tarball="${tmp_dir}/cmake.tar.gz"
url="https://github.com/Kitware/CMake/releases/download/v${version}/cmake-${version}-${target}.tar.gz"
if [[ "${CN:-}" == "1" ]]; then
    url="${GITHUB_RELEASE_PROXY}${url}"
fi

echo "下载 CMake ${version}..."
curl -fL "$url" -o "$tarball"

rm -rf "$CMAKE_DIR"
mkdir -p "$CMAKE_DIR"
tar -xzf "$tarball" -C "$CMAKE_DIR" --strip-components=1
rm -rf "$tmp_dir"

# macOS 包是 CMake.app 结构，Linux 包是平铺 bin/
if [[ "$os" == "Darwin" ]]; then
    cmake_bin_dir="$CMAKE_DIR/CMake.app/Contents/bin"
else
    cmake_bin_dir="$CMAKE_DIR/bin"
fi
ln -sf "$cmake_bin_dir/cmake" "$BIN_DIR/cmake"
ln -sf "$cmake_bin_dir/ctest" "$BIN_DIR/ctest"
ln -sf "$cmake_bin_dir/cpack" "$BIN_DIR/cpack"

echo "cmake 安装完成: $BIN_DIR/cmake"
"$BIN_DIR/cmake" --version | head -1
