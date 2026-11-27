---
name: code-style
description: Minimalist style review for code, scripts, configuration, and documentation. Use when asked to check code or doc style, review whether changes are necessary, enforce minimal implementation, or inspect changed files for unnecessary helpers, structure, control flow, comments, abstraction, compatibility logic, redundant sections, restated content, misplaced content, scattered related code, duplicated responsibilities, unintuitive information order, or unrequested documentation.
---

# Code Style

## Goal

Review code, scripts, configuration, and documentation so that the code
accurately expresses its intent and follows a consistent, minimal style.

## Style Summary

The style is minimal and direct: every unit, state, and step serves a stated
requirement; work happens where a reader following the call flow expects it;
the same concept uses the same representation; each responsibility has one
owner; structure mirrors containment and keeps related things together;
information is ordered by dependency; and code explains itself rather than
leaning on comments.

## Review

### What to review

Use the scope the user names, defaulting to uncommitted changes. For a change
review inspect the exact diff; for a review of specified files or directories
read their current contents. Check the full scope at each boundary, including
existing material, and inspect related code and prose that the reviewed
material calls, changes, duplicates, contradicts, or makes outdated.

Review code from packages to files, types, functions, then implementations,
treating top-level script logic at the implementation boundary. Review
configuration from files to sections, then fields. Review documentation from
files to sections and outlines, then paragraphs and sentences. Apply the rules
at every applicable boundary and classify a finding by the largest boundary
that must change to resolve it; changing a function signature is a
function-level finding even when its callers span several files.

### What to report

Check all applicable boundaries in one pass and report the findings together,
grouped by boundary in review order. Report each issue once under the rule that
best explains the fix, and say there are no findings only after all applicable
checks pass. Report each finding in this format:

```text
<file>:<line>
规则：<the violated rule under Rules>
说明：<what it violates, quoting the code or sentence>
```

Tie each finding to a named rule and keep the explanation specific to the
reviewed scope. When fixes are requested, fix the reported findings and recheck
the updated code from the largest boundary, since structural changes can
invalidate earlier judgments. Continue within the authorized scope until all
applicable checks pass or further work needs user input, then summarize the
changes, validation, and any remaining findings.

## Rules

### Minimal Implementation

Identify the requirement or invariant served by each unit, state, and step,
using the user's requirements, API contracts, supported callers, and
configuration as evidence. Apply the same standard to existing code and new
changes.

### Separate Paths Require Distinct Outcomes

For each special case, trace the condition back to the entry point and follow
its result to the caller, keeping a separate path only when a supported
scenario requires a distinct outcome. Check what validation, construction, and
the object's lifetime already guarantee and flag redundant handling inside that
invariant; keep a catch, fallback, or error conversion only when it enables
recovery, fulfills an API contract, or adds useful diagnostic context, flagging
conversions that only relay the error to the same failure outcome; assess each
test against the supported behavior rather than retaining a branch just because
a test exercises it. For each finding, name the triggering state and explain
which guarantee or caller contract makes the separate path unnecessary.

### Verify the Requirement for New Behavior

For each new behavior, identify the user request, existing contract, or
technical dependency of the requested outcome that requires it, and check that
the requirement applies at the entry point where the behavior is added. When a
branch comes from a test, build, or local verification constraint, compare the
same normal invocation with and without its trigger and flag any runtime
behavior change without a requirement that applies to that caller.

### Surface Simplifications That Change Behavior

When removing an existing behavior would eliminate a branch, state, or
abstraction, trace the behavior to the caller that observes it and use the
user's decisions and supported caller contracts to determine whether it is
required. If the choice is open, report it as a decision for the user, stating
the triggering scenario, what happens with each choice, and what code becomes
unnecessary if the behavior is dropped; ask before changing that behavior and
continue with independent fixes.

### Compatibility Logic

Keep compatibility when the user's request, an established contract, a supported
caller, or a supported configuration requires it; flag speculative fallbacks,
shims, legacy paths, version and platform checks, aliases, migrations, and
tolerance for old formats.

### Unrequested Documentation

Flag documentation added outside the requested scope, including doc files,
README sections, usage guides, and tutorial paragraphs. Assess existing
documentation by the purpose it serves in the document.

### Directness

