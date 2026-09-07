#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../tools" && pwd)/common.sh"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="$root/skills/code-report"
dest_root="${AGENTS_HOME:-$HOME/.agents}/skills"
dest="$dest_root/code-report"

REMOVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove) REMOVE=1 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ "$REMOVE" == "1" ]]; then
  confirm_remove "code-report skill" || exit 0
  remove_dir "$dest"
  exit 0
fi

if [[ ! -f "$src/SKILL.md" ]]; then
  echo "Missing skill source: $src" >&2
  exit 1
fi

if [[ "${UPDATE:-}" == "1" && ! -d "$dest" ]]; then
  echo "未安装，跳过: $dest"
  exit 0
fi

if ! command -v rsync >/dev/null; then
  echo "Error: rsync is required" >&2
  exit 1
fi

mkdir -p "$dest"
if [[ "${UPDATE:-}" == "1" ]]; then
    changes="$(rsync -nai --delete "$src/" "$dest/")"
    if [[ -z "$changes" ]]; then
        echo "已是最新: $dest"
        exit 0
    fi
    echo "$changes"
    confirm_update "code-report skill" || exit 0
fi
rsync -ai --delete "$src/" "$dest/"

echo "Installed code-report to $dest"
