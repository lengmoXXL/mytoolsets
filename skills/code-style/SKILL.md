---
name: code-style
description: Minimalist style review for code, scripts, configuration, and documentation. Use when asked to check code or doc style, review whether changes are necessary, enforce minimal implementation, or inspect changed files for unnecessary helpers, structure, control flow, comments, abstraction, compatibility logic, redundant sections, restated content, misplaced content, scattered related code, duplicated flows, unintuitive information order, or unrequested documentation.
---

# Code Style

Use this skill to review code and documentation changes for necessity and
arrangement; docs are reviewed as code. Every function, option, helper,
abstraction, comment, file, dependency, section, paragraph, and sentence
must earn its place.

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

For each part in the review range, decide whether it must exist and whether it
can be part of another existing entity instead.

#### Example: Options for a Single Knob

```go
type Option func(*client)

func WithTimeout(d time.Duration) Option {
	return func(c *client) { c.timeout = d }
}

func New(addr string, opts ...Option) *client {
	c := &client{addr: addr, timeout: 30 * time.Second}
	for _, opt := range opts {
		opt(c)
	}
	return c
}
```

The one caller writes `New(addr, WithTimeout(5*time.Second))`. With a single knob
and a single caller, the `Option` type, its wrapper, and the loop only carry one
value; pass it directly:

```go
func New(addr string, timeout time.Duration) *client {
	return &client{addr: addr, timeout: timeout}
}
```

### Reuse the Process, Not the Code

Deduplicate at the flow level, not the code level. When two places run the
same sequence of steps, define the sequence once and call it from both, so the
process changes in one place. When only scattered fragments match, keep the
duplication: a helper extracted from those fragments asserts a shared intent
that does not exist, even when several call sites use it, while each flow keeps
changing on its own.
Flag those helpers, and flag a flow copied wholesale into a second caller
instead of being called.

#### Example: Reusing a Fragment

```go
func putIfMissing(values map[string]string, key string, value string) {
	if _, ok := values[key]; !ok {
		values[key] = value
	}
}

func createRequest(name string) map[string]string {
	params := map[string]string{"name": name}
	putIfMissing(params, "type", "standard")
	return params
}

func applyDefaults(settings map[string]string) map[string]string {
	putIfMissing(settings, "region", "us-east-1")
	return settings
}
```

The two functions share the same three-line check, not a process: one builds a
request, the other completes loaded settings. The helper makes the flows look
alike, while each default answers a different concern. Keep the check in each
flow:

```go
func createRequest(name string) map[string]string {
	params := map[string]string{"name": name}
	if _, ok := params["type"]; !ok {
		params["type"] = "standard"
	}
	return params
}

func applyDefaults(settings map[string]string) map[string]string {
	if _, ok := settings["region"]; !ok {
		settings["region"] = "us-east-1"
	}
	return settings
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

### Outline and Type Levels Mirror Containment

In a document outline or a type definition, a level holds the rule its
children are cases of, or the groups the content distinguishes. Flag a case
beside the rule it specializes, and members of different groups sharing one
level.

#### Example: A Case Beside the Rule It Specializes

```markdown
## Retries

Failed requests retry with backoff.

## Rate limits

Rate-limited requests retry with backoff too.
```

The second heading belongs below the first: it states one case of that rule.

#### Example: Fields at Two Levels Collapsed Into One Level

```go
type Config struct {
	Endpoint string
	Timeout  time.Duration
	Addr     string
}
```

`Timeout` applies only to the HTTP endpoint, while `Addr` starts the gRPC
server: three fields sit at one level although the content has two groups. Give
each group its own level:

```go
type Config struct {
	HTTP HTTPConfig
	GRPC GRPCConfig
}

type HTTPConfig struct {
	Endpoint string
	Timeout  time.Duration
}

type GRPCConfig struct {
	Addr string
}
```

The levels now match the groups: each field sits inside the group it belongs to.

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

### Order Builds Understanding Gradually

Order content so every step eliminates uncertainty as early as possible: a
case is ruled out before the path it clears, and no step leaves the reader
holding something unresolved.

Then keep the thread continuous: a reader follows content one step at a time
and cannot take a step whose prerequisite arrives later. Put what a step
depends on before the step: prerequisites before the procedure, purpose before
mechanism, a term before its first use, a value before the operation on it.

Flag content that reads out of order: forward references, a sequence the reader
must double back through, and unrelated threads interleaved (see Related Code
Stays Together).

Flag implementations that defer error handling or nest the happy path; this
applies only to checks that must exist and never justifies adding new guards
(see One Owner Per Responsibility).

#### Example: Deferred Error Branch

Control flow lands the rule hardest: a necessary check dispatches its failure
branch immediately (early return/throw) and keeps the remaining path at the top
indentation level.

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

#### Example: Purpose After Mechanism

```markdown
etcd replicates every write through Raft and streams changes over a watch
API, which is what makes it a cluster's shared configuration store.
```

The mechanism precedes what the thing is, so the sentence can only be
understood by reading backwards. Lead with what it is and what it is for, then
the mechanism that delivers it.

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

#### Example: Announcing What the Code Does Not Do

```go
func notify(order Order) error {
	// No fallback to SMS: the admin decided against it.
	return email.Send(order.Email, order.Total)
}
```

The comment is 此地无银三百两: by announcing that the fallback is not there,
it makes the reader wonder why one should be. If it should not exist, the
cleanest code is the code that does not do it. A comment earns its place only
by giving the reason the code cannot, and only when that reason matters and is
not obvious.

### One Owner Per Responsibility

Each duty has one owner. The stage that establishes an invariant tests it: later
stages of the flow read the result instead of testing it again, and a callee
relies on the precondition its caller guaranteed instead of re-checking it. Flag
a check on an invariant something else already guarantees; the second owner
drifts from the first and leaves two places to keep in step.

#### Example: Re-Testing What the Constructor Established

```go
func Open(path string) (*Store, error) {
	if path == "" {
		return nil, errors.New("empty path")
	}
	return &Store{path: path}, nil
}

