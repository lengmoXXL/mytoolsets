## File links

- Whenever you mention a file path in a reply, write it as a markdown link so the
  terminal opens the file on click: `[<abs-path>](file://<abs-path>)`, the
  absolute path as both the text and the target, with spaces percent-encoded
  (` ` -> `%20`). Never hand-write escape sequences or OSC 8 codes; the renderer
  makes the link clickable when the terminal supports it.
- Inside code fences, file content you write, reports, commit messages, PR bodies
  or docs, write the plain path.
