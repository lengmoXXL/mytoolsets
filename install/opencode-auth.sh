#!/bin/bash
# sync: skip
# 安装 opencode auth（API 密钥 → ~/.local/share/opencode/auth.json），密钥从 .secrets 解析
# 合并语义：只补充缺失的 provider 条目，不覆盖已有条目——auth.json 里的 OAuth
# 登录状态由 opencode 运行时维护，覆盖会丢掉已登录状态。需要更新时手动执行

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_FILE="${HOME}/.local/share/opencode/auth.json"
SECRETS_FILE="${SECRETS_DIR:-$SCRIPT_DIR/../.secrets}/ai-providers.json"

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

if ! command -v python3 &>/dev/null; then
    echo "错误: 缺少依赖 python3"
    exit 1
fi

if [[ "$REMOVE" == "1" ]]; then
    if [[ ! -f "$AUTH_FILE" ]]; then
        echo "未安装: $AUTH_FILE"
        exit 0
    fi
    confirm_remove "opencode auth.json 中本脚本管理的 provider 条目" || exit 0
    python3 - "$AUTH_FILE" <<'EOF'
import json
import os
import sys

auth_path = sys.argv[1]
# 与安装逻辑一致的 provider 条目（ai-providers.json key -> opencode provider id）
providers = {"zai": "zai-coding-plan", "deepseek": "deepseek", "kimi": "kimi-for-coding"}

with open(auth_path, encoding="utf-8") as fh:
    auth = json.load(fh)

found = [provider_id for provider_id in providers.values() if provider_id in auth]
if not found:
    print(f"未安装: {auth_path} 中没有本脚本管理的 provider 条目")
    sys.exit(0)

for provider_id in found:
    del auth[provider_id]

with open(auth_path, "w", encoding="utf-8") as fh:
    json.dump(auth, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
os.chmod(auth_path, 0o600)
print(f"已删除: {', '.join(found)}")
EOF
    exit 0
fi

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "错误: 缺少 ${SECRETS_FILE}，请先运行 tools/secrets.sh init 或 pull" >&2
    exit 1
fi

tmp_merged="$(mktemp)"
trap 'rm -f "$tmp_merged"' EXIT

# 退出码: 0 = 有补充（结果写入 tmp_merged），3 = 已是最新，其他 = 失败
merge_status=0
python3 - "$SECRETS_FILE" "$AUTH_FILE" "$tmp_merged" <<'EOF' || merge_status=$?
import json
import sys
from pathlib import Path

secrets_path, auth_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
# ai-providers.json key -> opencode 官方 provider id
providers = {"zai": "zai-coding-plan", "deepseek": "deepseek", "kimi": "kimi-for-coding"}

with open(secrets_path, encoding="utf-8") as fh:
    api_keys = json.load(fh)

auth = {}
if Path(auth_path).exists():
    with open(auth_path, encoding="utf-8") as fh:
        auth = json.load(fh)

additions = {}
for key_name, provider_id in providers.items():
    api_key = api_keys.get(key_name)
    if not isinstance(api_key, str) or not api_key:
        print(f"跳过 {provider_id}: ai-providers.json 缺少 key {key_name}", file=sys.stderr)
    elif provider_id not in auth:
        additions[provider_id] = {"type": "api", "key": api_key}

if not additions:
    print(f"已是最新: {auth_path}")
    sys.exit(3)

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump({**auth, **additions}, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
print(f"将补充: {', '.join(sorted(additions))}")
EOF

case "$merge_status" in
    0)
        ;;
    3)
        exit 0
        ;;
    *)
        echo "错误: auth.json 合并失败" >&2
        exit 1
        ;;
esac

if [[ "$UPDATE" == "1" ]] && ! confirm_update "opencode auth.json"; then
    echo "已取消"
    exit 0
fi

mkdir -p "$(dirname "$AUTH_FILE")"
mv "$tmp_merged" "$AUTH_FILE"
chmod 600 "$AUTH_FILE"
echo "installed: $AUTH_FILE"
