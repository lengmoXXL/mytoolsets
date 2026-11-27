---
name: refine
description: Iteratively refine work against acceptance criteria, verified each round by an independent fresh checker. Use when asked to refine, polish, or harden work until it meets stated criteria, or to run a self-check loop before declaring a task done.
---

# Refine

## Goal

Drive the work to meet the user's acceptance criteria, proving it with an
independent checker each round rather than self-certifying.

## Workflow

1. Fix the acceptance criteria from the user's request. If none are given, ask
   for them before starting; do not invent criteria.
2. Do the work, or the next round of fixes.
3. Run one independent checker pass with the template below. Its first message
   carries your latest response: what you fixed, accepted, or rejected, and why.
4. Read the findings. For each, either fix it or reject it with a concrete reason
   grounded in the criteria or the code. Keep every rejection and its reason in
   your response so the next checker pass sees it.
5. Repeat from step 2 with a new checker pass. Cap at 6 rounds; if findings
   remain at the cap, stop and report them to the user instead of looping.
6. Declare done only after a checker pass returns no findings.

## Checker

Spawn one fresh subagent as the independent checker and wait for its result. The
built-in read-only `explorer` agent fits; otherwise spawn a default agent and tell
it not to modify files. Give it this task as its first message:

    You are an independent refinement checker. Do not modify any file.

    Acceptance criteria:
    <criteria>

    The parent agent's latest response (what it fixed, accepted, or rejected, and why):
    <your latest response>
    ---

    Read the current work in the working directory and report ONLY findings that
    remain unresolved against the criteria. Honor a rejection whose stated reason
    still holds; re-raise a rejected finding only if its reason no longer applies,
    and explain why. If a criterion cannot be verified from the work, report that
    as a finding.

    Output ONLY JSON, no prose:
    {"findings":[{"location":"<file:line>","rule":"<criterion>","reason":"<what remains unresolved>"}]}
    Return {"findings":[]} when everything is resolved.
