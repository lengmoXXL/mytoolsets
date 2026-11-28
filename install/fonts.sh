#!/bin/bash
# 从 OSS 下载字体到 fonts/ 目录，并把 ttf/otf 安装到系统字体目录
# （macOS ~/Library/Fonts，Linux ~/.local/share/fonts）。
# 可重入：系统副本与仓库内容一致则跳过，不一致则覆盖（打过补丁的同名字体能更新）。
# --remove 只删除与仓库副本内容一致的系统字体，即本脚本装的那份。

set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS_DIR="$SCRIPT_DIR/../fonts"
OSS_BASE_URL="https://lengmo-asserts.oss-cn-beijing.aliyuncs.com/fonts"
case "$(uname -s)" in
    Darwin) SYSTEM_FONTS_DIR="$HOME/Library/Fonts" ;;
    *) SYSTEM_FONTS_DIR="$HOME/.local/share/fonts" ;;
esac

# 每个字体对应的文件名清单
font_files() {
    case "$1" in
        dejavu)
            printf '%s\n' "DejaVuSansMNerdFontMono-Regular.ttf" "DejaVuSansMNerdFontMono-Bold.ttf"
            ;;
        aurulent)
            printf '%s\n' "AurulentSansMNerdFont-Regular.otf" "AurulentSansMNerdFontMono-Regular.otf" "AurulentSansMNerdFontPropo-Regular.otf" "README.md" "SIL Open Font License.txt"
            ;;
        droid)
            # 打过补丁的版本：补了 U+25CB ○ 字形（herdr idle 符号）
            printf '%s\n' "DroidSansMNerdFontMono-Regular.ttf"
            ;;
        yunhei)
            # 打过补丁的版本：声明等宽并规范家族名为 TsangerYunHei（Ghostty 只收等宽字体）
            printf '%s\n' "仓耳云黑-W04.ttf" "仓耳云黑-W07.ttf"
            ;;
        *)
            return 1
            ;;
    esac
}

urlencode() {
    local LC_ALL=C s="$1" out="" i c b
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) out+="$c" ;;
            *)
                printf -v b '%d' "'$c"
                printf -v c '%%%02X' "$(( b & 255 ))"
                out+="$c"
                ;;
        esac
    done
    printf '%s' "$out"
}

list_fonts() {
    echo "可用字体:"
    echo "  aurulent - AurulentSansMono Nerd Font"
    echo "  droid    - DroidSansMono Nerd Font（含 ○ 补丁）"
    echo "  dejavu   - DejaVuSansMono Nerd Font Regular+Bold（主字体）"
    echo "  yunhei   - TsangerYunHei W04 (仓耳云黑，等宽补丁)"
}

install_font() {
    local name="$1" files
    if ! files=$(font_files "$name"); then
        echo "错误: 未知字体 '$name'"
        list_fonts
        return 1
    fi

    local font_dir="$FONTS_DIR/$name"
    mkdir -p "$font_dir" "$SYSTEM_FONTS_DIR"

    local filename
    while IFS= read -r filename; do
        echo "下载 $name/$filename ..."
        curl -fL "$OSS_BASE_URL/$name/$(urlencode "$filename")" -o "$font_dir/$filename"
        case "$filename" in
            *.ttf | *.otf)
                if cmp -s "$font_dir/$filename" "$SYSTEM_FONTS_DIR/$filename"; then
                    echo "已安装，跳过: $filename"
                else
                    cp "$font_dir/$filename" "$SYSTEM_FONTS_DIR/$filename"
                fi
                ;;
        esac
    done <<< "$files"
}

usage() {
    cat << EOF
用法: $0 [--update] [--remove] [字体名...]

$(list_fonts)

不带参数则安装全部字体

选项:
  --update  更新已安装的工具（未安装则跳过）
  --remove  卸载字体（带字体名则只卸载指定字体）
EOF
}

ALL_FONTS=(dejavu aurulent droid yunhei)
FONT_NAMES=()

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
            FONT_NAMES+=("$1")
            ;;
    esac
    shift
done

if [[ "$REMOVE" == "1" ]]; then
    if [[ ${#FONT_NAMES[@]} -eq 0 ]]; then
        FONT_NAMES=("${ALL_FONTS[@]}")
    fi
    for name in "${FONT_NAMES[@]}"; do
        if ! font_files "$name" >/dev/null; then
            echo "错误: 未知字体 '$name'"
            list_fonts
            exit 1
        fi
    done
    confirm_remove "字体: ${FONT_NAMES[*]}" || exit 0
    for name in "${FONT_NAMES[@]}"; do
        while IFS= read -r filename; do
            case "$filename" in
                *.ttf | *.otf)
                    if cmp -s "$FONTS_DIR/$name/$filename" "$SYSTEM_FONTS_DIR/$filename"; then
                        remove_file "$SYSTEM_FONTS_DIR/$filename"
                    fi
                    ;;
            esac
        done < <(font_files "$name")
        remove_dir "$FONTS_DIR/$name"
    done
    exit 0
fi

if [[ "$UPDATE" == "1" ]]; then
    echo "跳过字体更新（未固定版本）"
    exit 0
fi

if [[ ${#FONT_NAMES[@]} -eq 0 ]]; then
    echo "安装全部字体..."
    FONT_NAMES=("${ALL_FONTS[@]}")
fi

for name in "${FONT_NAMES[@]}"; do
    install_font "$name"
done

echo ""
