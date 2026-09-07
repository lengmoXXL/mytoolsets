#!/bin/bash
# 安装 opencode 配置（~/.config/opencode/opencode.json）
# provider 全部用官方注册表（models.dev），不做自定义 provider 配置；
# 密钥由 opencode-auth.sh 单独安装

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

CONFIG_FILE="${HOME}/.config/opencode/opencode.json"

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
        *)
            echo "未知参数: $1" >&2
            exit 1
            ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "opencode 配置" || exit 0
    remove_file "$CONFIG_FILE"
    exit 0
fi

if [[ "$UPDATE" == "1" && ! -d "$(dirname "$CONFIG_FILE")" ]]; then
    echo "未安装，跳过: $CONFIG_FILE"
    exit 0
fi

tmp_config="$(mktemp)"
cat > "$tmp_config" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
write_file_if_changed "$CONFIG_FILE" "$tmp_config"
