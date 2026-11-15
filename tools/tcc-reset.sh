#!/usr/bin/env bash
# 清除某个 App 的 TCC 授权记录，主动请求一次让它回到列表，再引导重新授权。
#
# 适用于 adhoc 签名的 App（无 TeamIdentifier）：tccd 的授权记录钉的是二进制 cdhash，
# App 重建后 csreq 失配，系统设置里开关仍显示"开"但实际静默拒绝。
# 此时必须删掉记录重加，而设置面板的开关/`+` 只改旧行的状态、不重写 csreq，
# 所以要先 tccutil reset。
#
# 用法:
#   tcc-reset.sh                 重置 /Applications/旺财.app 的各项权限并打开设置面板
#   tcc-reset.sh --restart       重置后顺带重启 App（会杀掉宿主终端里的会话）
#   tcc-reset.sh --check         只验证当前权限状态
#   tcc-reset.sh /path/App.app   对其它 App 操作

set -uo pipefail

APP="/Applications/旺财.app"
RESTART=0
CHECK=0
for a in "$@"; do
  case "$a" in
    --restart) RESTART=1 ;;
    --check) CHECK=1 ;;
    -* ) echo "未知参数: $a" >&2; exit 2 ;;
    * ) APP="$a" ;;
  esac
done

INFO="$APP/Contents/Info.plist"
[[ -f "$INFO" ]] || { echo "找不到 $INFO" >&2; exit 1; }
# PlistBuddy 而不是 defaults: defaults 会把中文输出成 \u65fa\u8d22 这样的转义，拿它匹配进程名永远匹配不上。
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO") || exit 1
EXEC=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO") || exit 1
SERVICES="ScreenCapture Accessibility PostEvent SystemPolicyAllFiles SystemPolicyDesktopFolder"

check() {
  if screencapture -x /tmp/.tcc-check.png 2>/dev/null; then
    echo "截图/屏幕录制:  OK"
    rm -f /tmp/.tcc-check.png
  else
    echo "截图/屏幕录制:  拒绝"
  fi
  if osascript -e 'tell application "System Events" to key code 63' >/dev/null 2>&1; then
    echo "键盘鼠标控制:  OK"
  else
    echo "键盘鼠标控制:  拒绝"
  fi
  # 只算当前进程启动之后的失配：重启前的旧账与现在这份二进制无关。
  local pid started since counts
  pid=$(pgrep -x "$EXEC" | head -1)
  if [[ -z "$pid" ]]; then
    echo "csreq 失配: App 未运行，跳过统计"
    return
  fi
  started=$(LC_ALL=C ps -o lstart= -p "$pid" | awk '{print $1,$2,$3,$4,$5}')
  since=$(LC_ALL=C date -j -f '%a %b %d %T %Y' "$started" '+%Y-%m-%d %H:%M:%S')
  counts=$(log show --start "$since" --predicate 'subsystem == "com.apple.TCC"' --style compact 2>/dev/null |
    grep "Failed to match existing code requirement for subject $BID" | sed 's/.*and service //' | sort | uniq -c)
  if [[ -n "$counts" ]]; then
    echo "csreq 失配(本次启动以来，按服务):   # 列出的权限记录与当前二进制不一致，需重置后重加"
    echo "$counts"
  else
    echo "csreq 失配(本次启动以来): 无"
  fi
}

echo "目标: $APP ($BID)"
if (( CHECK )); then
  check
  exit 0
fi

for s in $SERVICES; do
  tccutil reset "$s" "$BID"
done

# 重置把 App 从列表里删掉了，所以每项都主动请求一次：被拒也会留下记录，面板里直接拨开关就行，不用 + 去找。
# 屏幕录制与辅助功能有请求 API，完全磁盘访问和桌面文件夹只能靠访问受保护路径触发。
python3 -c 'import ctypes; ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics").CGRequestScreenCaptureAccess()' >/dev/null 2>&1
osascript -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrustedWithOptions($.NSDictionary.dictionaryWithObjectForKey($.NSNumber.numberWithBool(true), $("AXTrustedCheckOptionPrompt")))' >/dev/null 2>&1
cat "$HOME/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1
ls "$HOME/Desktop" >/dev/null 2>&1

open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

cat <<EOF

接下来手动做（设置面板已打开，App 已回到各列表里，开关是关的）:
  1. 屏幕录制 → 打开 $APP 的开关
  2. 辅助功能 → 打开 $APP 的开关
  3. 完全磁盘访问 → 打开 $APP 的开关
  4. 完全退出 App 再打开

桌面文件夹会弹窗，点允许即可。
为什么要先 reset: 旧记录的 csreq 已失配，面板里拨开关只改状态、不重写它。
EOF

if (( RESTART )); then
  echo
  echo "重启 App（当前终端会话会被断开，pi 若挂在该会话的 server 下可存活）..."
  pkill -f "$APP/Contents/MacOS/$EXEC"
  sleep 2
  open "$APP"
  sleep 3
fi

echo
echo "重新授权并重启后，用 '$0 --check' 验证。"