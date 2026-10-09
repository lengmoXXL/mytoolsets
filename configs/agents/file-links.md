## File links

- Whenever you mention a file path in a reply, emit it as an OSC 8 hyperlink so the
  terminal opens the file on click:
  `\033]8;;file://<abs-path>\033\\<abs-path>\033]8;;\033\\`
  (`\033` is ESC, 0x1B; `<abs-path>` is the absolute path, percent-encoded
  (` ` -> `%20`); the visible text stays the plain path).
- Do not emit escape sequences inside code fences, in file content you write, or in
  output consumed outside a terminal (reports, commit messages, PR bodies, docs).
