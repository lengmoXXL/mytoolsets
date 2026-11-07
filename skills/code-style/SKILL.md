---
name: code-style
description: Minimalist style review for code, scripts, configuration, and documentation. Use when asked to check code or doc style, review whether changes are necessary, enforce minimal implementation, or inspect changed files for unnecessary helpers, structure, control flow, comments, abstraction, compatibility logic, redundant sections, restated content, misplaced content, scattered related code, duplicated responsibilities, unintuitive information order, or unrequested documentation.
---

# Code Style

Use this skill to review code and documentation changes for necessity and
arrangement.

## Scope

Determine the review range before checking.

- If the user names a range, use it: uncommitted changes, a base commit, a base
  branch, or one commit.
- If no range is named, review uncommitted changes.
- Use repository tools to inspect the exact diff before judging. Review the
  changes together with the parts they relate to: existing code or prose a
  change duplicates, calls, alters, restates, contradicts, or makes outdated.
- At each level, check the full review range, including pre-existing code or
  prose in it, not only lines a diff adds.

## Shared Rules

These rules apply at every structural level.

### Minimal Implementation

For each unit, decide whether it must exist.

#### Compatibility Logic

Flag compatibility branches, fallbacks, shims, legacy paths, version
checks, platform checks, aliases, migrations, or tolerance for old formats
unless they are clearly part of the user's requested behavior.

Do not invent compatibility support from general caution, possible old data,
existing consumers, platform differences, dependency versions, or unknown
deployments.

#### Unrequested Documentation

Flag documentation in the reviewed range that the user did not request: doc
files, README sections, usage guides, or tutorial paragraphs.
Documentation is a change like any other; do not invent it from general caution.

### One Owner Per Responsibility

