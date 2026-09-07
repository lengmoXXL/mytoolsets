#!/usr/bin/env bash
set -eu
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

bin_dir="${HOME}/.local/bin"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_path="${script_dir}/../tools/style-check.sh"
target_path="${bin_dir}/style-check"

REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove) REMOVE=1 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "style-check" || exit 0
    remove_file "${target_path}"
    exit 0
fi

if [[ "${UPDATE:-}" == "1" ]]; then
    if [[ ! -e "${target_path}" ]]; then
        echo "未安装，跳过: ${target_path}"
        exit 0
    fi
    if cmp -s "${source_path}" "${target_path}"; then
        echo "已是最新: ${target_path}"
        exit 0
    fi
    confirm_update "style-check" || exit 0
fi

mkdir -p "${bin_dir}"
install -m 755 "${source_path}" "${target_path}"

echo "Installed style-check to ${target_path}"
echo "Run it with: style-check [prompt]"
