#!/bin/bash
# 把文本中的路径包装成 OSC 8 终端超链接（file:// 空 host），其余文字与空白保留
# 用法: link <text>...  或  <text> | link（stdin 逐行）
# 只链接真实存在的路径；支持 ~/ ./ ../ 与 path:line:col 后缀；尾部 prose 标点留在链接外

set -uo pipefail

url_encode_path() {
    local LC_ALL=C s="$1" out="" i c b
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~/-]) out+="$c" ;;
            *)
                printf -v b '%d' "'$c"
                printf -v c '%%%02X' "$(( b & 255 ))"
                out+="$c"
                ;;
        esac
    done
    printf '%s' "$out"
}

# 存在则输出规范化绝对路径，否则返回 1
resolve() {
    local p="$1" dir
    case "$p" in
        "~") p="$HOME" ;;
        "~/"*) p="$HOME/${p#"~/"}" ;;
    esac
    [[ -e "$p" ]] || return 1
    if [[ -d "$p" ]]; then
        dir=$(cd "$p" 2>/dev/null && pwd) || return 1
        printf '%s' "$dir"
    else
        dir=$(cd "$(dirname "$p")" 2>/dev/null && pwd) || return 1
        printf '%s/%s' "${dir%/}" "$(basename "$p")"
    fi
}

link_token() {
    local tok="$1" core punct="" suf="" abs url punct_re='[.,;:)]$'
    core="$tok"
    while [[ "$core" =~ $punct_re ]]; do
        punct="${core: -1}${punct}"
        core="${core%?}"
    done
    if [[ "$core" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
        core="${BASH_REMATCH[1]}"
        suf=":${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
    elif [[ "$core" =~ ^(.+):([0-9]+)$ ]]; then
        core="${BASH_REMATCH[1]}"
        suf=":${BASH_REMATCH[2]}"
    fi
    if ! abs=$(resolve "$core"); then
        printf '%s' "$tok"
        return
    fi
    url=$(url_encode_path "$abs")
    printf '\033]8;;file://%s\033\\%s%s\033]8;;\033\\%s' "$url" "$core" "$suf" "$punct"
}

process_line() {
    local rest="$1" out="" tok pre post
    while [[ "$rest" =~ [^[:space:]]+ ]]; do
        tok="${BASH_REMATCH[0]}"
        pre="${rest%%"$tok"*}"
        post="${rest#*"$tok"}"
        out+="${pre}$(link_token "$tok")"
        rest="$post"
    done
    printf '%s%s\n' "$out" "$rest"
}

if [[ $# -gt 0 ]]; then
    for t in "$@"; do
        process_line "$t"
    done
else
    while IFS= read -r line; do
        process_line "$line"
    done
fi