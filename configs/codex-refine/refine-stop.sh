#!/bin/bash
# Codex Stop hook：每个回合结束后 fork 当前会话跑一次评审，未通过就把 findings
# 作为续跑提示打回去，直到验收标准通过或到轮次上限。
# stdin 是 Codex 的 Stop hook JSON，stdout 是 hook 决策 JSON。
# 是否开启由 state 目录里的 criteria.md 决定（见 codex-refine 命令）。

set -u

HOOK_DIR="${CODEX_REFINE_HOOK_DIR:-$HOME/.codex/hooks}"
STATE_DIR="${CODEX_REFINE_DIR:-$HOME/.codex/refine}"
CRITERIA_FILE="$STATE_DIR/criteria.md"
SESSION_FILE="$STATE_DIR/session"
ROUND_FILE="$STATE_DIR/round"
REVIEW_FILE="$STATE_DIR/review.json"
FINDINGS_FILE="$STATE_DIR/findings.md"
SCHEMA_FILE="$HOOK_DIR/findings.schema.json"
LOG_FILE="$STATE_DIR/refine.log"
MAX_ROUNDS="${CODEX_REFINE_MAX_ROUNDS:-30}"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG_FILE"
}

report() { # 只提示，不阻断
    python3 -c 'import json, sys; print(json.dumps({"systemMessage": sys.argv[1]}))' "$1"
}

stop_loop() { # 清循环状态；findings.md 与 refine.log 留给 status 查
    rm -f "$CRITERIA_FILE" "$SESSION_FILE" "$ROUND_FILE" "$REVIEW_FILE"
}

# 评审是 fork 出来的会话，会再次触发这个 hook
[[ "${REFINE_CHILD:-}" == "1" ]] && exit 0
[[ -s "$CRITERIA_FILE" ]] || exit 0
command -v python3 >/dev/null || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || true
hook_input="$(cat)"

json_field() {
    python3 -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" <<<"$hook_input"
}

session_id="$(json_field session_id)"
cwd="$(json_field cwd)"
[[ -n "$session_id" ]] || exit 0
[[ -n "$cwd" ]] || cwd="$PWD"

# 一次只服务一个会话：第一个结束回合的会话接管这个循环
if [[ -s "$SESSION_FILE" ]]; then
    [[ "$(cat "$SESSION_FILE")" == "$session_id" ]] || exit 0
else
    printf '%s' "$session_id" >"$SESSION_FILE"
fi

round=$(($(cat "$ROUND_FILE" 2>/dev/null || echo 0) + 1))
printf '%s' "$round" >"$ROUND_FILE"
if ((round > MAX_ROUNDS)); then
    log "round $round exceeds $MAX_ROUNDS, not blocking"
    stop_loop
    report "refine: stopped after $((round - 1)) rounds (limit $MAX_ROUNDS); findings remain in $FINDINGS_FILE"
    exit 0
fi

codex_bin="$(command -v codex || true)"
if [[ -z "$codex_bin" ]]; then
    codex_bin="$HOME/.local/bin/codex"
fi
if [[ ! -x "$codex_bin" ]]; then
    log "codex not found"
    report "refine: codex not found on PATH (install/codex.sh)"
    exit 0
fi

prompt="$(cat <<EOF
Refinement check, round $round of an iterative loop that repeats after every fix turn.
Acceptance criteria:
$(cat "$CRITERIA_FILE")

You have the parent session's conversation context. Inspect the current workspace
state and verify whether the work satisfies ALL criteria. Go through the criteria
ONE BY ONE against the actual files; do not stop at the first issue. Earlier
rounds' findings are neither necessarily fixed nor necessarily exhaustive, so
verify the whole criteria list against the current state.
A premature pass ends the loop with unfinished work; when in doubt, report a finding.
Report issues only, with evidence (cite file paths); do not change any file.
Answer only with the JSON object the output schema requires:
{"passed": <boolean>, "findings": [<string>, ...]}.
EOF
)"

log "round $round: reviewing $session_id"
rm -f "$REVIEW_FILE"
REFINE_CHILD=1 "$codex_bin" exec fork "$session_id" -C "$cwd" \
    --output-schema "$SCHEMA_FILE" -o "$REVIEW_FILE" "$prompt" >>"$LOG_FILE" 2>&1
reviewer_status=$?
if [[ "$reviewer_status" -ne 0 || ! -s "$REVIEW_FILE" ]]; then
    log "round $round: reviewer failed (exit $reviewer_status)"
    report "refine: round $round review failed (exit $reviewer_status); see $LOG_FILE"
    exit 0
fi

python3 - "$REVIEW_FILE" "$CRITERIA_FILE" "$FINDINGS_FILE" "$round" <<'PY'
import json, sys

review_path, criteria_path, findings_path, round_no = sys.argv[1:5]

def emit(payload, code=0):
    print(json.dumps(payload))
    sys.exit(code)

try:
    review = json.load(open(review_path))
except Exception as exc:
    emit({"systemMessage": f"refine: round {round_no} reviewer output is not JSON ({exc})"})

findings = [str(item).strip() for item in (review.get("findings") or []) if str(item).strip()]
if review.get("passed") or not findings:
    emit({"systemMessage": f"refine: criteria satisfied after round {round_no}"}, 10)

criteria = open(criteria_path).read().strip()
numbered = "\n".join(f"{index}. {finding}" for index, finding in enumerate(findings, 1))
open(findings_path, "w").write(numbered + "\n")
emit({
    "decision": "block",
    "reason": (
        f'<refine round="{round_no}">\n'
        "Judge every finding below against the acceptance criteria before fixing anything:\n"
        "fix the real ones; for a finding you judge wrong, do not fix it and say plainly\n"
        "that you reject it and why (cite the file, line, or the criterion it misreads).\n"
        "If you cannot tell whether a finding is right, do not guess -- ask the user.\n"
        "A follow-up check runs automatically after this turn; do not restate the criteria\n"
        "or the findings you are fixing. After fixing, re-check every criterion yourself.\n"
        f"\nAcceptance criteria:\n{criteria}\n"
        f"\nFindings from the round {round_no} check:\n{numbered}\n"
        "</refine>"
    ),
})
PY

case "$?" in
    10) stop_loop ;;
    0) ;;
    *)
        log "round $round: decision step failed"
        stop_loop
        ;;
esac
