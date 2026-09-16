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
RW_VERSION="0.1.5"
GIT_REPO="lengmoXXL/dsh-git"
GIT_COMMIT="8a39c366dcdff3455c2c65d6fa3bc6a72538d733"
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
        # pnpm 默认拦 build script，allowBuilds 的键是 pnpm 打印的那个完整 spec
        "$DSH_BIN" plugin --profile "$PROFILE" add \
            "--allow-build=dsh-git@https://codeload.github.com/${GIT_REPO}/tar.gz/${GIT_COMMIT}" \
            "$git_spec"
        check_plugin_artifacts dsh-git
        echo "dsh-git ${GIT_COMMIT:0:12} 安装完成"
    fi
fi

# remote-workspace 要接管 ctx.fs / subprocess / shell / tty，而 host plane 每项服务只允许一个实现
missing_ids=""
for row in subprocess fs-sandbox bash-sandbox pwsh-sandbox; do
    grep -q "id: ${row}$" "$PATCH_FILE" 2>/dev/null || missing_ids="${missing_ids} ${row}"
done
if [[ -n "$missing_ids" ]]; then
    echo ""
    echo "注意: $PATCH_FILE 缺少停用行:${missing_ids}"
    echo "  缺了它们插件仍会加载，但不会接管路由（见 $RW_REPO 的 README）"
fi

echo ""
echo "dsh 安装完成。重启 Web 服务生效: dsh web"
echo "提示: provider 密钥引用由 install/dsh-auth.py 写入 $DSH_HOME_DIR/.credentials.yaml"
