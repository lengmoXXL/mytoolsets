#!/bin/bash
# install 脚本共享函数

# confirm_update <描述>: 询问是否执行更新，回答 y 才继续
confirm_update() {
    local answer=""
    read -r -p "是否更新 $1? [y/N] " answer || answer=""
    [[ "$answer" =~ ^[Yy]$ ]]
}

# write_managed_block <file> <name> <content_file> [insert_before_pattern]
# 用 # BEGIN configs <name> / # END configs <name> 守卫管理 file 中的一段文本：
# 已有 block 则整体替换；否则可选插到匹配行之前，或追加到文件末尾；
# 内容一致跳过，UPDATE=1 下不一致先确认
write_managed_block() {
    local file="$1"
    local name="$2"
    local content_file="$3"
    local insert_pattern="${4:-}"
    local begin_marker="# BEGIN configs $name"
    local end_marker="# END configs $name"

    local block tmp_file
    block="$(mktemp)"
    {
        echo "$begin_marker"
        cat "$content_file"
        echo "$end_marker"
    } > "$block"

    [[ -f "$file" ]] || touch "$file"
    tmp_file="$(mktemp)"

    local has_begin=0 has_end=0
    grep -qF "$begin_marker" "$file" && has_begin=1
    grep -qF "$end_marker" "$file" && has_end=1

    if [[ "$has_begin" -ne "$has_end" ]]; then
        echo "错误: $file 中存在不完整的 configs managed block" >&2
        rm -f "$block" "$tmp_file"
        return 1
    elif [[ "$has_begin" -eq 1 ]]; then
        awk -v begin="$begin_marker" -v end="$end_marker" -v block="$block" '
            BEGIN {
                while ((getline line < block) > 0) {
                    replacement = replacement line ORS
                }
            }
            $0 == begin {
                printf "%s", replacement
                in_block = 1
                next
            }
            $0 == end {
                in_block = 0
                next
            }
            !in_block {
                print
            }
        ' "$file" > "$tmp_file"
    elif [[ -n "$insert_pattern" ]] && grep -q "$insert_pattern" "$file"; then
        awk -v block="$block" -v pattern="$insert_pattern" '
            BEGIN {
                while ((getline line < block) > 0) {
                    replacement = replacement line ORS
                }
            }
            !inserted && $0 ~ pattern {
                printf "%s", replacement
                inserted = 1
            }
            { print }
        ' "$file" > "$tmp_file"
    else
        cp "$file" "$tmp_file"
        if [[ -s "$tmp_file" ]]; then
            echo "" >> "$tmp_file"
        fi
        cat "$block" >> "$tmp_file"
    fi

    rm -f "$block"

    if cmp -s "$tmp_file" "$file"; then
        rm -f "$tmp_file"
        echo "$file ($name) 未变化"
        return
    fi
    if [[ "${UPDATE:-}" == "1" ]] && ! confirm_update "$file ($name)"; then
        rm -f "$tmp_file"
        return
    fi
    mv "$tmp_file" "$file"
    echo "$file ($name) 已更新"
}

# strip_block <file> <start_regex> <end_regex>: 删除匹配区间（含首尾行），
# 用于清理无 guard 的旧写法
strip_block() {
    local file="$1"
    local start="$2"
    local end="$3"
    local tmp_file
    tmp_file="$(mktemp)"
    sed "/$start/,/$end/d" "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
}


# write_file_if_changed <dest> <content_file>: 内容一致跳过；
# UPDATE=1 下不一致先确认；不一致时覆盖 dest（dest 父目录自动创建）
write_file_if_changed() {
    local file="$1"
    local content_file="$2"
    if cmp -s "$content_file" "$file" 2>/dev/null; then
        rm -f "$content_file"
        echo "$file 未变化"
        return
    fi
    if [[ "${UPDATE:-}" == "1" ]] && ! confirm_update "$file"; then
        rm -f "$content_file"
        return
    fi
    mkdir -p "$(dirname "$file")"
    mv "$content_file" "$file"
    echo "$file 已更新"
}

# confirm_remove <描述>: 询问是否卸载，回答 y 才继续
confirm_remove() {
    local answer=""
    read -r -p "是否卸载 $1? [y/N] " answer || answer=""
    [[ "$answer" =~ ^[Yy]$ ]]
}

# remove_file <path>: 删除文件或符号链接，不存在则跳过
remove_file() {
    if [[ -e "$1" || -L "$1" ]]; then
        rm -f "$1"
        echo "已删除: $1"
    fi
}

# remove_dir <path>: 删除目录，不存在则跳过
remove_dir() {
    if [[ -d "$1" ]]; then
        rm -rf "$1"
        echo "已删除: $1"
    fi
}

# remove_managed_block <file> <name>: 删除 write_managed_block 管理的文本段（含标记行）
remove_managed_block() {
    local file="$1"
    local name="$2"
    local begin_marker="# BEGIN configs $name"
    local end_marker="# END configs $name"
    [[ -f "$file" ]] || return
    grep -qF "$begin_marker" "$file" || return
    local tmp_file
    tmp_file="$(mktemp)"
    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { in_block = 1; next }
        $0 == end { in_block = 0; next }
        !in_block { print }
    ' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
    echo "已删除: $file ($name)"
}
