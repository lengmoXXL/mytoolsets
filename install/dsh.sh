#!/bin/bash
# 安装/更新 DeepSeek Harness：CLI（npm 固定版本）+ 用户设置 + web profile 插件（npm 固定版本）
# 固定版本写在 DSH_VERSION / RW_VERSION / GIT_VERSION；升级前用 tools/latest-version.sh 查上游
# 插件都从 npm 装（发布包里带 lib/）

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CLI
BIN_DIR="${HOME}/.local/bin"
NPM_PREFIX="${HOME}/.local"
DSH_PACKAGE="@deepseek-ai/dsh"
DSH_VERSION="0.1.6-alpha.2"
DSH_BIN="${BIN_DIR}/dsh"
MIN_NODE_VERSION="22.19.0"
NPM_REGISTRY=""

# 用户设置
SETTINGS_SOURCE="$SCRIPT_DIR/../configs/dsh/settings.yaml"

# 插件
PROFILE="web"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE_DIR="$DSH_HOME_DIR/profiles/$PROFILE"
MANIFEST="$PROFILE_DIR/package.json"
PATCH_FILE="$PROFILE_DIR/cordis.patch.yml"
SETTINGS_FILE="$DSH_HOME_DIR/settings.yaml"
RW_PACKAGE="@lengmoxxl/dsh-remote-workspace"
RW_VERSION="0.1.14"
GIT_PACKAGE="@lengmoxxl/dsh-git"
GIT_VERSION="0.2.1"

