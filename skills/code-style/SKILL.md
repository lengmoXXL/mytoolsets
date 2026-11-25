---
name: code-style
description: Minimalist style review for code, scripts, configuration, and documentation. Use when asked to check code or doc style, review whether changes are necessary, enforce minimal implementation, or inspect changed files for unnecessary helpers, structure, control flow, comments, abstraction, compatibility logic, redundant sections, restated content, misplaced content, scattered related code, duplicated responsibilities, unintuitive information order, or unrequested documentation.
---

# Code Style

Review code, scripts, configuration, and documentation for simplicity.

## Review Workflow

### Scope

Use the scope the user names. Default to uncommitted changes.

For a change review, inspect the exact diff. For a review of specified
files or directories, read their current contents.

Check the full scope at each boundary, including existing material.
Inspect related code and prose that the reviewed material calls,
changes, duplicates, contradicts, or makes outdated.

### Review Order

For code, review packages, files, types, functions, then implementations.
Review top-level script logic at the implementation boundary.

For configuration, review files, sections, then fields.

For documentation, review files, sections and outlines, then paragraphs
and sentences.

Apply the shared rules and the relevant checks at every applicable boundary.
Classify a finding by the largest boundary that must change to resolve it.
Changing a function signature is a function-level finding even when its
callers span several files.

### Reporting and Recheck

Check all applicable boundaries in one pass and report the findings
together. Group findings by boundary in review order. Report each issue
once under the rule that best explains the fix. Say there are no findings
only after all applicable checks pass.

Report each finding in the following format.

```text
<file>:<line>
规则：<the violated rule under Shared Rules or Checks by Boundary>
说明：<what it violates, quoting the code or sentence>
```

Tie each finding to a named rule and keep the explanation specific to the
reviewed scope.

When fixes are requested, fix the reported findings and recheck the updated
code from the largest boundary, since structural changes can invalidate
earlier judgments. Continue within the authorized scope until all applicable
checks pass or further work needs user input. Summarize the changes,
validation, and any remaining findings.

## Shared Rules

These rules apply at every structural level.

### Minimal Implementation

Identify the requirement or invariant served by each unit, state, and step.
Use the user's requirements, API contracts, supported callers, and
configuration as evidence. Apply the same standard to existing code and new
changes.

#### Separate Paths Require Distinct Outcomes

For each special case, trace the condition back to the entry point and
follow its result to the caller. Keep a separate path when a supported
scenario requires a distinct outcome.

- **Internal state.** Check what validation, construction, and the object's
  lifetime already guarantee. Keep the code that establishes the invariant
  and flag redundant handling inside it.
- **Failure handling.** Keep a catch, fallback, or error conversion when
  it enables recovery, fulfills an API contract, or adds useful diagnostic
  context. Flag conversions that only relay the error to the same failure
  outcome.
- **Tests.** Assess each test against the supported behavior. A test for an
  existing branch shows what the implementation does. Verify that the
  branch's outcome is required before retaining it for that test.

For each finding, name the triggering state and explain which guarantee or
caller contract makes the separate path unnecessary.

##### Example of Repeated Initialization

The logging API permits one initialization per lifetime. An empty
`path` selects the default configuration when initializing.

```cpp
if (mBackends) {
    if (path.empty()) {
        return Status::OK();
    }
    return Status(EALREADY, "Logging system already initialized");
}
```

Once initialization succeeds, every subsequent call has the same required
outcome. The choice of configuration belongs to the first call.

```cpp
if (mBackends) {
    return Status(EALREADY, "Logging system already initialized");
}
```

#### Compatibility Logic

Keep compatibility when the user's request, an established contract,
a supported caller, or a supported configuration requires it. Flag
speculative fallbacks, shims, legacy paths, version and platform checks,
aliases, migrations, and tolerance for old formats.

##### Example of Unrequested Legacy Format

```go
if cfg.Endpoint == "" && cfg.LegacyURL != "" {
	cfg.Endpoint = cfg.LegacyURL
}
```

When the supported configuration uses `Endpoint` only, remove the legacy
fallback.

#### Unrequested Documentation

Flag documentation added outside the requested scope, including doc files,
README sections, usage guides, and tutorial paragraphs. Assess existing
documentation by the purpose it serves in the document.

### Directness

Put work where a reader following the owner's responsibilities and the
normal call flow would expect it to happen.

When an implementation changes the expected location or timing of an
operation, or introduces a surprising side effect, make the purpose of
that choice clear where it is made. Require a short comment when the
local code leaves the reason implicit. In the finding, state what a
reader would expect, what the code does, and which choice needs an
explanation.

#### Example of Deferred Thread Pool Startup

The executor owns the compression pool, so its constructor is the natural
place to look for thread startup. This implementation starts the pool when
creating the first gzip handler. Explain the reason next to the guard.

```cpp
// Avoid starting compressor threads for configurations without gzip archives.
if (!mPool) {
    mPool = std::make_unique<butil::DelegateSimpleThreadPool>("log-compress", mWorkerCount);
    mPool->Start();
}
```

### Consistency