func (s *Store) Read() ([]byte, error) {
	if s.path == "" {
		return nil, errors.New("empty path")
	}
	return os.ReadFile(s.path)
}
```

`Open` is the only way to obtain a `Store` and it rejects an empty path, so
`Read` can never see one. The invariant belongs to `Open`; `Read` reads the
result instead of repeating the check.

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

### Compatibility Logic

Flag compatibility branches, fallbacks, shims, legacy paths, version
checks, platform checks, aliases, migrations, or tolerance for old formats
unless they are clearly part of the user's requested behavior.

Do not invent compatibility support from general caution, possible old data,
existing consumers, platform differences, dependency versions, or unknown
deployments.

#### Example: Unrequested Legacy Format

```go
if cfg.Endpoint == "" && cfg.LegacyURL != "" {
	cfg.Endpoint = cfg.LegacyURL
}
```

If the requested behavior only uses `Endpoint`, the legacy field support is
unnecessary unless the user asked to preserve old config files. Prefer removing
the compatibility path.

### Package Boundaries Earn Their Place

In module design, one operation is one requirement. Flag a package that serves
no requirement of its own and hides no external mechanism a test can replace.
A split is wrong when one operation's flow crosses several packages whose
callers must thread state between them, when packages only change together, or
when a package holds only types or helpers that callers must combine into a
complete operation. A merge is wrong when it joins packages with different
requirements, callers, or axes of change because they touch the same data.

#### Example: A Split the Requirement Decides Against

```text
internal/
├── order/
│   └── order.go          # Order and its rules
├── cart/
│   └── cart.go           # cart model and lookup
├── pricing/
│   └── pricing.go        # coupon, membership, and tax rules
├── payment/
│   └── payment.go        # charge calls to an external gateway
└── httpapi/
    └── checkout.go       # checkout endpoint
```

```go
// internal/httpapi/checkout.go
func PlaceOrder(w http.ResponseWriter, r *http.Request) {
	cart := cart.Load(r.FormValue("cart_id"))

	subtotal := pricing.Subtotal(cart.Items())
	subtotal -= pricing.Coupon(cart.Items(), r.FormValue("coupon"))
	total := pricing.Tax(subtotal)

	charge, err := payment.Charge(r.FormValue("token"), total)
	if err != nil {
		http.Error(w, "payment failed", http.StatusBadGateway)
		return
	}
	order := order.New(cart.Items(), total, charge.ID)
	order.Save()
	json.NewEncoder(w).Encode(order)
}
```

The split follows the nouns in the code: the endpoint knows all four packages'
APIs and threads every intermediate value between them. Checkout is one
operation, so it should be one package.

```text
internal/
├── checkout/
│   ├── checkout.go
│   ├── payment.go        # Payment interface owned by the domain
│   └── store.go          # Store interface owned by the domain
├── storage/
│   └── mysql/
│       └── store.go
├── gateway/
│   └── stripe/
│       └── gateway.go
└── httpapi/
    └── checkout.go       # checkout endpoint
```

```go
// internal/httpapi/checkout.go
func PlaceOrder(w http.ResponseWriter, r *http.Request) {
	order, err := checkout.Place(checkout.Request{
		CartID: r.FormValue("cart_id"),
		Coupon: r.FormValue("coupon"),
		Token:  r.FormValue("token"),
	})
	if err != nil {
		http.Error(w, "checkout failed", http.StatusBadGateway)
		return
	}
	json.NewEncoder(w).Encode(order)
}
```

The rule inside checkout is the domain's; storage and gateway stay split off
because each hides a mechanism a test can replace.

### Unrequested Documentation

Flag documentation in the reviewed range that the user did not request: doc
files, README sections, usage guides, or tutorial paragraphs.
Documentation is a change like any other; do not invent it from general caution.

## Output

Report findings only. If there are none, say so.

Use this format for each finding:

```text
<file>:<line>
判断：<specific part> 不必要，或位置、次序、拆分与合并不当
原因：<为何它不必要、该换位置或次序，或该拆分/合并>
```

Keep reasons specific to the reviewed range. Avoid general style essays.