usage() {
    cat << EOF
用法: $0 [--registry URL] [--remove] [--update]

选项:
  --registry URL  安装 dsh CLI 与插件时使用的 npm registry
  --remove        卸载 dsh（CLI、用户设置与插件）
  --update        更新已安装的部分（未安装则跳过）

环境变量:
  CN=1          使用 npmmirror registry
  DSH_HOME      dsh 数据目录，默认 ~/.dsh
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
    confirm_remove "dsh（CLI + 用户设置 + 插件）" || exit 0
    if [[ -x "$DSH_BIN" ]]; then
        for plugin in "$RW_PACKAGE" "$GIT_PACKAGE"; do
            "$DSH_BIN" plugin --profile "$PROFILE" remove "$plugin" || true
        done
    fi
    remove_file "$SETTINGS_FILE"
    # 插件没了，profile patch 里为它停用的行要还回去（只删我们写的块）
    for block_name in dsh-routers dsh-terminal; do
        remove_managed_block "$PATCH_FILE" "$block_name"
    done
    if [[ -f "$PATCH_FILE" ]] && grep -q 'id: subprocess$' "$PATCH_FILE"; then
        echo "提示: $PATCH_FILE 里仍有手写的停用行，插件已卸载，可能需要一并删掉"
    fi
    if command -v npm &>/dev/null; then
        npm uninstall -g --prefix "$NPM_PREFIX" "$DSH_PACKAGE"
    else
        remove_file "$DSH_BIN"
        remove_dir "$NPM_PREFIX/lib/node_modules/@deepseek-ai/dsh"
    fi
    exit 0
fi

if [[ "${CN:-}" == "1" && -z "$NPM_REGISTRY" ]]; then
    NPM_REGISTRY="https://registry.npmmirror.com"
fi

node_ready() {
    command -v node &>/dev/null &&
        command -v npm &>/dev/null &&
        node -e '
            const need = process.argv[1].split(".").map(Number);
            const have = process.versions.node.split(".").map(Number);
            process.exit(have[0] > need[0] ||
                (have[0] === need[0] && (have[1] > need[1] || (have[1] === need[1] && have[2] >= need[2]))) ? 0 : 1);
        ' "$MIN_NODE_VERSION" &>/dev/null
}

if ! node_ready; then
    echo "错误: dsh 需要 Node.js ${MIN_NODE_VERSION}+ 和 npm，请先运行 install/compiler/node.sh" >&2
    echo "当前 node: $(node --version 2>/dev/null || echo missing)" >&2
    echo "当前 npm: $(npm --version 2>/dev/null || echo missing)" >&2
    exit 1
fi

if ! command -v pnpm &>/dev/null; then
    echo "错误: 缺少 pnpm（dsh plugin 用它管理 profile 依赖），请先运行 $SCRIPT_DIR/pnpm.sh" >&2
    exit 1
fi

# ---- dsh CLI ----

local_version=""
if [[ -x "$DSH_BIN" ]]; then
    local_version="$("$DSH_BIN" --version 2>/dev/null | tr -d '[:space:]')"
fi

if [[ "$UPDATE" == "1" && -z "$local_version" ]]; then
    echo "未安装，跳过: dsh"
    exit 0
fi

if [[ "$local_version" == "$DSH_VERSION" ]]; then
    echo "dsh ${DSH_VERSION} 已安装: $DSH_BIN"
else
    if [[ -n "$local_version" ]]; then
        echo "当前 dsh: ${local_version} (${DSH_BIN})"
        echo "目标 dsh: ${DSH_VERSION}"
        confirm_update "dsh: ${local_version} -> ${DSH_VERSION}" || exit 0
    else
        echo "dsh 未安装，将安装目标版本 ${DSH_VERSION}"
    fi

    mkdir -p "$BIN_DIR"

    npm_args=(
        install -g
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
    npm_args+=("${DSH_PACKAGE}@${DSH_VERSION}")

    echo "安装 dsh ${DSH_VERSION}..."
    npm "${npm_args[@]}"

    echo "dsh 安装完成: $DSH_BIN"
    "$DSH_BIN" --version
fi

# ---- 用户设置 ----

if [[ ! -f "$SETTINGS_SOURCE" ]]; then
    echo "错误: 缺少 $SETTINGS_SOURCE" >&2
    exit 1
fi

if [[ "$UPDATE" == "1" && ! -f "$SETTINGS_FILE" ]]; then
    echo "未安装，跳过: $SETTINGS_FILE"
else
    tmp_settings="$(mktemp)"
    cp "$SETTINGS_SOURCE" "$tmp_settings"
    write_file_if_changed "$SETTINGS_FILE" "$tmp_settings"
    echo "提示: dsh 以本文件为准，它自己写的运行态字段（ui-onboarding 等）不会保留"
fi

# ---- 插件 ----

# 在 profile patch 层里停用若干行，写进一个受管块：
#   1) remote-workspace 要接管 ctx.fs / subprocess / shell / tty，而 host plane 每项服务只允许一个实现，
#      不停用默认 provider 时插件会报 “this router is inert” 且不接管路由；
#   2) dsh 0.1.6 起自带侧边栏终端，与插件自己的终端注册同一个右侧栏 tab kind，
#      两个都在时官方那个激活失败（UI 报 “Failed to load plugins”）。
# 只补块外缺失的 id（手写过的算已有），避免同一 id 在同一个 patch 层里出现两次。
ensure_patch_entries() {
    local block_name="$1"
    shift
    local begin="# BEGIN configs ${block_name}"
    local end="# END configs ${block_name}"
    local outside block_ids id entry_block

    outside="$(mktemp)"
    if [[ -f "$PATCH_FILE" ]]; then
        awk -v b="$begin" -v e="$end" '$0 == b { inb = 1; next } $0 == e { inb = 0; next } !inb { print }' \
            "$PATCH_FILE" > "$outside"
    fi

    block_ids=""
    for id in "$@"; do
        grep -q "id: ${id}$" "$outside" 2>/dev/null || block_ids="${block_ids} ${id}"
    done
    rm -f "$outside"

    if [[ -z "$block_ids" ]]; then
        # 块外已经写全，受管块就没必要留着
        remove_managed_block "$PATCH_FILE" "$block_name"
        return 0
    fi

    entry_block="$(mktemp)"
    for id in $block_ids; do
        printf -- "- id: %s\n  disabled: true\n" "$id" >> "$entry_block"
    done
    write_managed_block "$PATCH_FILE" "$block_name" "$entry_block"
    rm -f "$entry_block"
}

ensure_disabled_entries() {
    [[ -f "$PROFILE_DIR/node_modules/$RW_PACKAGE/package.json" ]] || return 0

    # dsh 初始化 profile 时会写一个空数组占位 []：留着它再往后追加，文件就变成两个 YAML 文档
    # （end of the stream or a document separator is expected）。它本身不表达任何条目，删掉即可。
    if [[ -f "$PATCH_FILE" ]] && grep -q '^[[:space:]]*\[\][[:space:]]*$' "$PATCH_FILE"; then
        local placeholder_removed="$(mktemp)"
        grep -v '^[[:space:]]*\[\][[:space:]]*$' "$PATCH_FILE" > "$placeholder_removed" || true
        cat "$placeholder_removed" > "$PATCH_FILE"
        rm -f "$placeholder_removed"
        echo "已移除 $PATCH_FILE 里的空数组占位 []"
    fi

    ensure_patch_entries dsh-routers subprocess fs-sandbox bash-sandbox pwsh-sandbox

    # 官方侧边栏终端只有 0.1.6+ 才有那一行；插件没装时不能停，否则这台机器就没有终端可用
    if [[ -f "$NPM_PREFIX/lib/node_modules/${DSH_PACKAGE}/node_modules/@deepseek-ai/dsh-client-ui-sidebar-terminal/package.json" ]]; then
        ensure_patch_entries dsh-terminal ui-sidebar-terminal
    fi
}

# 先补齐停用再动插件：插件已装好的机器上，任何后续步骤失败都不该让它停在“不接管路由”的状态
ensure_disabled_entries

# install_plugin <package> <version> [allow-build 包名]
install_plugin() {
    local package="$1" version="$2" allow_build="${3:-}"
    local spec installed args

    # profile 里是本地 link/file 安装（开发用）就让位，别用 npm 版覆盖
    spec="$(node -p "require('$MANIFEST').dependencies?.['$package'] ?? ''" 2>/dev/null || true)"
    case "$spec" in
        link:* | file:*)
            echo "跳过: ${package}（profile 里是本地安装，开发用）"
            return 0
            ;;
    esac

    installed="$(node -p "require('$PROFILE_DIR/node_modules/$package/package.json').version" 2>/dev/null || true)"
    if [[ "$installed" == "$version" ]]; then
        echo "${package} ${version} 已安装"
        return 0
    fi
    if [[ "$UPDATE" == "1" && -z "$installed" ]]; then
        echo "未安装，跳过: ${package}"
        return 0
    fi
    if [[ -n "$installed" ]] && ! confirm_update "${package}: ${installed} -> ${version}"; then
        echo "跳过: ${package}"
        return 0
    fi

    echo "安装 ${package} ${version}..."
    args=(plugin --profile "$PROFILE" add --save-exact)
    [[ -n "$allow_build" ]] && args+=(--allow-build="$allow_build")
    [[ -n "$NPM_REGISTRY" ]] && args+=(--registry "$NPM_REGISTRY")
    "$DSH_BIN" "${args[@]}" "${package}@${version}"

    for artifact in lib/index.js lib/client.js; do
        [[ -f "$PROFILE_DIR/node_modules/$package/$artifact" ]] || {
            echo "错误: 插件产物缺失 $PROFILE_DIR/node_modules/$package/$artifact" >&2
            exit 1
        }
    done
    echo "${package} ${version} 安装完成"
}

echo ""
install_plugin "$RW_PACKAGE" "$RW_VERSION" node-pty
install_plugin "$GIT_PACKAGE" "$GIT_VERSION"

# 全新安装时插件是上面几步才装上的，早先那次调用会因为“插件未装”直接返回，这里补一次
ensure_disabled_entries
echo ""
echo "dsh 安装完成。重启 Web 服务生效: dsh web"
echo "提示: provider 密钥引用由 install/dsh-auth.py 写入 $DSH_HOME_DIR/.credentials.yaml"