Use the same representation and conventions for the same concept across
related code or prose. Flag conflicting conventions where a single
convention can satisfy the relevant contracts.

### One Owner Per Responsibility

A responsibility has one owner. Code that repeats that responsibility calls
its owner instead of implementing the same work again: this is the DRY rule
(don't repeat yourself). Similar text alone does not establish a shared
responsibility.

Flag caller-side coordination when one owner can maintain the same
invariant for all callers.

#### Checks Stay With Their Owner

Delete a duplicate check only if the remaining code calls the owning function
on every affected path and that function validates the same input before any
operation that depends on the check.

##### Example of Duplicate Validation

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

## Checks by Boundary

### Files

#### File Placement Matches Intent

Code and prose belong in the file whose purpose matches their responsibility.
Flag necessary content placed in a file about something else; move it to the
right file instead of duplicating it there.

#### Related Declarations Stay Together

Keep declarations read or changed together in one place: a helper near its
only caller, related functions in one contiguous group. Flag file organization
that scatters one task across unrelated files or distant declarations and
forces the reader to jump back and forth.

### Code

#### Packages

##### Package Boundaries Earn Their Place

In module design, one operation is one requirement. Flag a package that serves
no requirement of its own and hides no external mechanism a test can replace.
A split is wrong when one operation's flow crosses several packages whose
callers must thread state between them, when packages only change together, or
when a package holds only types or helpers that callers must combine into a
complete operation. A merge is wrong when it joins packages with different
requirements, callers, or axes of change because they touch the same data.

###### Example of One Operation Split Across Packages

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

#### Types

##### Type Levels Mirror Containment

In a class or struct, each level holds members of the same group. Flag members
of different groups collapsed into one level; put each member inside the
group it belongs to.

###### Example of Mixed Configuration Groups

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

#### Functions

##### Function Boundaries Earn Their Place

Functions and methods expose coherent operations. Flag wrappers and option
machinery that only carry a value without providing a needed abstraction,
and separate entry points that duplicate the same operation.

###### Example of Options for a Single Parameter

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

###### Example of Two Writers for One Format

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

##### Copies That Own No Responsibility

Keep small repetitions inline when they serve separate purposes and share no
responsibility (DAMP: descriptive and meaningful phrases). Flag a helper
extracted only to remove that textual similarity when it hides which value
belongs to each use.

#### Implementation

##### Related Steps Stay Together

Keep the branches of one decision in one place and one topic's logic in one
contiguous block. Use a variable immediately after modifying it; nothing
unrelated may sit between the change and its use.

###### Example of a Rewrite Separated From Its Use

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

##### Control Flow Resolves Each Case Early

Handle each failure before proceeding with work that requires success.
Use early returns where appropriate to keep the main path at the top
indentation level.

###### Example of a Nested Success Path

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

Each `else` branch returns its error. Moving those returns into early
checks lets the success path stay at the top indentation level.

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

##### Self-Explanatory Code Over Comments

Flag comments that restate what the code already says: narrating the
next line, translating a well-named identifier into prose, or labeling an
obvious block. Prefer renaming or restructuring the code so it explains itself.
A comment earns its place only when it says what code cannot: why a non-obvious
decision was made, a workaround for an external quirk, or an invisible
constraint.

###### Example of a Narrating Comment

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

###### Example of an Unnecessary Fallback Comment

```go
func notify(order Order) error {
	// No fallback to SMS: the admin decided against it.
	return email.Send(order.Email, order.Total)
}
```

The comment is 此地无银三百两: by announcing that the fallback is not there,
it makes the reader wonder why one should be, without saying why. Delete it.

### Documentation

#### Sections and Outlines

##### Outline Levels Mirror Containment

In a document outline, each level holds a rule whose children are cases of it,
or groups of related content. Flag a case beside the rule it specializes.

###### Example of a Case Beside the Rule It Specializes

```markdown
## Retries

Failed requests retry with backoff.

## Rate limits

Rate-limited requests retry with backoff too.
```

The second heading belongs below the first: it states one case of that rule.

##### Section Placement Matches Intent

Content belongs under the section or heading that matches its intent. Move
misplaced content to the right section instead of duplicating it there.

###### Example of Prerequisites Under Usage

```markdown
## Usage

This script requires bash 5+.
```

A requirement is not usage; it belongs with prerequisites or installation,
not under the heading that promises commands to run.

##### Section Order Follows Dependencies

Put prerequisites before the procedure and foundational concepts before the
sections that depend on them. Keep one topic's sections together; flag an
outline that forces readers to jump between unrelated threads.

#### Paragraphs and Sentences

##### Prose Builds Understanding Gradually

Put what a passage depends on before the passage: purpose before mechanism,
a term before its first use, and an antecedent before its pronoun. Flag
forward references and interleaved threads that force the reader to double
back.

###### Example of Purpose After Mechanism

```markdown
etcd replicates every write through Raft and streams changes over a watch
API, which is what makes it a cluster's shared configuration store.
```

The mechanism precedes what the thing is, so the sentence can only be
understood by reading backwards. Lead with what it is and what it is for, then
the mechanism that delivers it.