A responsibility has one owner. Code that repeats that responsibility calls
its owner instead of implementing the same work again: this is the DRY rule
(don't repeat yourself). Similar text alone does not establish a shared
responsibility.

## Review Order

Review packages, files, classes and structs, functions, then implementations.
For documentation, check files at level 2, sections and outlines at level 3,
and paragraphs and sentences at level 5. Top-level script logic also belongs
to level 5.

At each level, apply the shared rules and that level's checks. Skip levels that
do not apply or have no findings. Classify a finding by the largest boundary
that must change to resolve it, not by how many files the edit touches:
changing a function signature is function-level even when its callers span
several files.

When a level has findings, finish checking that level and defer lower levels.
For a review-only request, return all findings at that level and wait until
they have been addressed before starting another round.

When fixes are requested, fix the current level and start another round.
Recheck the updated code from the largest level, since structural changes can
invalidate earlier judgments. Continue within the authorized scope until all
applicable levels pass or further work needs user input.

## Checks

### 1. Packages

#### Package Boundaries Earn Their Place

In module design, one operation is one requirement. Flag a package that serves
no requirement of its own and hides no external mechanism a test can replace.
A split is wrong when one operation's flow crosses several packages whose
callers must thread state between them, when packages only change together, or
when a package holds only types or helpers that callers must combine into a
complete operation. A merge is wrong when it joins packages with different
requirements, callers, or axes of change because they touch the same data.

##### Example: A Split the Requirement Decides Against

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

### 2. Files

#### File Placement Matches Intent

Code and prose belong in the file whose purpose matches their responsibility.
Flag necessary content placed in a file about something else; move it to the
right file instead of duplicating it there.

#### Related Declarations Stay Together

Keep declarations read or changed together in one place: a helper near its
only caller, related functions in one contiguous group. Flag file organization
that scatters one task across unrelated files or distant declarations and
forces the reader to jump back and forth.

### 3. Classes, Structs, and Document Sections

#### Type Levels Mirror Containment

In a class or struct, each level holds members of the same group. Flag members
of different groups collapsed into one level; put each member inside the
group it belongs to.

##### Example: Fields at Two Levels Collapsed Into One Level

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

#### Outline Levels Mirror Containment

In a document outline, each level holds a rule whose children are cases of it,
or groups of related content. Flag a case beside the rule it specializes.

##### Example: A Case Beside the Rule It Specializes

```markdown
## Retries

Failed requests retry with backoff.

## Rate limits

Rate-limited requests retry with backoff too.
```

The second heading belongs below the first: it states one case of that rule.

#### Section Placement Matches Intent

Content belongs under the section or heading that matches its intent. Move
misplaced content to the right section instead of duplicating it there.

##### Example: Prerequisites Under Usage

```markdown
## Usage

This script requires bash 5+.
```

A requirement is not usage; it belongs with prerequisites or installation,
not under the heading that promises commands to run.

#### Section Order Follows Dependencies

Put prerequisites before the procedure and foundational concepts before the
sections that depend on them. Keep one topic's sections together; flag an
outline that forces readers to jump between unrelated threads.

### 4. Functions

#### Function Boundaries Earn Their Place

Functions and methods expose coherent operations. Flag wrappers and option
machinery that only carry a value without providing a needed abstraction,
and separate entry points that duplicate the same operation.

##### Example: Options for a Single Knob

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

##### Example: A Second Writer for One Format

```go
type store struct{ path string }

func (s *store) Save(v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0o644)
}

func (s *store) Dump(v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0o644)
}
```

`Dump`'s body is a copy of `Save`'s, so one piece of work has two owners.
If `Dump` has no distinct required contract, remove it and use `Save`.

#### Copies That Own No Responsibility

Keep small repetitions inline when they serve separate purposes and share no
responsibility (DAMP: descriptive and meaningful phrases). Flag a helper
extracted only to remove that textual similarity when it hides which value
belongs to each use.

### 5. Function Implementation and Prose

#### Checks Stay With Their Owner

Delete a duplicate check only if the remaining code calls the owning function
on every affected path and that function validates the same input before any
operation that depends on the check.

##### Example: Deleting a Copy

```go
type blob struct{ path string }

func Load(path string) ([]byte, error) {
	if path == "" {
		return nil, errors.New("empty path")
	}
	return os.ReadFile(path)
}

func (b *blob) Read() ([]byte, error) {
	if b.path == "" {
		return nil, errors.New("empty path")
	}
	return Load(b.path)
}
```

`Load` rejects an empty path too, so dropping the check in `Read` leaves that
error to `Load`.

#### Example: Unrequested Legacy Format

```go
if cfg.Endpoint == "" && cfg.LegacyURL != "" {
	cfg.Endpoint = cfg.LegacyURL
}
```

If the requested behavior only uses `Endpoint`, the legacy field support is
unnecessary unless the user asked to preserve old config files. This violates
Compatibility Logic; remove the compatibility path.

#### Related Steps Stay Together

Keep the branches of one decision in one place and one topic's logic in one
contiguous block. Use a variable immediately after modifying it; nothing
unrelated may sit between the change and its use.

##### Example: Rewrite Separated From Its Use

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

#### Control Flow Resolves Each Case Early

Resolve each known case before proceeding with the path it clears. Flag
implementations that defer error handling or nest the happy path; handle
failure immediately and keep the remaining path at the top indentation level.

##### Example: Deferred Error Branch

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

#### Prose Builds Understanding Gradually

Put what a passage depends on before the passage: purpose before mechanism,
a term before its first use, and an antecedent before its pronoun. Flag
forward references and interleaved threads that force the reader to double
back.

##### Example: Purpose After Mechanism

```markdown
etcd replicates every write through Raft and streams changes over a watch
API, which is what makes it a cluster's shared configuration store.
```

The mechanism precedes what the thing is, so the sentence can only be
understood by reading backwards. Lead with what it is and what it is for, then
the mechanism that delivers it.

#### Self-Explanatory Code Over Comments

Flag comments that restate what the code already says: narrating the
next line, translating a well-named identifier into prose, or labeling an
obvious block. Prefer renaming or restructuring the code so it explains itself.
A comment earns its place only when it says what code cannot: why a non-obvious
decision was made, a workaround for an external quirk, or an invisible
constraint.

##### Example: Narrating Comment

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

##### Example: Announcing What the Code Does Not Do

```go
func notify(order Order) error {
	// No fallback to SMS: the admin decided against it.
	return email.Send(order.Email, order.Total)
}
```

The comment is 此地无银三百两: by announcing that the fallback is not there,
it makes the reader wonder why one should be, without saying why. Delete it.

## Output

For a review, state the current level and report only that level's findings.
If lower levels were deferred, say they have not yet been reviewed. Say there
are no findings only after all applicable levels pass.

Use this format for each finding:

```text
<file>:<line>
规则：<the named rule under Shared Rules or Checks it violates>
说明：<what it violates, quoting the code or sentence>
```

A finding that violates no rule is not reported. Keep the explanation specific
to the reviewed range, and avoid general style essays.

When fixes are requested, summarize the changes, validation, and any remaining
findings or deferred levels.
