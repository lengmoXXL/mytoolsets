#!/bin/bash
# 查询工具的上游最新版本
# 来源: GitHub release / npm / npm next / PyPI / crates.io / go / node / zig / kimi / git commit

set -euo pipefail

usage() {
    cat << EOF
用法: $0 <package|owner/repo>
      $0 --all

--all  列出全部已知工具的上游最新版

Packages:
  GitHub release  ripgrep(rg) fzf fd cmake tmux nvim uv codex opencode herdr
                  lua-lsp starpls typos-lsp(typos) rust sarasa aurulent droid
  npm             pi-agent(pi) playwright typescript-lsp bash-lsp pyright
  npm next        dsh
  PyPI            tldr
  crates.io       tree-sitter
  其他            go gopls node zig kimi
  git commit      doc-research neovim-skill markdown-oxide dsh-git dsh-remote-workspace
EOF
}

# entry <package> -> "<source> <target>"
entry() {
    case "$1" in
        ripgrep | rg) echo "gh BurntSushi/ripgrep" ;;
        fzf) echo "gh junegunn/fzf" ;;
        fd) echo "gh sharkdp/fd" ;;
        cmake) echo "gh Kitware/CMake" ;;
        tmux) echo "gh tmux/tmux" ;;
        nvim | neovim) echo "gh neovim/neovim" ;;
        uv) echo "gh astral-sh/uv" ;;
        codex) echo "gh openai/codex" ;;
        opencode) echo "gh anomalyco/opencode" ;;
        herdr) echo "gh herdrdev/herdr" ;;
        lua-lsp | lua-language-server) echo "gh LuaLS/lua-language-server" ;;
        starpls) echo "gh withered-magic/starpls" ;;
        typos-lsp | typos) echo "gh tekumara/typos-lsp" ;;
        rust) echo "gh rust-lang/rust" ;;
        sarasa) echo "gh laishulu/Sarasa-Term-SC-Nerd" ;;
        aurulent | droid | droidsansmono) echo "gh ryanoasis/nerd-fonts" ;;
        pi-agent | pi) echo "npm @earendil-works/pi-coding-agent" ;;
        playwright) echo "npm playwright" ;;
        typescript-lsp) echo "npm typescript-language-server" ;;
        bash-lsp) echo "npm bash-language-server" ;;
        pyright) echo "npm pyright" ;;
        # dsh 的固定版本取自 next 通道（latest 还停在更早的 rc）
        dsh) echo "npmnext @deepseek-ai/dsh" ;;
        tldr) echo "pypi tldr" ;;
        tree-sitter) echo "crates tree-sitter-cli" ;;
        go) echo "go -" ;;
        gopls) echo "gopls -" ;;
        node) echo "node -" ;;
        zig) echo "zig -" ;;
        kimi) echo "kimi -" ;;
        doc-research) echo "commit https://github.com/lengmoXXL/doc-research.git" ;;
        neovim-skill) echo "commit https://github.com/lengmoXXL/neovim-skill.git" ;;
        markdown-oxide) echo "commit https://github.com/lengmoXXL/markdown-oxide.git" ;;
        dsh-git) echo "commit https://github.com/lengmoXXL/dsh-git.git" ;;
        dsh-remote-workspace) echo "commit https://github.com/lengmoXXL/dsh-remote-workspace.git" ;;
        */*) echo "gh $1" ;;
        *) return 1 ;;
    esac
}

ALL_PACKAGES="ripgrep fzf fd cmake tmux nvim uv codex opencode herdr lua-lsp starpls
typos-lsp rust pi-agent playwright typescript-lsp bash-lsp pyright tldr tree-sitter
go gopls node zig kimi dsh doc-research neovim-skill markdown-oxide sarasa aurulent droid
dsh-git dsh-remote-workspace"

latest() {
    local source="$1" target="$2"
    case "$source" in
        gh)
            curl -fsSL --max-time 20 "https://api.github.com/repos/${target}/releases/latest" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
            ;;
        npm)
            curl -fsSL --max-time 20 "https://registry.npmjs.org/${target}/latest" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])'
            ;;
        npmnext)
            curl -fsSL --max-time 20 "https://registry.npmjs.org/${target}" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)["dist-tags"]["next"])'
            ;;
        pypi)
            curl -fsSL --max-time 20 "https://pypi.org/pypi/${target}/json" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])'
            ;;
        crates)
            curl -fsSL --max-time 20 -A configs-latest-version "https://crates.io/api/v1/crates/${target}" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)["crate"]["max_stable_version"])'
            ;;
        go) curl -fsSL --max-time 20 "https://go.dev/VERSION?m=text" | sed -n '1s/^go//p' ;;
        gopls)
            curl -fsSL --max-time 20 "https://goproxy.cn/golang.org/x/tools/gopls/@latest" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)["Version"])'
            ;;
        node)
            curl -fsSL --max-time 30 "https://nodejs.org/dist/index.json" |
                python3 -c 'import json, sys; print(json.load(sys.stdin)[0]["version"])'
            ;;
        zig)
            curl -fsSL --max-time 30 "https://ziglang.org/download/index.json" |
                python3 -c 'import json, sys; print([k for k in json.load(sys.stdin) if k != "master"][0])'
            ;;
        kimi) curl -fsSL --max-time 20 "https://code.kimi.com/kimi-code/latest" ;;
        commit) git ls-remote "$target" HEAD | cut -f1 ;;
    esac
}

for dep in curl git python3; do
    if ! command -v "$dep" &>/dev/null; then
        echo "错误: 缺少依赖 $dep" >&2
        exit 1
    fi
done

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--all" ]]; then
    printf '%-18s %s\n' "package" "latest"
    for package in $ALL_PACKAGES; do
        read -r source target <<< "$(entry "$package")"
        got="$(latest "$source" "$target" 2>/dev/null || true)"
        printf '%-18s %s\n' "$package" "${got:-查询失败}"
    done
    exit 0
fi

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
fi

package="$1"
if ! fields="$(entry "$package")"; then
    echo "错误: 未知 package: $package" >&2
    usage >&2
    exit 1
fi
read -r source target <<< "$fields"

got="$(latest "$source" "$target" 2>/dev/null || true)"
if [[ -z "$got" ]]; then
    echo "错误: 无法获取 $package 的最新版本" >&2
    exit 1
fi

echo "package: $package"
echo "source: $source $target"
echo "latest: $got"
if [[ "$source" == "gh" ]]; then
    echo "release: https://github.com/${target}/releases/tag/${got}"
fi
