#!/bin/bash
# 安装/更新 DeepSeek Harness：CLI（npm 固定版本）+ 用户设置 + web profile 插件
# 固定版本写在 DSH_VERSION / RW_VERSION / GIT_COMMIT；升级前用 tools/latest-version.sh 查上游
# 插件装法：remote-workspace 下载 release tarball（自带 lib/），dsh-git 用 github 依赖（靠 prepare 构建）

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
TARBALL_DIR="${HOME}/.local/share/dsh-plugins/tarballs"
RW_REPO="lengmoXXL/dsh-remote-workspace"
RW_VERSION="0.1.9"
GIT_REPO="lengmoXXL/dsh-git"
GIT_COMMIT="ef7c6aa232f5b6ebf32871b0ce9d44b6b519d528"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"
CURL_USER_AGENT="configs-install-dsh"

usage() {
    cat << EOF
用法: $0 [--registry URL] [--remove] [--update]

选项:
  --registry URL  使用指定 npm registry 安装 dsh CLI
  --remove        卸载 dsh（CLI、用户设置与插件）
  --update        更新已安装的部分（未安装则跳过）

环境变量:
  CN=1          使用 npmmirror registry，并经国内代理下载 GitHub release
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
        for plugin in dsh-remote-workspace dsh-git; do
            "$DSH_BIN" plugin --profile "$PROFILE" remove "$plugin" || true
        done
    fi
    remove_file "$SETTINGS_FILE"
    # 插件没了，profile patch 里为它停用的默认 provider 要还回去（只删我们写的块）
    remove_managed_block "$PATCH_FILE" dsh-routers
    if [[ -f "$PATCH_FILE" ]] && grep -q 'id: subprocess$' "$PATCH_FILE"; then
        echo "提示: $PATCH_FILE 里仍有手写的停用行，插件已卸载，可能需要一并删掉"
    fi
    remove_dir "$TARBALL_DIR"
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

for dep in pnpm curl git; do
    if ! command -v "$dep" &>/dev/null; then
        case "$dep" in
            pnpm) echo "错误: 缺少 pnpm（dsh plugin 用它管理 profile 依赖），请先运行 $SCRIPT_DIR/pnpm.sh" >&2 ;;
            *) echo "错误: 缺少依赖 $dep" >&2 ;;
        esac
        exit 1
    fi
done

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

rw_installed="$(plugin_version dsh-remote-workspace)"
echo ""
if [[ "$rw_installed" == "$RW_VERSION" ]]; then
    echo "dsh-remote-workspace ${RW_VERSION} 已安装"
elif [[ "$UPDATE" == "1" && -z "$rw_installed" ]]; then
    echo "未安装，跳过: dsh-remote-workspace"
else
    if [[ -n "$rw_installed" ]] &&
        ! confirm_update "dsh-remote-workspace: ${rw_installed} -> ${RW_VERSION}"; then
        echo "跳过: dsh-remote-workspace"
    else
        rw_url="https://github.com/${RW_REPO}/releases/download/plugin-v${RW_VERSION}/dsh-remote-workspace-${RW_VERSION}.tgz"
        if [[ "${CN:-}" == "1" ]]; then
            rw_url="${GITHUB_PROXY_PREFIX}${rw_url}"
        fi
        rw_tarball="$TARBALL_DIR/dsh-remote-workspace-${RW_VERSION}.tgz"

        mkdir -p "$TARBALL_DIR"
        echo "下载 dsh-remote-workspace ${RW_VERSION}..."
        curl -fL -H "User-Agent: ${CURL_USER_AGENT}" "$rw_url" -o "$rw_tarball"

        # 用本地 tgz：直接给 URL 会撞 pnpm 的 ERR_PNPM_MISSING_TARBALL_INTEGRITY
        "$DSH_BIN" plugin --profile "$PROFILE" add --allow-build=node-pty "$rw_tarball"
        check_plugin_artifacts dsh-remote-workspace
        echo "dsh-remote-workspace ${RW_VERSION} 安装完成"
    fi
fi

git_spec="github:${GIT_REPO}#${GIT_COMMIT}"
if [[ -f "$MANIFEST" ]] && grep -q "#${GIT_COMMIT}\"" "$MANIFEST"; then
    echo "dsh-git ${GIT_COMMIT:0:12} 已安装"
