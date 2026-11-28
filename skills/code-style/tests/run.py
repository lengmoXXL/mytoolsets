#!/usr/bin/env python3
"""Regression tests for the code-style skill rules.

Each case under cases/ holds code that violates one rule and an "expected"
finding (location + rule + reason). For every case the runner reviews the code
twice: once with the rule removed from the skill (absent) and once with the
full skill (present). A judge model then decides, for each review, whether it
reports a finding describing the SAME problem as the expected finding (same
location and underlying reason; the rule label may differ). Keyword matching
cannot make that judgment, so the judge is a model call.

Two backends are supported:
  pi    - pi CLI with --skill (default)
  codex - codex exec with the skill inlined in the prompt, run in an isolated
          HOME/CODEX_HOME so it cannot auto-load ~/.agents/skills (which would
          contaminate the absent variant).

Ideal outcome: absent misses the problem, present catches it. If the model
catches it even without the rule, that is acceptable (verdict "OK"). The
present review MUST catch the problem; if it does not, the case FAILs.

Usage:
  python3 run.py                          # pi backend, all cases
  python3 run.py --backend codex --model gpt-6.2-sol
  python3 run.py --case repeated --jobs 4
  python3 run.py --judge-backend codex --judge-model gpt-6.2-sol
  python3 run.py --list
  python3 run.py --reeval results/<ts>    # re-judge saved reviews after tuning
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TESTS = Path(__file__).resolve().parent
SKILL = TESTS.parent / "SKILL.md"
CASES = TESTS / "cases"
REAL_HOME = Path.home()
CODEX_DEFAULT_MODEL = "gpt-6.2-sol"


def load_cases(substr):
    cases = []
    for d in sorted(CASES.iterdir()):
        if not d.is_dir() or not (d / "case.json").exists():
            continue
        if substr and substr not in d.name:
            continue
        meta = json.loads((d / "case.json").read_text())
        files = meta.get("files") or sorted(
            p.name for p in d.iterdir() if p.name != "case.json"
        )
        cases.append({"id": d.name, "dir": d, "files": files, **meta})
    return cases


def rule_removed(skill_text, rule):
    lines = skill_text.splitlines(keepends=True)
    start = next(
        (i for i, ln in enumerate(lines) if ln.rstrip("\n") == f"### {rule}"), None
    )
    if start is None:
        raise SystemExit(f"rule not found in SKILL.md: {rule}")
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("### ") or lines[j].startswith("## "):
            end = j
            break
    return "".join(lines[:start] + lines[end:])


def run_cmd(cmd, timeout, cwd=None, stdin=None, env=None):
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, input=stdin, capture_output=True, text=True,
            timeout=timeout, env=env,
        )
        err = None if proc.returncode == 0 else (
            f"exit {proc.returncode}: {proc.stderr[-500:]}"
        )
        return proc.stdout, err
    except subprocess.TimeoutExpired:
        return "", f"timeout after {timeout}s"


def default_model(backend):
    if backend == "codex":
        return CODEX_DEFAULT_MODEL
    if os.environ.get("PI_MODEL"):
        prov = os.environ.get("PI_PROVIDER")
        return f"{prov}/{os.environ['PI_MODEL']}" if prov else os.environ["PI_MODEL"]
    return None


def review_prompt(case, skill_text, inline_skill):
    p = (
        "Apply the code-style skill to review these files in the current "
        f"directory: {', '.join(case['files'])}. "
    )
    if case.get("context"):
        p += "Background: " + case["context"] + " "
    p += "Report all findings in the skill's format."
    if inline_skill:
        p += "\n\n=== code-style skill ===\n" + skill_text + "\n=== end skill ==="
    return p


def stage_case(case, workroot):
    ws = Path(tempfile.mkdtemp(dir=workroot))
    for name in case["files"]:
        shutil.copy(case["dir"] / name, ws / name)
    return ws


def pi_review(skill_text, case, model, timeout, workroot):
    ws = stage_case(case, workroot)
    skillfile = workroot / (ws.name + ".SKILL.md")
    skillfile.write_text(skill_text)
    cmd = [
        "pi", "-p", "--no-session", "-ne", "-ns", "-nc", "--no-mcp",
        "--tools", "read,grep,find,ls", "--skill", str(skillfile),
        review_prompt(case, skill_text, inline_skill=False),
    ]
    if model:
        cmd += ["--model", model]
    return run_cmd(cmd, timeout, cwd=ws)


def codex_env(workroot):
    home = Path(tempfile.mkdtemp(dir=workroot, prefix="home-"))
    (home / ".codex").mkdir()
    (home / ".agents").mkdir()
    shutil.copy(REAL_HOME / ".codex" / "auth.json", home / ".codex" / "auth.json")
    return {**os.environ, "HOME": str(home),
            "CODEX_HOME": str(home / ".codex"),
            "AGENTS_HOME": str(home / ".agents")}


def codex_call(prompt, model, reasoning, timeout, workroot, cwd=None):
    outfile = Path(tempfile.mktemp(dir=workroot, suffix=".out.txt"))
    cmd = [
        "codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only",
        "--ignore-user-config", "--ephemeral", "--color", "never",
        "-m", model, "-c", f'model_reasoning_effort="{reasoning}"',
        "-o", str(outfile),
    ]
    if cwd:
        cmd += ["-C", str(cwd)]
    _, err = run_cmd(cmd, timeout, cwd=cwd, stdin=prompt, env=codex_env(workroot))
    out = outfile.read_text() if outfile.exists() else ""
    return out, err


def codex_review(skill_text, case, model, reasoning, timeout, workroot):
    ws = stage_case(case, workroot)
    return codex_call(review_prompt(case, skill_text, inline_skill=True),
                      model, reasoning, timeout, workroot, cwd=ws)


def review(backend, skill_text, case, model, reasoning, timeout, workroot):
    if backend == "codex":
        return codex_review(skill_text, case, model, reasoning, timeout, workroot)
    return pi_review(skill_text, case, model, timeout, workroot)


def judge_prompt(expected, absent_out, present_out):
    e = expected
    return f"""You judge whether a code-style review reports a specific expected problem.

