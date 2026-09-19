---
name: code-style
description: Minimalist style review for code, scripts, configuration, and documentation. Use when asked to check code or doc style, review whether changes are necessary, enforce minimal implementation, or inspect changed files for unnecessary helpers, structure, control flow, comments, abstraction, mixed abstraction levels, compatibility logic, redundant sections, restated content, misplaced content, scattered related code, or unrequested documentation.
---

# Code Style

Use this skill to review code and documentation changes for necessity; docs
are reviewed as code. Every function, option, helper, abstraction, comment,
file, dependency, section, paragraph, and sentence must earn its place.

## Scope

Confirm the review range before checking.

- If the user names a range, use it: uncommitted changes, a base commit, a base
  branch, or one commit.
- If no range is named, review uncommitted changes.
- Use repository tools to inspect the exact diff before judging. Review the
  changes together with the parts they relate to: existing code or prose a
  change duplicates, calls, alters, restates, contradicts, or makes outdated.
- Apply every check to the full review range, including pre-existing code or
  prose in it, not only to lines a diff adds.

## Checks

### Minimal Implementation

For each part in the review range, decide whether it must exist and whether it can be part
of another existing entity instead. A small amount of duplication is acceptable;
flag helpers and abstractions that carry no meaningful abstraction of their own,
even when they have multiple call sites.

#### Example: Single-Use Helper

```go
func putIfMissing(values map[string]string, key string, value string) {
	if _, ok := values[key]; !ok {
		values[key] = value
	}
}

putIfMissing(values, key, value)
```

This helper is usually unnecessary when it has one local call site. Inline it:

```go
if _, ok := values[key]; !ok {
	values[key] = value
}
```

### One Intent Per Paragraph

Every paragraph has exactly one primary intent. State that intent and stop;
anything beyond it is excess. The reverse also holds: each intent is primarily
described in at most one place. Flag content beyond the intent (delete it),
paragraphs that mix two intents (split them), and one intent described primarily
in multiple places (merge them). Typical excess: restating what the code, the
UI, or an adjacent sentence already says, and pointers the reader did not ask
for.

#### Example: Restating the Code

```markdown
## install.sh

This script installs the tool. Run it to install the tool.
```

The heading already says what the file is; the sentences add nothing. Delete
them, or replace them with information the reader cannot see: prerequisites,
side effects, or non-obvious options.

### Placement Matches Intent

Each piece of content must live where a reader would look for it given its
intent: the right file, section, or heading. Flag content that is necessary
but misplaced under a heading or in a file about something else; move it
instead of tolerating or duplicating it where it belongs.

#### Example: Prerequisites Under Usage

```markdown
## Usage

This script requires bash 5+.
```

A requirement is not usage; it belongs with prerequisites or installation,
not under the heading that promises commands to run.

### Related Code Stays Together

Code that is read or changed together should sit together: a helper next to
its only caller, the branches of one decision in one place, one topic's logic
in one contiguous block. Flag implementations that scatter a single logical
task across distant locations (far-apart spots in a file, or separate files)
so the reader must jump back and forth to follow one flow. Use a variable
immediately after modifying it; nothing unrelated may sit between the change
and its use.

#### Example: Rewrite Separated From Its Use

```bash
if [[ "$USE_CN" == "true" ]]; then
    REPO_URL="${GITHUB_PROXY_PREFIX}${REPO_URL}"
fi

# ... local-path early return that never reads REPO_URL ...

remote_head="$(git ls-remote "$REPO_URL" HEAD)"
```

The rewrite is cut off from its only reader and also runs on paths that
never use the value. Put the local-path return first, then keep the rewrite
directly above the `ls-remote` that consumes it.

### Self-Explanatory Code Over Comments

Flag comments that restate what the code already says: narrating the
next line, translating a well-named identifier into prose, or labeling an
obvious block. Prefer renaming or restructuring the code so it explains itself.
A comment earns its place only when it says what code cannot: why a non-obvious
decision was made, a workaround for an external quirk, or an invisible
constraint.

#### Example: Narrating Comment

```go
// check whether the user exists
if _, ok := users[id]; !ok {
	return ErrUserNotFound
}
```

The comment duplicates the condition in prose. Delete it; the code already says
what it does. The same applies to doc comments that merely repeat the signature:

```go
// GetUserByID returns the user with the given ID.
func GetUserByID(id string) (*User, error) {
```

### Over-Defensive Guards

Flag checks that only protect against caller misuse or impossible
states when the surrounding contract should already guarantee the invariant.

#### Example: Go Nil Receiver Check

