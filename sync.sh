#!/bin/bash
# 遍历 install/ 下所有安装脚本，更新已安装的工具与配置
# 每个脚本 --update 下：未安装则跳过；已安装则对比版本/内容，按需更新

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# sync 自身忽略 SIGINT，Ctrl+C 只杀当前子脚本（子 shell 里恢复默认处理）
trap '' INT
run_script() {
    ( trap - INT; exec "$@" )
}

failed=()
for script in "$ROOT"/install/*.sh "$ROOT"/install/compiler/*.sh \
    "$ROOT"/install/lsp/*.sh "$ROOT"/install/skill/*.sh; do
    [[ -f "$script" ]] || continue
    echo ""
    echo "==> ${script#"$ROOT"/}"
    if grep -q '^# sync: skip$' "$script"; then
        echo "跳过（sync: skip）"
        continue
    fi
    if ! run_script "$script" --update; then
        failed+=("${script#"$ROOT"/}")
    fi
done

for script in "$ROOT"/install/*.py; do
    echo ""
    echo "==> ${script#"$ROOT"/}"
    if grep -q '^# sync: skip$' "$script"; then
        echo "跳过（sync: skip）"
        continue
    fi
    if ! run_script python3 "$script" --update; then
        failed+=("${script#"$ROOT"/}")
    fi
done

echo ""
if [[ ${#failed[@]} -gt 0 ]]; then
    echo "sync 完成，以下脚本失败:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
echo "sync 完成"
