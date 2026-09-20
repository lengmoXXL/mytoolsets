#!/bin/bash
# 安装/更新 Pi：CLI（npm 固定版本）+ 用户配置与自研 extensions
# 固定版本写在 PI_VERSION；升级前用 tools/latest-version.sh pi-agent 查上游
# 单文件配置用 write_file_if_changed；themes/agents/extensions 用 rsync 镜像

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CLI
BIN_DIR="${HOME}/.local/bin"
NPM_PREFIX="${HOME}/.local"
PI_PACKAGE="@earendil-works/pi-coding-agent"
PI_VERSION="0.86.0"
PI_BIN="${BIN_DIR}/pi"
MIN_NODE_VERSION="22.19.0"
NPM_REGISTRY=""

# 配置
CONFIG_SOURCE="$SCRIPT_DIR/../configs/pi"
CONFIG_TARGET="$HOME/.pi/agent"
CONFIG_FILES="models.json settings.json pi-plan-mode.json zentui.json"

usage() {
    cat << EOF
用法: $0 [--registry URL] [--remove] [--update]

选项:
  --registry URL  使用指定 npm registry 安装 Pi CLI
  --remove        卸载 Pi（CLI、配置与自研 extensions）
  --update        更新已安装的部分（未安装则跳过）

环境变量:
  CN=1     使用 npmmirror npm registry
EOF
}

UPDATE=0
REMOVE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry)
            if [[ $# -lt 2 ]]; then
                usage
                exit 1
            fi
            NPM_REGISTRY="$2"
            shift
            ;;
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
    confirm_remove "pi（CLI + 配置与 extensions）" || exit 0
    if command -v npm &>/dev/null; then
        npm uninstall -g --prefix "$NPM_PREFIX" "$PI_PACKAGE"
    else
        remove_file "$PI_BIN"
        remove_dir "$NPM_PREFIX/lib/node_modules/@earendil-works/pi-coding-agent"
    fi
    for name in $CONFIG_FILES; do
        remove_file "$CONFIG_TARGET/$name"
    done
    remove_dir "$CONFIG_TARGET/themes"
    remove_dir "$CONFIG_TARGET/agents"
    # 只删镜像安装的自研 *.ts，不动目录里 pi 包管理的其他文件
    for ext in "$CONFIG_SOURCE/extensions/"*.ts; do
        [[ -e "$ext" ]] || continue
        remove_file "$CONFIG_TARGET/extensions/$(basename "$ext")"
    done
    exit 0
fi

if [[ "${CN:-}" == "1" && -z "$NPM_REGISTRY" ]]; then
    NPM_REGISTRY="https://registry.npmmirror.com"
fi

node_ready() {
    command -v node &>/dev/null &&
        command -v npm &>/dev/null &&
        node -e '
            const [major, minor, patch] = process.versions.node.split(".").map(Number);
            process.exit(major > 22 || (major === 22 && (minor > 19 || (minor === 19 && patch >= 0))) ? 0 : 1);
        ' &>/dev/null
}

if ! node_ready; then
    echo "错误: Pi 需要 Node.js ${MIN_NODE_VERSION}+ 和 npm，请先运行 $SCRIPT_DIR/compiler/node.sh" >&2
    echo "当前 node: $(node --version 2>/dev/null || echo missing)" >&2
    echo "当前 npm: $(npm --version 2>/dev/null || echo missing)" >&2
    exit 1
fi

for dep in grep head rsync; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep" >&2
        exit 1
    fi
done

# ---- Pi CLI ----

local_pi=""
if [[ -x "$PI_BIN" ]]; then
    local_pi="$PI_BIN"
fi

local_version=""
if [[ -n "$local_pi" ]]; then
    local_version=$("$local_pi" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

if [[ "$UPDATE" == "1" && -z "$local_pi" ]]; then
    echo "未安装，跳过: pi"
    exit 0
fi

if [[ -n "$local_pi" && "$local_version" == "$PI_VERSION" ]]; then
    echo "Pi ${PI_VERSION} 已安装: $local_pi"
else
    if [[ -n "$local_pi" ]]; then
        echo "当前 Pi: ${local_version:-unknown} (${local_pi})"
        echo "目标 Pi: ${PI_VERSION}"
        confirm_update "pi: ${local_version:-unknown} -> ${PI_VERSION}" || exit 0
    else
        echo "Pi 未安装，将安装目标版本 ${PI_VERSION}"
    fi

    mkdir -p "$BIN_DIR"

    npm_args=(
        install -g
        --ignore-scripts
        --min-release-age=0
        --prefix "$NPM_PREFIX"
        --no-fund
        --no-audit
        --loglevel=error
        --progress=false
    )
    if [[ -n "$NPM_REGISTRY" ]]; then
        npm_args+=(--registry "$NPM_REGISTRY")
    fi
    npm_args+=("${PI_PACKAGE}@${PI_VERSION}")

    echo "安装 Pi ${PI_VERSION}..."
    npm "${npm_args[@]}"

    echo "Pi 安装完成: $PI_BIN"
    "$PI_BIN" --version
fi

# ---- 用户配置与 extensions ----

if [[ "$UPDATE" == "1" && ! -d "$CONFIG_TARGET" ]]; then
    echo "未安装，跳过: $CONFIG_TARGET"
    exit 0
fi

mkdir -p "$CONFIG_TARGET"

for name in $CONFIG_FILES; do
    tmp_config="$(mktemp)"
    cp "$CONFIG_SOURCE/$name" "$tmp_config"
    write_file_if_changed "$CONFIG_TARGET/$name" "$tmp_config"
done

sync_dir() {
    local src="$1" dest="$2" desc="$3" changes
    changes="$(rsync -nai --delete "$src/" "$dest/" 2>/dev/null)"
    if [[ -z "$changes" ]]; then
        echo "$dest 未变化"
        return
    fi
    if [[ "$UPDATE" == "1" ]] && ! confirm_update "$desc"; then
        return
    fi
    mkdir -p "$dest"
    rsync -ai --delete "$src/" "$dest/"
    echo "$dest 已更新"
}

sync_dir "$CONFIG_SOURCE/themes" "$CONFIG_TARGET/themes" "pi themes"
sync_dir "$CONFIG_SOURCE/agents" "$CONFIG_TARGET/agents" "pi agents"

# 只镜像自研 *.ts（node_modules、tsconfig 等编辑器辅助文件不装）；
# 目标目录里 pi 包管理的文件（subagent/ 等）被 exclude 保护，不会被 --delete 删除
ext_changes="$(rsync -nai --delete --include='*.ts' --exclude='*' "$CONFIG_SOURCE/extensions/" "$CONFIG_TARGET/extensions/")"
if [[ -n "$ext_changes" ]]; then
    echo "$ext_changes"
    if [[ "$UPDATE" != "1" ]] || confirm_update "pi extensions"; then
        rsync -ai --delete --include='*.ts' --exclude='*' "$CONFIG_SOURCE/extensions/" "$CONFIG_TARGET/extensions/"
        echo "pi extensions 已更新: $CONFIG_TARGET/extensions"
    fi
else
    echo "$CONFIG_TARGET/extensions 未变化"
fi

echo ""
echo "Pi 安装完成。凭据由 install/pi-auth.py 写入 ~/.pi/agent/auth.json"