elif [[ "$UPDATE" == "1" && ! -f "$PROFILE_DIR/node_modules/dsh-git/package.json" ]]; then
    echo "未安装，跳过: dsh-git"
else
    if [[ -f "$PROFILE_DIR/node_modules/dsh-git/package.json" ]] &&
        ! confirm_update "dsh-git -> ${GIT_COMMIT:0:12}"; then
        echo "跳过: dsh-git"
    else
        # 仓库没发 release，也没有 lib/（gitignore），只能靠 prepare 构建；
        # pnpm 默认拦 build script：node-pty 用 --allow-build 放行，git 依赖的键是它解析出的完整
        # spec（https codeload 还是 git+ssh 取决于本机 git 配置），所以失败时放行那个键再重试
        add_log="$(mktemp)"
        add_rc=0
        "$DSH_BIN" plugin --profile "$PROFILE" add --allow-build=node-pty "$git_spec" >"$add_log" 2>&1 || add_rc=$?
        cat "$add_log"
        if [[ "$add_rc" != "0" ]]; then
            # pnpm 换用 TTY 时会输出带缩进的框式提示，先去掉 ANSI 再按任意缩进取那个键
            allow_key="$(sed $'s/\033\\[[0-9;]*[a-zA-Z]//g' "$add_log" \
                | sed -n 's/^[[:space:]]*\(dsh-git@.*\):[[:space:]]*true[[:space:]]*$/\1/p' | head -1)"
            if [[ -z "$allow_key" ]]; then
                # 解析不出就把它可能解析成的两种 spec 都放行：题头的 codeload 与 ssh 直连
                allow_key="dsh-git@https://codeload.github.com/${GIT_REPO}/tar.gz/${GIT_COMMIT}"
                fallback_key="dsh-git@git+ssh://git@github.com/${GIT_REPO}.git#${GIT_COMMIT}"
            else
                fallback_key=""
            fi

            for key in "$allow_key" "$fallback_key"; do
                [[ -n "$key" ]] || continue
                echo "为 pnpm 放行 git 依赖的 prepare 构建: $key"
                allow_build="$PROFILE_DIR/pnpm-workspace.yaml"
                grep -qF "$key" "$allow_build" 2>/dev/null && continue
                if [[ -f "$allow_build" ]] && grep -q '^allowBuilds:' "$allow_build"; then
                    awk -v key="$key" '{ print; if ($0 == "allowBuilds:") print "  " key ": true" }' \
                        "$allow_build" > "$allow_build.tmp"
                    mv "$allow_build.tmp" "$allow_build"
                else
                    printf '\nallowBuilds:\n  %s: true\n' "$key" >> "$allow_build"
                fi
            done
            rm -f "$add_log"
            "$DSH_BIN" plugin --profile "$PROFILE" add --allow-build=node-pty "$git_spec" || {
                echo "错误: dsh-git 仍未装成功；把下面这行加进 $PROFILE_DIR/pnpm-workspace.yaml 的 allowBuilds 后重跑：" >&2
                echo "  ${allow_key}: true" >&2
                exit 1
            }
        else
            rm -f "$add_log"
        fi
        check_plugin_artifacts dsh-git
        echo "dsh-git ${GIT_COMMIT:0:12} 安装完成"
    fi
fi

# remote-workspace 要接管 ctx.fs / subprocess / shell / tty，而 host plane 每项服务只允许一个实现：
# profile patch 层得停用默认 provider，否则插件会报 “this router is inert” 且不接管路由。
# 只补缺的那些（块外手写过的算已有），避免同一 id 在同一个 patch 层里出现两次。
if [[ -f "$PROFILE_DIR/node_modules/dsh-remote-workspace/package.json" ]]; then
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
    else
        block="$(mktemp)"
        for id in $block_ids; do
            printf -- "- id: %s\n  disabled: true\n" "$id" >> "$block"
        done
        write_managed_block "$PATCH_FILE" dsh-routers "$block"
        rm -f "$block"
    fi
fi

echo ""
echo "dsh 安装完成。重启 Web 服务生效: dsh web"
echo "提示: provider 密钥引用由 install/dsh-auth.py 写入 $DSH_HOME_DIR/.credentials.yaml"