Put work where a reader following the owner's responsibilities and the normal
call flow would expect it to happen. When an implementation changes the expected
location or timing of an operation, or introduces a surprising side effect, make
the purpose of that choice clear where it is made, requiring a short comment
when the local code leaves the reason implicit; in the finding, state what a
reader would expect, what the code does, and which choice needs an explanation.

### Consistency

Use the same representation and conventions for the same concept across related
code or prose; flag conflicting conventions where a single convention can
satisfy the relevant contracts.

### One Owner Per Responsibility

A responsibility has one owner, and code that repeats that responsibility calls
its owner instead of implementing the same work again (DRY); similar text alone
does not establish a shared responsibility. Flag caller-side coordination when
one owner can maintain the same invariant for all callers.

### Checks Stay With Their Owner

Delete a duplicate check only if the remaining code calls the owning function on
every affected path and that function validates the same input before any
operation that depends on the check.

### File Placement Matches Intent

Code and prose belong in the file whose purpose matches their responsibility;
flag necessary content placed in a file about something else and move it to the
right file instead of duplicating it there. Judge a file's purpose by what it
actually does (its responsibility, target, and callers), not its name or
directory label; for a group of sibling files, read the group's purpose from the
members' shared responsibility or target, and flag a member that diverges from
every sibling as belonging to the file that owns its responsibility.

### Related Declarations Stay Together

Keep declarations read or changed together in one place, such as a helper near
its only caller or related functions in one contiguous group; flag file
organization that scatters one task across unrelated files or distant
declarations and forces the reader to jump back and forth.

### Package Boundaries Earn Their Place

In module design, one operation is one requirement; flag a package that serves
no requirement of its own and hides no external mechanism a test can replace. A
split is wrong when one operation's flow crosses several packages whose callers
must thread state between them, when packages only change together, or when a
package holds only types or helpers that callers must combine into a complete
operation; a merge is wrong when it joins packages with different requirements,
callers, or axes of change because they touch the same data.

### Type Levels Mirror Containment

In a class or struct, each level holds members of the same group; flag members
of different groups collapsed into one level and put each member inside the
group it belongs to.

### Function Boundaries Earn Their Place

Functions and methods expose coherent operations; flag wrappers and option
machinery that only carry a value without providing a needed abstraction, and
separate entry points that duplicate the same operation.

### Copies That Own No Responsibility

Keep small repetitions inline when they serve separate purposes and share no
responsibility (DAMP: descriptive and meaningful phrases); flag a helper
extracted only to remove that textual similarity when it hides which value
belongs to each use.

### Related Steps Stay Together

Keep the branches of one decision in one place and one topic's logic in one
contiguous block; use a variable immediately after modifying it, with nothing
unrelated between the change and its use.

### Control Flow Resolves Each Case Early

Handle each failure before proceeding with work that requires success; use early
returns where appropriate to keep the main path at the top indentation level.

### Self-Explanatory Code Over Comments

Flag comments that restate what the code already says, such as narrating the
next line, translating a well-named identifier into prose, or labeling an
obvious block, and prefer renaming or restructuring the code so it explains
itself. A comment earns its place only when it explains the code that is
present: why a non-obvious choice in that code was made, a workaround for an
external quirk, or an invisible constraint. A comment that merely announces an
alternative the code does not take, such as a missing fallback or a rejected
approach, narrates an absence instead of explaining the present code; flag it
unless knowing about that absence is a constraint the reader needs to use the
code correctly.

### Outline Levels Mirror Containment

In a document outline, each level holds a rule whose children are cases of it,
or groups of related content; flag a case beside the rule it specializes.

### Section Placement Matches Intent

Content belongs under the heading whose promise matches its kind, regardless
of the section's position or whether it is the only section: a requirement or
prerequisite is not usage, and a heading that promises commands to run does not
house requirements. Move misplaced content to the right section, creating it if
needed, instead of duplicating it there.

### Section Order Follows Dependencies

Put prerequisites before the procedure and foundational concepts before the
sections that depend on them; keep one topic's sections together and flag an
outline that forces readers to jump between unrelated threads.

### Prose Builds Understanding Gradually

Put what a passage depends on before the passage, such as purpose before
mechanism, a term before its first use, and an antecedent before its pronoun;
flag forward references and interleaved threads that force the reader to double
back.