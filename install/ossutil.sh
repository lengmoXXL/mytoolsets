#!/bin/bash
# 安装 ossutil 到 ~/.local/bin
# https://www.alibabacloud.com/help/en/oss/developer-reference/ossutil-overview/

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

INSTALL_DIR="${HOME}/.local/ossutil"
BIN_DIR="${HOME}/.local/bin"
OSSUTIL_VERSION="${OSSUTIL_VERSION:-${1:-2.3.0}}"
OSSUTIL_BASE_URL="${OSSUTIL_BASE_URL:-https://gosspublic.alicdn.com/ossutil/v2}"
OSSUTIL_BIN="$BIN_DIR/ossutil"

usage() {
    cat <<EOF
Usage: $0 [version]

Installs ossutil to $OSSUTIL_BIN.
Only ossutil 2.3.0 has built-in SHA256 checksums in this script.

Environment:
  OSSUTIL_VERSION   Version to install. Default: 2.3.0
  OSSUTIL_BASE_URL  Download base URL. Default: $OSSUTIL_BASE_URL
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

for dep in curl unzip find install uname mktemp awk sed head; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

if command -v sha256sum &>/dev/null; then
    sha256_file() {
        sha256sum "$1" | awk '{print $1}'
    }
elif command -v shasum &>/dev/null; then
    sha256_file() {
        shasum -a 256 "$1" | awk '{print $1}'
    }
else
    echo "错误: 缺少依赖 sha256sum 或 shasum"
    exit 1
fi

os="$(uname -s)"
arch="$(uname -m)"

case "$os:$arch" in
    Linux:i386 | Linux:i686) package="ossutil-${OSSUTIL_VERSION}-linux-386.zip"; checksum="29cbd49b6c401c740c2f036cdf9d44ee8da340b16bdb3be71a33bcbebbe35ec5" ;;
    Linux:x86_64) package="ossutil-${OSSUTIL_VERSION}-linux-amd64.zip"; checksum="3ae4d9fc85a7a6e9f5654d1599766f1a3a42a3692870887b5ae9338d582ef65a" ;;
    Linux:armv7l | Linux:armv6l) package="ossutil-${OSSUTIL_VERSION}-linux-arm.zip"; checksum="8aff883c676961a11c89ac98b807fafa54fb424851d0557b1691b9d320324b9e" ;;
    Linux:aarch64 | Linux:arm64) package="ossutil-${OSSUTIL_VERSION}-linux-arm64.zip"; checksum="f6c95ba0c2d2ef30290af686ce4d706c701f4734ce8090bee4288a77e3f1d764" ;;
    Darwin:x86_64) package="ossutil-${OSSUTIL_VERSION}-mac-amd64.zip"; checksum="8437fdd3ef1a3eb12310f61fcf1c00a5bff5cdab47b4fea815527472e7cf896c" ;;
    Darwin:arm64 | Darwin:aarch64) package="ossutil-${OSSUTIL_VERSION}-mac-arm64.zip"; checksum="058fd048f321f8c80def8b748030531646eefe3a82837bf16b581ba7d9c84ac7" ;;
    *) echo "错误: 不支持的平台 ${os}/${arch}"; exit 1 ;;
esac

if [[ "$OSSUTIL_VERSION" != "2.3.0" ]]; then
    echo "错误: 当前脚本只内置 ossutil 2.3.0 的 SHA256 校验和"
    echo "如需安装其它版本，请更新脚本中的 checksum"
    exit 1
fi

existing_ossutil=""
if [[ -x "$OSSUTIL_BIN" ]]; then
    existing_ossutil="$OSSUTIL_BIN"
fi

if [[ "${UPDATE:-}" == "1" && -z "$existing_ossutil" ]]; then
    echo "未安装，跳过: ossutil"
    exit 0
fi

if [[ -n "$existing_ossutil" ]]; then
    existing_version="$("$existing_ossutil" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [[ "$existing_version" == "$OSSUTIL_VERSION" && "$existing_ossutil" == "$OSSUTIL_BIN" ]]; then
        echo "ossutil ${OSSUTIL_VERSION} 已安装: $OSSUTIL_BIN"
        "$OSSUTIL_BIN" version
        exit 0
    fi

    echo "检测到 ossutil: ${existing_version:-unknown} (${existing_ossutil})"
    echo "目标版本: ${OSSUTIL_VERSION}"
    confirm_update "ossutil: ${existing_version:-unknown} -> ${OSSUTIL_VERSION}" || exit 0
fi

tmp_dir="$(mktemp -d)"
zip_file="$tmp_dir/$package"
url="${OSSUTIL_BASE_URL%/}/${OSSUTIL_VERSION}/${package}"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "下载 ossutil ${OSSUTIL_VERSION}..."
curl -fL "$url" -o "$zip_file"

actual_checksum="$(sha256_file "$zip_file")"
if [[ "$actual_checksum" != "$checksum" ]]; then
    echo "错误: SHA256 校验失败"
    echo "  expected: $checksum"
    echo "  actual:   $actual_checksum"
    exit 1
fi

unzip -q "$zip_file" -d "$tmp_dir"

ossutil_source="$(find "$tmp_dir" -type f -name ossutil | head -1)"
if [[ -z "$ossutil_source" ]]; then
    echo "错误: 压缩包中没有找到 ossutil"
    exit 1
fi

mkdir -p "$INSTALL_DIR" "$BIN_DIR"
install -m 755 "$ossutil_source" "$INSTALL_DIR/ossutil"
ln -sf "$INSTALL_DIR/ossutil" "$OSSUTIL_BIN"

echo ""
echo "ossutil 安装完成"
echo "  binary: $OSSUTIL_BIN"
"$OSSUTIL_BIN" version
