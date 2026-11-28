---
name: product-style
description: Minimalist experience review for terminal and desktop products (CLI, TUI, plugin UIs). Use when asked to check product or UX style, or to review a flow, command, keybinding, screen, or prompt for simplicity and consistency.
---

# Product Style

Review CLI, TUI, and plugin interfaces for a simple, consistent experience.

## Scope

Use the scope the user names; otherwise follow the whole feature the change affects end to end: its entry, every state and exit, and the surfaces sharing its keys, terms, and confirmations.

Check as a user trying the product for the first time, not as a reader of its source. Prefer computer use — run the command, click and type through the UI, watch what actually happens — over analyzing code. Judge what the user sees, does, and waits for; read code only when a behavior cannot be observed directly.

## Simple and Consistent

Identify the job the user is trying to do.

- **Simple.** Every screen, state, step, and prompt earns its place by serving that job. Flag what serves none.
- **Consistent.** The same action uses the same key, the same thing the same term, the same kind of choice the same confirmation. Flag a second convention where one already serves.

## Finding

```text
<surface>:<where>
规则：Simple and Consistent
说明：<what it violates, quoting the behavior, label, or message>
```