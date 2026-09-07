#!/bin/bash
# Download a prebuilt perf_to_profile binary from OSS.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

BIN_DIR="${HOME}/.local/bin"
BINARY="${BIN_DIR}/perf_to_profile"
VERSION_FILE="${HOME}/.local/share/perf_to_profile/source-commit"
SOURCE_COMMIT="42b687e95926099f791847789cc52925ef385ddb"
PUBLIC_BASE_URL="${PERF_TO_PROFILE_BASE_URL:-https://lengmo-asserts.oss-cn-beijing.aliyuncs.com/tools/perf_to_profile/${SOURCE_COMMIT}}"

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  卸载 perf_to_profile
  --update  更新已安装的工具（未安装则跳过）

环境变量:
  PERF_TO_PROFILE_BASE_URL  预编译文件下载目录
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
    confirm_remove "perf_to_profile" || exit 0
    remove_file "$BINARY"
    remove_dir "$HOME/.local/share/perf_to_profile"
    exit 0
fi

if [[ "$UPDATE" == "1" && ! -x "$BINARY" ]]; then
    echo "未安装，跳过: $BINARY"
    exit 0
fi

if [[ -x "$BINARY" && -f "$VERSION_FILE" && "$(<"$VERSION_FILE")" == "$SOURCE_COMMIT" ]]; then
    echo "perf_to_profile 已安装: $BINARY"
    echo "  source commit: ${SOURCE_COMMIT:0:12}"
    exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "错误: perf_to_profile 仅支持 Linux"
    exit 1
fi

if [[ "$UPDATE" == "1" && -x "$BINARY" ]]; then
    confirm_update "perf_to_profile: $(<"$VERSION_FILE" 2>/dev/null || echo unknown) -> ${SOURCE_COMMIT:0:12}" || exit 0
fi

for dep in awk curl install mktemp sha256sum uname; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep"
        exit 1
    fi
done

case "$(uname -m)" in
    x86_64) asset="perf_to_profile-linux-amd64" ;;
    aarch64 | arm64) asset="perf_to_profile-linux-arm64" ;;
    *) echo "错误: 不支持的架构 $(uname -m)"; exit 1 ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

download="${tmp_dir}/${asset}"
checksum_file="${download}.sha256"

echo "下载 perf_to_profile ${SOURCE_COMMIT:0:12}..."
curl -fL --retry 3 "${PUBLIC_BASE_URL%/}/${asset}" -o "$download"
curl -fL --retry 3 "${PUBLIC_BASE_URL%/}/${asset}.sha256" -o "$checksum_file"

expected_checksum="$(awk 'NR == 1 { print $1 }' "$checksum_file")"
actual_checksum="$(sha256sum "$download" | awk '{ print $1 }')"
if [[ ! "$expected_checksum" =~ ^[0-9a-f]{64}$ || "$actual_checksum" != "$expected_checksum" ]]; then
    echo "错误: SHA256 校验失败"
    echo "  expected: $expected_checksum"
    echo "  actual:   $actual_checksum"
    exit 1
fi

mkdir -p "$BIN_DIR" "$(dirname "$VERSION_FILE")"
install -m 755 "$download" "$BINARY"
echo "$SOURCE_COMMIT" > "$VERSION_FILE"

echo ""
echo "perf_to_profile 安装完成"
echo "  binary: $BINARY"
echo "  source commit: ${SOURCE_COMMIT:0:12}"
