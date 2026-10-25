#!/usr/bin/env bash
# 清除某个 App 的 TCC 授权记录并引导重新授权。
#
# 适用于 adhoc 签名的 App（无 TeamIdentifier）：tccd 的授权记录钉的是二进制 cdhash，
# App 重建后 csreq 失配，系统设置里开关仍显示"开"但实际静默拒绝。
# 此时必须删掉记录重加，而设置面板的开关/`+` 只改旧行的状态、不重写 csreq，
# 所以要先 tccutil reset。
#
# 用法:
#   tcc-reset.sh                 重置 /Applications/旺财.app 的三项权限并打开设置面板
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
BID=$(defaults read "$INFO" CFBundleIdentifier) || exit 1
EXEC=$(defaults read "$INFO" CFBundleExecutable) || exit 1
SERVICES="ScreenCapture Accessibility PostEvent"

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
  local n
  n=$(log show --last 3m --predicate 'subsystem == "com.apple.TCC"' --style compact 2>/dev/null |
    grep -c "Failed to match existing code requirement for subject $BID")
  echo "csreq 失配次数(近3分钟): $n   # >0 说明授权记录与当前二进制不一致，需重置后重加"
}

if (( CHECK )); then
  echo "目标: $APP ($BID)"
  check
  exit 0
fi

echo "目标: $APP ($BID)"
for s in $SERVICES; do
  tccutil reset "$s" "$BID"
done

open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

cat <<EOF

接下来手动做（设置面板已打开）:
  1. 屏幕录制 → + → 选 $APP → 开关打开
  2. 辅助功能 → + → 选 $APP → 开关打开
  3. 完全退出 App 再打开${RESTART:+（本次会由脚本重启）}

为什么必须 + 而不能只拨开关: 旧记录里的 csreq 已经失配，拨开关只改状态不重写它。
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