Expected problem:
- Location: {e['location']}
- Rule: {e['rule']}
- Reason: {e['reason']}

Review A (produced with the rule removed from the skill):
\"\"\"
{absent_out}
\"\"\"

Review B (produced with the full skill):
\"\"\"
{present_out}
\"\"\"

For each review, decide whether it contains a finding that describes the SAME
problem as the expected problem: it points to the same location in the file and
gives the same underlying reason; judge the substance, not the label. A mere
mention of the code, or a different problem at the same place, is NOT a match.
For Review B also record attribution: MATCH = the matching finding cites the
expected rule name; OTHER = same problem but a different rule; NO = no match.

Reply with exactly two lines and nothing else:
A: YES or NO
B: MATCH or OTHER or NO
"""


def parse_judge(out):
    a = re.search(r"A\s*[:：]\s*(YES|NO)", out, re.I)
    b = re.search(r"B\s*[:：]\s*(MATCH|OTHER|NO)", out, re.I)
    if not a or not b:
        return None, None, f"unparseable judge answer: {out[:200]}"
    return a.group(1).upper() == "YES", b.group(1).upper(), None


def record(absent=None, present=None, attribution=None, error=None):
    return {"absent": absent, "present": present,
            "present_attribution": attribution, "error": error}


def judge_case(backend, case, absent_out, present_out, model, reasoning,
               timeout, workroot):
    prompt = judge_prompt(case["expected"], absent_out, present_out)
    if backend == "codex":
        prompt += "\nDo not use any tools; answer directly with the two lines."
        out, err = codex_call(prompt, model, reasoning, timeout, workroot)
    else:
        cmd = ["pi", "-p", "--no-session", "-ne", "-ns", "-nc", "--no-mcp",
               "--no-tools"]
        if model:
            cmd += ["--model", model]
        out, err = run_cmd(cmd, timeout, stdin=prompt)
    if err:
        return None, None, out, err
    a, b, perr = parse_judge(out)
    return a, b, out, perr


def verdict(p_detected, a_detected, err):
    if err or p_detected is None or a_detected is None:
        return "ERR"
    if p_detected and not a_detected:
        return "IDEAL"
    if p_detected and a_detected:
        return "OK"
    return "FAIL"


def mark(detected, err, want):
    if err or detected is None:
        return "ERR"
    return "Y" if detected == want else "N"


def report(cases, scored, label, results):
    lines = ["| model | case | rule | absent | present | B | verdict |",
             "|---|---|---|---|---|---|---|"]
    rows = []
    for c in cases:
        s = scored[c["id"]]
        v = verdict(s["present"], s["absent"], s["error"])
        rows.append((c, s, v))
        lines.append(
            f"| {label} | {c['id']} | {c['rule']} | "
            f"{mark(s['absent'], s['error'], False)} | "
            f"{mark(s['present'], s['error'], True)} | "
            f"{s['present_attribution'] or 'ERR'} | {v} |"
        )
    table = "\n".join(lines)
    legend = (
        "\nabsent Y = problem NOT detected without the rule (rule is necessary); "
        "present Y = problem detected with the rule (required).\n"
        "B: MATCH = detected and cites the expected rule; OTHER = detected but "
        "cites a different rule; NO = not detected.\n"
        "verdict: IDEAL = absent Y + present Y; OK = present Y but model catches "
        "it without the rule too; FAIL = present N; ERR = run/judge error.\n"
    )
    print(table + legend)
    print(f"raw outputs: {results}")
    (results / "summary.json").write_text(json.dumps(
        {"model": label, "rows": [
            {"case": c["id"], "rule": c["rule"], "verdict": v,
             "present_detected": s["present"], "absent_detected": s["absent"],
             "present_attribution": s["present_attribution"],
             "error": s["error"]} for c, s, v in rows]}, indent=2))
    (results / "table.md").write_text(table + "\n")
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--case", help="run cases whose id contains this substring")
    ap.add_argument("--backend", choices=["pi", "codex"], default="pi",
                    help="review engine (default pi)")
    ap.add_argument("--model", help="review model; default per backend")
    ap.add_argument("--judge-backend", choices=["pi", "codex"], default="pi",
                    help="judge engine (default pi)")
    ap.add_argument("--judge-model", help="judge model; default per judge backend")
    ap.add_argument("--reasoning", default="medium",
                    help="codex reasoning effort (default medium)")
    ap.add_argument("--timeout", type=int, default=300, help="per-call seconds")
    ap.add_argument("--jobs", type=int, default=2, help="parallel calls")
    ap.add_argument("--list", action="store_true", help="list cases and exit")
    ap.add_argument("--reeval", metavar="DIR",
                    help="re-judge saved review outputs in DIR after tuning expected")
    args = ap.parse_args()

    cases = load_cases(args.case)
    if not cases:
        raise SystemExit("no matching cases")
    if args.list:
        for c in cases:
            print(f"{c['id']:28} {c['rule']}")
        return

    review_model = args.model or default_model(args.backend)
    judge_model = args.judge_model or default_model(args.judge_backend)
    label = f"{args.backend}:{review_model or 'default'}"

    workroot = Path(tempfile.mkdtemp(prefix="code-style-test-"))

    def judge_and_save(c, absent_out, present_out):
        a, p, raw, err = judge_case(
            args.judge_backend, c, absent_out, present_out, judge_model,
            args.reasoning, args.timeout, workroot)
        (results / f"{c['id']}.judge.txt").write_text(raw)
        return c["id"], record(absent=a,
                               present=None if p is None else p in ("MATCH", "OTHER"),
                               attribution=p, error=err)

    if args.reeval:
        results = Path(args.reeval)
        if (results / "summary.json").exists():
            label = json.loads((results / "summary.json").read_text())["model"]

        def rejudge(c):
            fa = results / f"{c['id']}.absent.txt"
            fp = results / f"{c['id']}.present.txt"
            if not fa.exists() or not fp.exists():
                return c["id"], record(error="missing output")
            return judge_and_save(c, fa.read_text(), fp.read_text())

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            scored = dict(pool.map(rejudge, cases))
        rows = report(cases, scored, label, results)
        sys.exit(1 if any(v in ("FAIL", "ERR") for _, _, v in rows) else 0)

    skill_text = SKILL.read_text()
    results = TESTS / "results" / time.strftime("%Y%m%d-%H%M%S")
    results.mkdir(parents=True)

    tasks = []
    for c in cases:
        tasks.append((c, "present", skill_text))
        tasks.append((c, "absent", rule_removed(skill_text, c["rule"])))

    def do_review(task):
        c, variant, text = task
        out, err = review(args.backend, text, c, review_model, args.reasoning,
                          args.timeout, workroot)
        (results / f"{c['id']}.{variant}.txt").write_text(out)
        return c["id"], variant, out, err

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        reviews = list(pool.map(do_review, tasks))

    outs, review_err = {}, {}
    for cid, variant, out, err in reviews:
        outs.setdefault(cid, {})[variant] = out
        if err:
            review_err[cid] = err

    def do_judge(c):
        if c["id"] in review_err:
            return c["id"], record(error=review_err[c["id"]])
        o = outs[c["id"]]
        return judge_and_save(c, o["absent"], o["present"])

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        scored = dict(pool.map(do_judge, cases))

    rows = report(cases, scored, label, results)
    if any(v in ("FAIL", "ERR") for _, _, v in rows):
        sys.exit(1)


if __name__ == "__main__":
    main()