---
name: code-report
description: Analyze a codebase or module and produce a markdown report that cites code with verbatim fenced excerpts labeled by path and line. Use when asked to analyze code, explain a codebase, document a module, or generate a code analysis report.
---

# Code Report

Produce a markdown report that explains code, where every claim cites the
exact code it describes.

## Scope

Confirm before writing:

- Range: whole repo, a module, or specific files.
- Audience and depth: onboarding overview vs. deep mechanism analysis.
- Output path and filename: use the user's path if given, otherwise pick
  a name that fits the report topic.

## Process

1. Map the territory first: directory layout, entry points, build/config files.
   Then read the key files. Do not write from filenames or guesses.
2. Build the dependency and call relationships that matter for the chosen scope.
   Skip anything that does not serve the report's purpose.
3. Structure for the scope: module/architecture breakdown → core flows →
   notable implementation details → risks or caveats. Drop sections
   that have nothing to say; do not pad.

## Citation rules

Reports are read in Neovim with otter.nvim, where fenced excerpts carry a
live LSP context. Follow them strictly:

- Every claim about code cites it with a fenced block quoting the exact
  lines, labeled by a caption below the block, wrapped in a blockquote:
  ``> `src/server.ts:42-58` ``. `gd` in the block jumps to the cited lines.
- Quote verbatim with the real language tag (`ts`, `lua`, ...); never
  reformat. Code lines are exempt from the 80-character wrap rule.
- Trim excerpts to the lines that matter for the claim.
- Captions are paths relative to the report file's location.
- Read the file before citing it; line numbers must be exact at writing time.
- Captions drift when code changes — if the codebase is moving, note the
  commit or date in the report header.

## Output

- One markdown file: one-paragraph summary first, then the sections.
- Write the report in the user's language.
- Keep every line within 80 characters while writing; wrap prose manually
  instead of relying on post-formatting.
- Then run the bundled `validate.py <report>` (path relative to the skill
  directory) and fix any citation problems it reports.
- When done, report the output path.