```go
func (s *Store) Save(ctx context.Context, item Item) error {
	if s == nil {
		return errors.New("nil store")
	}
	return s.db.Save(ctx, item)
}
```

If valid calls require a non-nil receiver, the caller should guarantee that
precondition. Prefer removing the guard:

```go
func (s *Store) Save(ctx context.Context, item Item) error {
	return s.db.Save(ctx, item)
}
```

### Fast Entropy Reduction

Structure each function so every step eliminates uncertainty as early as
possible. A necessary check should dispatch its failure branch immediately
(early return/throw), keeping the remaining path at the top indentation level.
Flag implementations that defer error handling or nest the happy path, forcing
the reader to hold unresolved branches in mind.

This applies only to checks that must exist; it never justifies adding new
guards (see Over-Defensive Guards).

#### Example: Deferred Error Branch

```go
func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err == nil {
		var cfg Config
		if err := json.Unmarshal(data, &cfg); err == nil {
			return &cfg, nil
		} else {
			return nil, err
		}
	} else {
		return nil, err
	}
}
```

Every error branch is known at the check site but resolved later, and the
success path sinks two levels deep. Resolve each branch the moment it is known:

```go
func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}
```

### Compatibility Logic

Flag compatibility branches, fallbacks, shims, legacy paths, version
checks, platform checks, aliases, migrations, or tolerance for old formats
unless they are clearly part of the user's requested behavior.

Do not invent compatibility support from general caution, possible old data,
existing consumers, platform differences, dependency versions, or unknown
deployments. If the reviewed range contains compatibility logic, verify that the user asked
for that compatibility before accepting it.

#### Example: Unrequested Legacy Format

```go
if cfg.Endpoint == "" && cfg.LegacyURL != "" {
	cfg.Endpoint = cfg.LegacyURL
}
```

If the requested behavior only uses `Endpoint`, the legacy field support is
unnecessary unless the user asked to preserve old config files. Prefer removing
the compatibility path.

### Layers Keep Their Own Abstraction Level

Flag packages that mix abstraction levels: a high-level package that builds or
picks apart a lower level's data representation, operates on its protocol or
storage format, or performs a lower layer's job inline. Read from the outermost
entry points and follow the imports inward; at each package ask which level's
concepts its API and its code are written in.

Module design runs top-down: the requirements decide which packages exist, and
a package's public API decides the implementation behind it. A package that
reaches past the API of the layer below into its implementation detail is
detached from the design above it, and every later change to that detail leaks
through it.

Delegating to a lower level is not the violation; the higher level doing or
duplicating that work itself is.

#### Example: Storage Reached Through the Domain

```text
internal/
├── admin/
│   └── order.go          # admin API: reads and updates orders
├── order/
│   ├── order.go          # order model and rules
│   └── store.go          # Store interface; the domain's only persistence API
└── storage/
    └── mysql/
        └── store.go      # Store implementation
```

```go
// internal/admin/order.go
func UpdateAmount(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	amount, _ := strconv.Atoi(r.FormValue("amount"))

	db, _ := sql.Open("mysql", dsn)
	_, err := db.Exec("UPDATE orders SET amount = ? WHERE id = ?", amount, id)
	if err != nil {
		http.Error(w, "update failed", http.StatusInternalServerError)
		return
	}

	row := db.QueryRow("SELECT status FROM orders WHERE id = ?", id)
	var status string
	if err := row.Scan(&status); err != nil {
		http.Error(w, "read failed", http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"status": status})
}
```

The admin package reaches through the domain into the storage layer: it opens
the connection itself, writes the order, and picks its columns apart, so the
persistence schema leaks up into the admin layer, which must now track every
column it touches. Let the domain API be the only way in:

```go
// internal/order/store.go
type Store interface {
	UpdateAmount(ctx context.Context, id string, amount int) error
	Status(ctx context.Context, id string) (string, error)
}

// internal/admin/order.go
func UpdateAmount(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	amount, _ := strconv.Atoi(r.FormValue("amount"))
	if err := store.UpdateAmount(ctx, id, amount); err != nil {
		http.Error(w, "update failed", http.StatusInternalServerError)
		return
	}
	status, err := store.Status(ctx, id)
	if err != nil {
		http.Error(w, "read failed", http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"status": status})
}
```

### Unrequested Documentation

Flag documentation in the reviewed range that the user did not request: doc
files, README sections, usage guides, or tutorial paragraphs.
Documentation is a change like any other; do not invent it from general caution.

## Output

Report findings only. If there are none, say so.

Use this format for each finding:

```text
<file>:<line>
判断：<specific part> 不必要
原因：<why this part does not need to exist>
```

Keep reasons specific to the reviewed range. Avoid general style essays.
