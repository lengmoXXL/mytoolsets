#!/bin/bash
# 安装/更新 DeepSeek Harness：CLI（npm 固定版本）+ 用户设置 + web profile 插件（npm 固定版本）
# 固定版本写在 DSH_VERSION / RW_VERSION / GIT_VERSION；升级前用 tools/latest-version.sh 查上游
# 插件都从 npm 装（发布包里带 lib/），不再下载 GitHub release，也不在本地构建

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CLI
BIN_DIR="${HOME}/.local/bin"
NPM_PREFIX="${HOME}/.local"
DSH_PACKAGE="@deepseek-ai/dsh"
DSH_VERSION="0.1.5-rc.2"
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
RW_VERSION="0.1.12"
GIT_PACKAGE="@lengmoxxl/dsh-git"
GIT_VERSION="0.2.1"

usage() {
    cat << EOF
用法: $0 [--registry URL] [--remove] [--update]

选项:
  --registry URL  使用指定 npm registry 安装 dsh CLI
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
        for plugin in "$RW_PACKAGE" "$GIT_PACKAGE" dsh-remote-workspace dsh-git; do
            "$DSH_BIN" plugin --profile "$PROFILE" remove "$plugin" || true
        done
    fi
    remove_file "$SETTINGS_FILE"
    # 插件没了，profile patch 里为它停用的默认 provider 要还回去（只删我们写的块）
    remove_managed_block "$PATCH_FILE" dsh-routers
    if [[ -f "$PATCH_FILE" ]] && grep -q 'id: subprocess$' "$PATCH_FILE"; then
        echo "提示: $PATCH_FILE 里仍有手写的停用行，插件已卸载，可能需要一并删掉"
    fi
    remove_dir "${HOME}/.local/share/dsh-plugins/tarballs"   # 旧版 release 下载缓存
    # 旧版按 clone + 本地构建安装的源码目录
    remove_dir "${HOME}/.local/share/dsh-plugins/dsh-git"
    remove_dir "${HOME}/.local/share/dsh-plugins/dsh-remote-workspace"
    rmdir "${HOME}/.local/share/dsh-plugins" 2>/dev/null || true
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
            const [major, minor, patch] = process.versions.node.split(".").map(Number);
            process.exit(major > 22 || (major === 22 && (minor > 19 || (minor === 19 && patch >= 0))) ? 0 : 1);
        ' &>/dev/null
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

plugin_version() {
    local name="$1"
    local manifest="$PROFILE_DIR/node_modules/$name/package.json"
    [[ -f "$manifest" ]] || return 0
    node -p "require('$manifest').version" 2>/dev/null || true
}

check_plugin_artifacts() {
    local name="$1"
    local dir="$PROFILE_DIR/node_modules/$name"
    for artifact in lib/index.js lib/client.js; do
        if [[ ! -f "$dir/$artifact" ]]; then
            echo "错误: 插件产物缺失 $dir/$artifact" >&2
            exit 1
        fi
    done
}

# remote-workspace 要接管 ctx.fs / subprocess / shell / tty，而 host plane 每项服务只允许一个实现：
# profile patch 层得停用默认 provider，否则插件会报 “this router is inert” 且不接管路由。
# 只补缺的那些（块外手写过的算已有），避免同一 id 在同一个 patch 层里出现两次。
ensure_router_disables() {
    [[ -f "$PROFILE_DIR/node_modules/$RW_PACKAGE/package.json" ]] || return 0

    # dsh 初始化 profile 时会写一个空数组占位 []：留着它再往后追加，文件就变成两个 YAML 文档
    # （end of the stream or a document separator is expected）。它本身不表达任何条目，删掉即可。
    if [[ -f "$PATCH_FILE" ]] && grep -q '^[[:space:]]*\[\][[:space:]]*$' "$PATCH_FILE"; then
        local placeholder_removed="$(mktemp)"
        grep -v '^[[:space:]]*\[\][[:space:]]*$' "$PATCH_FILE" > "$placeholder_removed"
        cat "$placeholder_removed" > "$PATCH_FILE"
        rm -f "$placeholder_removed"
        echo "已移除 $PATCH_FILE 里的空数组占位 []"
    fi

    local patch_outside block block_ids id
    patch_outside="$(mktemp)"
    if [[ -f "$PATCH_FILE" ]]; then
        awk -v begin="# BEGIN configs dsh-routers" -v end="# END configs dsh-routers" '
            $0 == begin { in_block = 1; next }
            $0 == end { in_block = 0; next }
            !in_block { print }
        ' "$PATCH_FILE" > "$patch_outside"
    fi

    block_ids=""
    for id in subprocess fs-sandbox bash-sandbox pwsh-sandbox; do
        grep -q "id: ${id}$" "$patch_outside" 2>/dev/null || block_ids="${block_ids} ${id}"
    done
    rm -f "$patch_outside"

    if [[ -z "$block_ids" ]]; then
        # 块外已经写全，managed block 就没必要留着
        remove_managed_block "$PATCH_FILE" dsh-routers
        return 0
    fi

    block="$(mktemp)"
    for id in $block_ids; do
        printf -- "- id: %s\n  disabled: true\n" "$id" >> "$block"
    done
    write_managed_block "$PATCH_FILE" dsh-routers "$block"
    rm -f "$block"
}

# 先补齐停用再动插件：插件已装好的机器上，任何后续步骤失败都不该让它停在“不接管路由”的状态
ensure_router_disables

# 旧版把 terminal 当独立包（仓库是 packages/ 多包布局）并在 profile 里 link 它；新版并回主包，
# 两边都会注册 /dsh-terminal/ws，同一条升级路由挂两次会让 boot 直接失败。清掉旧依赖与旧 clone 目录。
migrate_legacy_install() {
    local legacy dir stale

    if [[ -f "$MANIFEST" ]] && grep -q '"dsh-terminal"' "$MANIFEST"; then
        echo "旧布局的 dsh-terminal 已并入 dsh-remote-workspace，从 profile 移除…"
        "$DSH_BIN" plugin --profile "$PROFILE" remove dsh-terminal || true
    fi

    for legacy in dsh-git dsh-remote-workspace; do
        dir="${HOME}/.local/share/dsh-plugins/$legacy"
        [[ -d "$dir" ]] || continue
        # profile 还 link 着它就别动（开发时用 link: 指过来的情况）
        if [[ -f "$MANIFEST" ]] && grep -q "dsh-plugins/$legacy" "$MANIFEST"; then
            continue
        fi
        remove_dir "$dir"
    done

    # pnpm 卸载后会留下悬空的符号链接，清掉（还能解析到目标的不动）
    for stale in dsh-terminal dsh-tty dsh-tty-local dsh-tty-remote; do
        [[ -L "$PROFILE_DIR/node_modules/$stale" ]] || continue
        [[ -e "$PROFILE_DIR/node_modules/$stale" ]] && continue
        remove_file "$PROFILE_DIR/node_modules/$stale"
    done
}

migrate_legacy_install

add_plugin() {
    local package="$1" version="$2" allow_build="${3:-}"
    local args=(plugin --profile "$PROFILE" add --save-exact)
    [[ -n "$allow_build" ]] && args+=(--allow-build="$allow_build")
    [[ -n "$NPM_REGISTRY" ]] && args+=(--registry "$NPM_REGISTRY")
    "$DSH_BIN" "${args[@]}" "${package}@${version}"
}

# dep_spec <依赖键>: profile manifest 里该依赖的版本 spec
dep_spec() {
    [[ -n "$1" && -f "$MANIFEST" ]] || return 0
    node -p "require('$MANIFEST').dependencies?.['$1'] ?? ''" 2>/dev/null || true
}

# install_plugin <package> <version> [allow-build 包名] [旧依赖键]
# 旧依赖键指无 scope 的 dsh-git / dsh-remote-workspace：它们各自也进 bundles，
# 不先清掉就换 npm 包名，同一个 patch 会挂两次。
install_plugin() {
    local package="$1" version="$2" allow_build="${3:-}" legacy_key="${4:-}"
    local installed legacy_spec

    case "$(dep_spec "$package")" in
        link:* | file:*)
            echo "跳过: ${package}（profile 里是本地安装，开发用）"
            return 0
            ;;
    esac
    # 旧键指向 release 缓存 tarball 的是旧版安装，要迁移；指向别处的本地安装不动
    legacy_spec="$(dep_spec "$legacy_key")"
    case "$legacy_spec" in
        link:*)
            echo "跳过: ${package}（profile 里是本地安装，开发用）"
            return 0
            ;;
        file:*)
            if [[ "$legacy_spec" != "file:${HOME}/.local/share/dsh-plugins/tarballs/"* ]]; then
                echo "跳过: ${package}（profile 里是本地安装，开发用）"
                return 0
            fi
            ;;
    esac

    installed="$(plugin_version "$package")"
    if [[ -z "$installed" && -n "$legacy_key" ]]; then
        installed="$(plugin_version "$legacy_key")"
    fi

    if [[ -n "$legacy_spec" ]]; then
        echo "${package} 由旧依赖键 ${legacy_key}（${legacy_spec}）安装，改用 npm 包"
        if ! confirm_update "${package}: 迁移到 npm 包（当前 ${installed:-unknown}）"; then
            echo "跳过: ${package}"
            return 0
        fi
    elif [[ "$installed" == "$version" ]]; then
        echo "${package} ${version} 已安装"
        return 0
    elif [[ "$UPDATE" == "1" && -z "$installed" ]]; then
        echo "未安装，跳过: ${package}"
        return 0
    elif [[ -n "$installed" ]] &&
        ! confirm_update "${package}: ${installed} -> ${version}"; then
        echo "跳过: ${package}"
        return 0
    fi

    if [[ -n "$legacy_spec" ]]; then
        "$DSH_BIN" plugin --profile "$PROFILE" remove "$legacy_key" || true
    fi

    echo "安装 ${package} ${version}..."
    add_plugin "$package" "$version" "$allow_build"
    check_plugin_artifacts "$package"
    echo "${package} ${version} 安装完成"
}

echo ""
install_plugin "$RW_PACKAGE" "$RW_VERSION" node-pty dsh-remote-workspace
install_plugin "$GIT_PACKAGE" "$GIT_VERSION" "" dsh-git

echo ""
echo "dsh 安装完成。重启 Web 服务生效: dsh web"
echo "提示: provider 密钥引用由 install/dsh-auth.py 写入 $DSH_HOME_DIR/.credentials.yaml"
