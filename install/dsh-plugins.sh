#!/bin/bash
# 安装/更新 dsh 插件到 web profile：dsh-git、dsh-remote-workspace、dsh-terminal
# 源码固定在 ~/.local/share/dsh-plugins/<repo>，按 PINNED_COMMIT 拉取后本地构建再 link 进 profile
# （插件没有 prepare 脚本，不能直接 pnpm add git 依赖；remote-workspace 的 terminal 插件是仓库里的独立包）

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

PROFILE="web"
PLUGIN_ROOT="${HOME}/.local/share/dsh-plugins"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE_MANIFEST="$DSH_HOME_DIR/profiles/$PROFILE/package.json"
VERSIONS_DIR="$HOME/.local/share/configs-setup/versions"
GITHUB_PROXY_PREFIX="https://gh-proxy.com/"
NPM_REGISTRY=""

# repo|url|commit|链接进 profile 的包（<包目录>:<包名>，逗号分隔；包目录相对仓库根）
PLUGINS=(
    "dsh-git|https://github.com/lengmoXXL/dsh-git.git|8a39c366dcdff3455c2c65d6fa3bc6a72538d733|.:dsh-git"
    "dsh-remote-workspace|https://github.com/lengmoXXL/dsh-remote-workspace.git|0c98af132538414e99512d57a378a75d92fe543f|packages/remote-workspace:dsh-remote-workspace,packages/terminal:dsh-terminal"
)

usage() {
    cat << EOF
用法: $0 [--remove] [--update]

选项:
  --remove  从 profile 卸载这些插件，并删除源码目录
  --update  更新已安装的插件（未安装则跳过）

环境变量:
  CN=1          使用 npmmirror registry，并通过国内代理 clone GitHub
  DSH_HOME      dsh 数据目录，默认 ~/.dsh
EOF
}

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

in_profile() {
    grep -q "\"$1\"" "$PROFILE_MANIFEST" 2>/dev/null
}

# profile 里记的是 link:<绝对路径>，指向别处（例如开发用的 clone）也算未装到位
plugin_linked() {
    grep -q "\"link:$1\"" "$PROFILE_MANIFEST" 2>/dev/null
}

if [[ "$REMOVE" == "1" ]]; then
    confirm_remove "dsh 插件 (dsh-git, dsh-remote-workspace, dsh-terminal)" || exit 0
    for spec in "${PLUGINS[@]}"; do
        IFS='|' read -r name _repo _commit links <<< "$spec"
        if command -v dsh &>/dev/null; then
            for link in ${links//,/ }; do
                package_name="${link##*:}"
                if in_profile "$package_name"; then
                    dsh plugin --profile "$PROFILE" remove "$package_name" || true
                fi
            done
        fi
        remove_dir "$PLUGIN_ROOT/$name"
        remove_file "$VERSIONS_DIR/$name"
    done
    exit 0
fi

for dep in git npm dsh pnpm; do
    if ! command -v "$dep" &>/dev/null; then
        case "$dep" in
            dsh) echo "错误: 缺少 dsh，请先运行 $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dsh.sh" >&2 ;;
            pnpm) echo "错误: 缺少 pnpm（dsh plugin 用它管理 profile 依赖），请先运行 $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pnpm.sh" >&2 ;;
            *) echo "错误: 缺少依赖 $dep" >&2 ;;
        esac
        exit 1
    fi
done

if [[ "${CN:-}" == "1" ]]; then
    NPM_REGISTRY="https://registry.npmmirror.com"
fi

for spec in "${PLUGINS[@]}"; do
    IFS='|' read -r name repo commit links <<< "$spec"
    dir="$PLUGIN_ROOT/$name"
    marker="$VERSIONS_DIR/$name"

    # 已装到位的判据：目录/版本标记齐全，且每个包都构建过并链接进 profile
    stale=0
    if [[ "$(cat "$marker" 2>/dev/null)" != "$commit" ]]; then
        stale=1
    fi
    for link in ${links//,/ }; do
        package="$dir/${link%%:*}"
        package="${package%/.}"
        if [[ ! -f "$package/lib/index.js" ]] || ! plugin_linked "$package"; then
            stale=1
        fi
    done

    echo ""
    echo "==> $name @ ${commit:0:12}"

    if [[ "$stale" == "0" ]]; then
        echo "$name 已是最新"
        continue
    fi

    if [[ "$UPDATE" == "1" ]]; then
        if [[ ! -d "$dir" ]]; then
            echo "未安装，跳过: $name"
            continue
        fi
        confirm_update "$name -> ${commit:0:12}" || continue
    fi

    remote="$repo"
    if [[ "${CN:-}" == "1" ]]; then
        remote="${GITHUB_PROXY_PREFIX}${repo}"
    fi

    if [[ ! -d "$dir/.git" ]]; then
        mkdir -p "$dir"
        git -C "$dir" init -q
        git -C "$dir" remote add origin "$remote"
    fi

    dirty=1
    if [[ -z "$(git -C "$dir" status --porcelain)" ]]; then
        dirty=0
        echo "拉取 ${commit:0:12}..."
        git -C "$dir" fetch -q --depth 1 origin "$commit"
        git -C "$dir" checkout -q --detach FETCH_HEAD
    else
        echo "$name 工作区有未提交改动，跳过固定 commit，仅重新构建"
    fi

    echo "构建 $name..."
    npm_args=(install --no-fund --no-audit --loglevel=error --progress=false)
    if [[ -n "$NPM_REGISTRY" ]]; then
        npm_args+=(--registry "$NPM_REGISTRY")
    fi
    (cd "$dir" && npm "${npm_args[@]}")
    (cd "$dir" && npm run build)

    for link in ${links//,/ }; do
        package="$dir/${link%%:*}"
        package="${package%/.}"
        for artifact in lib/index.js lib/client.js; do
            if [[ ! -f "$package/$artifact" ]]; then
                echo "错误: 构建产物缺失 $package/$artifact" >&2
                exit 1
            fi
        done
    done

    if [[ "$dirty" == "0" ]]; then
        mkdir -p "$VERSIONS_DIR"
        echo "$commit" > "$marker"
    fi

    for link in ${links//,/ }; do
        package="$dir/${link%%:*}"
        package="${package%/.}"
        if plugin_linked "$package"; then
            echo "${link##*:} 已在 profile $PROFILE 中"
        else
            dsh plugin --profile "$PROFILE" add "$package"
        fi
    done
    echo "$name 安装完成: $dir"
done

echo ""
echo "dsh 插件安装完成。重启 Web 服务生效: dsh web"
