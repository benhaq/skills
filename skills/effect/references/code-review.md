# Effect Code Review

A 12-point quality pipeline for reviewing Effect-TS code. This is a cross-cutting capability — not a mode — that applies the same analysis whether reviewing generated code or auditing existing codebases.

## Quick Index

| Check | What to Review | Key Signals |
|-------|---------------|-------------|
| [Check 1: LSP Diagnostics](#check-1-lsp-diagnostics) | Type errors, Effect-specific checks | `floatingEffect`, `missingYieldStar` |
| [Check 2: Service Architecture](#check-2-service-architecture) | Service pattern, Layer wiring | `ServiceMap.Service`, `defaultLayer` |
| [Check 3: Error Handling](#check-3-error-handling) | Error classes, catchTag usage | `throw` in generator, `catchAll` overuse |
| [Check 4: Schema Usage](#check-4-schema--data-modeling) | Branded types, decodeUnknown at boundaries | `Schema.brand` without `withStatics` |
| [Check 5: Resource Management](#check-5-resource-management) | acquireRelease, scoped, finalizers | Leaked resources, missing cleanup |
| [Check 6: Concurrency Safety](#check-6-concurrency-safety) | forkScoped, Semaphore, Deferred | Orphaned fibers, race conditions |
| [Check 7: Observability](#check-7-observability) | Logging, tracing, metrics | `console.*`, missing spans |
| [Check 8: Testing](#check-8-testing) | @effect/vitest, it.scoped, mock layers | Plain vitest imports, no test isolation |
| [Check 9: Performance](#check-9-performance) | Caching, Pool, memoization | Repeated computation, missing Cache |
| [Check 10: Security](#check-10-security) | Input decoding, tagged error exposure | Unvalidated external input |
| [Check 11: Import Hygiene](#check-11-import-hygiene) | Barrel imports, @effect/schema legacy | `from "effect/Effect"`, multiple effect versions |
| [Check 12: Idiomatic Assessment](#check-12-idiomatic-assessment) | Overall Effect idiom | Effect.fn, pipe chains, yield* usage |

## Triggers

**Activate when user says:** "review this code", "audit this codebase", "check this PR", "is this idiomatic Effect", "review Effect patterns", "what's wrong with this Effect code", "code review"

## Scope Detection

Auto-detect review scope from context:

| User says | Scope | What to do |
|-----------|-------|-----------|
| "review this file", "check this code", pastes snippet | **Single file** | Full pipeline on one file |
| "review this PR", "check my changes", "review the diff" | **Diff** | `git diff --name-only` then pipeline on changed `.ts` files |
| "audit this codebase", "review the project", "how's our Effect code" | **Full codebase** | Find all Effect files then pipeline on each |

### Finding Effect Files

For full codebase scope, identify Effect files by:
- Files importing from `"effect"` or `"@effect/*"`
- Command: `rg "from \"effect\"" src/ -t ts -t tsx -l`
- Also check: `rg "from \"@effect/" src/ -t ts -t tsx -l`
- Exclude: `node_modules/`, `dist/`, generated files

### Search & Analysis Policy

| Tool | Use For |
|------|---------|
| `rg` | Broad discovery: file names, imports, symbol mentions, configs, initial narrowing |
| `ast-grep` | TypeScript/TSX structural checks: anti-pattern detection, service architecture, codemod candidates |
| `bun typecheck` + `@effect/language-service diagnostics` | Semantic verification — **required** before presenting findings |

> **Do NOT treat `rg` or `ast-grep` as proof that code is correct.** These tools detect patterns — they cannot verify that the Effect code is type-safe or semantically correct. Always follow structural checks with LSP diagnostics and typecheck. If `ast-grep` or `rg` is not installed, prompt the user to install first: `bun add -g ast-grep`.

---

## The 12-Point Quality Pipeline

Run each check in order. Assign severity per finding. Stop early if Check 1 surfaces unrecoverable type errors.

Each check produces findings at three severity levels:
- **Critical** (must fix) — bugs, correctness issues, silent failures
- **Warning** (should fix) — anti-patterns, missing best practices
- **Suggestion** (could improve) — style, idiom, optimization

> **Automation:** For the full executable pipeline with exact tool calls, see `scripts/review-prompt.md`.

### Check 1: LSP Diagnostics

**Source:** `@effect/language-service` plugin diagnostics
**Reference:** See `references/lsp-integration.md` for full setup and severity mapping.

Run `bunx @effect/language-service diagnostics --file FILE --format json` and categorize:

| Diagnostic | Severity | Meaning |
|-----------|----------|---------|
| `floatingEffect` | Critical | Effect created but never yielded — silently does nothing |
| `missingYieldStar` | Critical | Missing `yield*` — expression discarded |
| `classSelfMismatch` | Critical | Service class type mismatch — breaks DI |
| `multipleEffectVersions` | Critical | Duplicate Effect runtime — subtle type failures |
| `tryCatchInGenerator` | Warning | `try/catch` in generator — use Effect error channel |
| `effectInFailure` | Warning | Effect passed to failure position — likely bug |
| `multipleEffectProvide` | Warning | Multiple `.pipe(Layer.provide(...))` — merge layers |
| `layerMergeAllWithDependencies` | Warning | `Layer.mergeAll` with dependent layers — use `Layer.provideMerge` |
| `asyncFunction` | Suggestion | `async` function — use `Effect.gen` instead |
| `globalConsole` | Suggestion | `console.*` — use `Effect.log` family |
| `globalFetch` | Suggestion | Global `fetch` — use `HttpClient` service |
| `unnecessaryEffectGen` | Suggestion | `Effect.gen` wrapping a single yield — simplify |

> For the complete diagnostic list and fix map, see `references/lsp-integration.md`. The table above highlights the diagnostics most commonly encountered during code review.

### Check 2: Service Architecture

**Source:** Pattern detection based on version

**For Effect 4.x** — verify 6-step ServiceMap pattern:

| Step | What to check | Severity if missing |
|------|-------------|-------------------|
| 1. Interface | `export interface Interface` inside service namespace | Warning |
| 2. Service class | `ServiceMap.Service` (canonical) | Warning |
| 3. Layer | `Layer.effect(` or `Layer.sync(` | Warning |
| 4. defaultLayer | `export const defaultLayer` | Warning |
| 5. Runtime | `makeRuntime` or `ManagedRuntime.make` | Suggestion |
| 6. Facades | `export async function` wrapping `runtime.runPromise` | Suggestion |

**For Effect 3.x** — verify Effect.Service pattern:

| Step | What to check | Severity if missing |
|------|-------------|-------------------|
| 1. Context tag | `Context.Tag<ServiceType>("service-name")` | Warning |
| 2. Service class | `Effect.Service` with `context` tag | Warning |
| 3. Layer | `Layer.effect(` or `Layer.sync(` | Warning |
| 4. defaultLayer | `export const defaultLayer` | Warning |
| 5. Runtime | `ManagedRuntime.make` | Suggestion |

**Version-aware detection commands:**
```bash
# v4 patterns
rg -n "ServiceMap.Service" "$FILE"
rg -n "Layer.effect|Layer.sync|Layer.succeed" "$FILE"

# v3 patterns
rg -n "Effect\.Service" "$FILE"
rg -n "Context\.Tag" "$FILE"

# Common
rg -n "defaultLayer" "$FILE"
rg -n "ManagedRuntime|makeRuntime" "$FILE"
```

**Migration note for v3 codebases:** Flag `Context.Tag` usage as "v3 canonical — plan v4 migration" not as a defect.

### Check 3: Error Handling

**Source:** Pattern matching on error constructs

**For Effect 4.x:**

| Pattern | Detection | Severity |
|---------|----------|----------|
| `throw` inside `Effect.gen` | `throw` keyword in generator body | Critical |
| `catchAll` with generic re-throw | `catchAll` followed by `Effect.fail` without narrowing | Warning |
| Errors not using `TaggedErrorClass` | Error classes without `Schema.TaggedErrorClass` | Warning |
| Missing error type exports | Error classes not in barrel exports | Suggestion |

**Correct v4 error definition:**
```ts
export class UserNotFoundError extends Schema.TaggedErrorClass<UserNotFoundError>()(
  "UserNotFoundError",
  { userId: Schema.String },
) {}
```

**For Effect 3.x:**

| Pattern | Detection | Severity |
|---------|----------|----------|
| `throw` inside `Effect.gen` | `throw` keyword in generator body | Critical |
| `Data.TaggedError` without Schema | Error class without `Schema` field | Warning |
| Plain `Error` class | `class MyError extends Error` | Warning |
| No `catchTag` usage | `catchAll` where `catchTag` per variant is cleaner | Suggestion |

**Correct v3 error definition:**
```ts
export class UserNotFoundError extends Data.TaggedError<UserNotFoundError>("UserNotFoundError") {
  constructor(
    public readonly userId: string,
  ) {
    super()
  }
}
```

**Anti-pattern (both versions):**
```ts
// WRONG: throw in generator
Effect.gen(function* () {
  const user = yield* db.get(id)
  if (!user) throw new Error("not found")  // Bypasses error channel
})
```

**Migration note:** For v3 codebases, `Data.TaggedError` is canonical — flag as "v3 pattern, plan Schema.TaggedErrorClass for v4 migration", not as defect.

### Check 4: Effect Correctness

**Source:** AST-level pattern detection

| Pattern | Detection | Severity |
|---------|----------|----------|
| Missing `yield*` | Effect expression on its own line without `yield*` | Critical |
| `Effect.runPromise` inside service layer | `runPromise` in a file that also has `Layer.effect` | Critical |
| Wrong provide order | `Layer.provide` after `Effect.runPromise` | Warning |
| Fiber without join/interrupt | `Effect.fork` without corresponding `Fiber.join` or `Fiber.interrupt` | Warning |
| Missing Scope management | `acquireRelease` without `Effect.scoped` or `it.scoped` | Warning |
| Long pipe chains (>7 operators) | Count `.pipe(` chain length | Suggestion |

Detection:
```bash
# Missing yield* — lines with Effect-returning calls but no yield*
rg -n "Effect\.|yield\*" "$FILE" | rg -v "yield\*" | rg "Effect\."
# Note: Filter out import statements (`import { Effect }`), type annotations
# (`Effect.Effect<...>`), and comments from results before flagging.

# runPromise inside service
rg -n "runPromise|runSync" "$FILE"
```

### Check 5: Schema & Data Modeling

**Source:** Schema usage patterns (see `references/schema-data-modeling.md`)

| Pattern | Detection | Severity |
|---------|----------|----------|
| Branded types without `withStatics` | `Schema.brand` without `pipe(Schema.withStatics({...}))` | Warning |
| Union types without discriminator | `Schema.Union` members lacking `_tag` field | Warning |
| Missing decode at boundaries | API handlers without `Schema.decodeUnknown` | Warning |
| Raw `Class` for errors | `Schema.Class` where `Schema.TaggedErrorClass` fits | Suggestion |
| Missing `Schema.encode` at output boundary | Responses sent without encoding | Suggestion |

Detection:
```bash
rg -n "Schema.brand|Schema.Union|Schema.Class" "$FILE"
rg -n "Schema.decodeUnknown|Schema.decode" "$FILE"
```

### Check 6: effect-solutions Compliance

**Source:** Compare code against canonical patterns from `effect-solutions`

Workflow:
1. Map source files to topics (service files -> `services-and-layers`, error files -> `error-handling`, etc.)
2. Fetch canonical: `effect-solutions show <topic>`
3. Structural comparison

Report format per topic:
```
| Topic | Status | Detail |
|-------|--------|--------|
| services-and-layers | ✓ Compliant | Full 6-step pattern |
| error-handling | ⚠ Deviation | Uses plain Error class instead of TaggedErrorClass |
| testing | ✗ Non-compliant | Plain vitest, no @effect/vitest |
```

Or run the bundled script:
```bash
bash skills/effect/scripts/effect-solutions-check.sh
```

### Check 7: Observability

**Source:** Telemetry and logging patterns (see `references/observability.md`)

| Pattern | Detection | Severity |
|---------|----------|----------|
| Service methods not using `Effect.fn` | Method bodies without `Effect.fn("Name.method")` wrapper | Warning |
| `console.log` / `console.error` | `console.` calls anywhere | Warning |
| Missing span annotations | `Effect.fn` present but no `Effect.annotateCurrentSpan` | Suggestion |
| No structured logging | `Effect.log` without structured fields object | Suggestion |
| No metrics | No `Metric.counter` / `Metric.histogram` usage | Suggestion |

Detection:
```bash
rg -n "Effect\.fn\b" "$FILE"
rg -n "console\.(log|error|warn|info)" "$FILE"
rg -n "annotateCurrentSpan" "$FILE"
rg -n "Metric\." "$FILE"
```

### Check 8: Testing

**Source:** Test file analysis (see `references/testing-guide.md`)

| Pattern | Detection | Severity |
|---------|----------|----------|
| Plain `vitest` instead of `@effect/vitest` | Import from `"vitest"` not `"@effect/vitest"` | Warning |
| Missing `it.scoped` | `it(` or `it.effect(` without `it.scoped` for resource tests | Warning |
| No mock layers | Tests calling real services, no `Test` layer exports | Suggestion |
| Missing error path tests | Only happy-path test cases, no `Effect.flip` assertions | Suggestion |
| No `TestClock` usage | Time-dependent code tested without `TestClock.adjust` | Suggestion |

Detection:
```bash
rg -rn "from \"vitest\"" "$TEST_DIR"
rg -rn "from \"@effect/vitest\"" "$TEST_DIR"
rg -rn "it\.scoped|it\.effect|it\.live" "$TEST_DIR"
rg -rn "TestClock|TestContext" "$TEST_DIR"
```

### Check 9: Resource Management

**Source:** Resource lifecycle patterns

| Pattern | Detection | Severity |
|---------|----------|----------|
| `try/finally` instead of `acquireRelease` | `try {` ... `finally {` in Effect code | Warning |
| Resources opened without `Scope` | `acquireRelease` without enclosing `Effect.scoped` | Warning |
| Manual cleanup callbacks | `addEventListener`/`removeEventListener` pattern | Warning |
| Pool without TTL | `Pool.make` without `timeToLive` option | Suggestion |
| Missing `Effect.addFinalizer` | Scope-dependent resources without finalizer | Suggestion |

Correct pattern:
```ts
const managed = Effect.acquireRelease(
  Effect.sync(() => createConnection(url)),
  (conn) => Effect.sync(() => conn.close()),
)
```

### Check 10: Concurrency

**Source:** Shared state and parallel execution patterns

| Pattern | Detection | Severity |
|---------|----------|----------|
| `let` for shared mutable state | `let` variable mutated from multiple fibers | Critical |
| Unbounded `Effect.all` with `concurrency: "unbounded"` | `Effect.all(` with large/dynamic arrays and `"unbounded"` | Warning |
| Missing `Semaphore` for throttling | High-concurrency code without `Effect.makeSemaphore` | Suggestion |
| `Deferred` without timeout | `Deferred.await` without `Effect.timeout` | Suggestion |
| No structured concurrency | `Effect.fork` without `Effect.forkScoped` or `forkIn` | Suggestion |

Detection:
```bash
rg -n "let " "$FILE" | rg -v "const|readonly"
rg -n "concurrency.*unbounded|concurrency.*Infinity" "$FILE"
rg -n "Semaphore|makeSemaphore" "$FILE"
rg -n "Deferred.await" "$FILE"
```

### Check 11: Import Hygiene

**Source:** Import statement analysis

| Pattern | Detection | Severity | Version |
|---------|----------|----------|---------|
| Multiple Effect versions | Different `effect` versions in lockfile | Critical | Both |
| v3 `@effect/schema` import | `from "@effect/schema"` | Warning | v4 codebase |
| v3 `@effect/io` import | `from "@effect/io"` | Warning | v4 codebase |
| v4 barrel import in v3 | `from "effect"` | Warning | v3 codebase |
| Non-barrel imports | `from "effect/Effect"` | Suggestion | Both |

**Version-aware detection:**
```bash
# Detect Effect version first
EFFECT_VERSION=$(node -p "require('./package.json').dependencies.effect || require('./package.json').devDependencies.effect" 2>/dev/null | head -c 3)

# For v4 codebases — flag v3 imports
if [ "$EFFECT_VERSION" = "4." ]; then
  rg -rn "from \"@effect/schema\"" "$FILE"
  rg -rn "from \"@effect/io\"" "$FILE"
fi

# For v3 codebases — flag v4 patterns
if [ "$EFFECT_VERSION" = "3." ]; then
  rg -rn "from \"effect\"" "$FILE" | rg -v "from \"effect/"  # barrel imports in v3
fi

# Non-barrel imports (both versions)
rg -rn "from \"effect/" "$FILE"

# Multiple versions
rg "\"effect\":" package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null | sort -u
```

### Check 12: Idiomatic Assessment

**Source:** Holistic pattern analysis — the "smell test"

| Symptom | Diagnosis | Severity |
|---------|----------|----------|
| `Effect.runPromise` scattered across files | Not using facade pattern; runtime leaking into business logic | Warning |
| `catchAll` everywhere with generic handler | Error channel not being leveraged; errors are untyped | Warning |
| Services without layers | Missing dependency injection; hard to test | Warning |
| `async/await` wrapping Effect | Mixing paradigms; lose Effect benefits | Warning |
| `try/catch` around `runPromise` | Error channel bypassed; should use typed errors | Warning |
| Raw `Promise` in service implementations | Should be `Effect.tryPromise` or `Effect.promise` | Warning |
| Effect used in only one file | Adoption too shallow; not gaining architectural value | Suggestion |
| No typed error channel | All effects are `Effect<A, never>` — errors hidden in `unknown` | Suggestion |

This check produces an overall idiomatic rating:

| Rating | Criteria |
|--------|----------|
| **Idiomatic** | All 12 checks pass, full service pattern, typed errors, Effect.fn everywhere |
| **Mostly Idiomatic** | 1-2 warnings, minor deviations, good architecture |
| **Partially Idiomatic** | 3-5 warnings, some anti-patterns, but Effect is being used intentionally |
| **Non-Idiomatic** | 6+ warnings or any critical, mixing paradigms, Effect as afterthought |

---

## Review Output Format

### Validation Status Reporting

Always include validation status with failure categorization:

```markdown
### Validation Status

| Check | Tool | Status | Category |
|-------|------|--------|----------|
| LSP Diagnostics | effect-language-service | ⚠ Completed | Product type failure |
| Typecheck | tsc --noEmit | ✗ Failed | Product type failure |
| Tests | vitest run | ⚠ Skipped | Toolchain failure |
| Lint | biome lint | ✓ Passed | — |

**Categories:**
- **Toolchain failure** — command didn't run (missing deps, broken Node/Bun)
- **Product type failure** — command ran, code has type errors
- **Product test failure** — command ran, tests failed
- **External dependency unavailable** — service unavailable, skipped
- **Migration note** — v3/v4 rule flagged for future migration, not current defect
```

### Single File Review

```markdown
## Effect Code Review: `src/services/user.ts`

### Health Score: 10/12 checks passing

### Validation Status

| Check | Status | Detail |
|-------|--------|--------|
| LSP Diagnostics | ✓ Passed | 0 errors, 2 suggestions |
| Typecheck | ✓ Passed | No type errors |
| Tests | ⚠ Skipped | Test runner missing ICU |

### Critical (must fix)

- **Line 42** — `floatingEffect`: Effect created but never yielded
  **Fix:** Add `yield*` before `userService.validate(input)`
  **Why:** This validation silently never runs

### Warnings (should fix)

- **Line 18** — `tryCatchInGenerator`: `try/catch` in Effect.gen body
  **Fix:** Use `Effect.catchTag` or typed error channel
  **Why:** Bypasses Effect's error tracking

- **Line 91** — Service method not using `Effect.fn`
  **Fix:** Wrap with `Effect.fn("UserService.create")(function* () { ... })`
  **Why:** Loses tracing and span context

### Suggestions (could improve)

- **Line 5** — `globalFetch`: Using global `fetch`
  **Fix:** Use `HttpClient` service for testability
  **Why:** Global fetch is not interceptable in tests

### Migration Notes (Effect 3.x codebase)

- **Line 15** — `Effect.Service` usage detected
  **Note:** v3 canonical pattern — plan migration to `ServiceMap.Service` for v4
- **Line 67** — `Data.TaggedError` usage detected
  **Note:** v3 canonical pattern — plan migration to `Schema.TaggedErrorClass` for v4

### Positive Patterns ✓

- Full 6-step ServiceMap.Service pattern
- All errors use Schema.TaggedErrorClass
- Typed error channel with per-error catchTag
- Effect.gen on all public methods
```

### Diff / PR Review

```markdown
## Effect Code Review: PR #123 (4 files changed)

### Health Score: 9/12 checks passing

### Changed Files

| File | Status | Issues |
|------|--------|--------|
| `src/services/user.ts` | ⚠ 2 warnings | Missing Effect.fn, console.log |
| `src/services/auth.ts` | ✓ Clean | — |
| `src/errors.ts` | ✓ Clean | — |
| `src/index.ts` | ⚠ 1 suggestion | Non-barrel import |

### effect-solutions Compliance

| Topic | Status | Gap |
|-------|--------|-----|
| services-and-layers | ✓ Compliant | — |
| error-handling | ✓ Compliant | — |
| testing | ⚠ Deviation | New service missing test file |
| observability | ⚠ Deviation | Effect.fn missing on 2 methods |

### Priority Fixes

1. **`src/services/user.ts:67`** — Add `Effect.fn` wrapper to `create` method
2. **`src/services/user.ts:89`** — Replace `console.log` with `Effect.logInfo`
3. **`src/index.ts:3`** — Change `from "effect/Effect"` to `from "effect"`
```

### Full Codebase Audit

```markdown
## Effect Code Review: Full Codebase Audit

### Overview

| Metric | Value |
|--------|-------|
| Effect files found | 23 |
| Service files | 8 |
| Test files | 12 |
| Schema files | 3 |
| Overall health | 10/12 checks passing |

### Summary by Category

| # | Check | Status | Issues |
|---|-------|--------|--------|
| 1 | LSP Diagnostics | ✓ | 0 errors, 2 suggestions |
| 2 | Service Architecture | ✓ | All 8 services follow 6-step pattern |
| 3 | Error Handling | ⚠ | 2 services use plain Error class |
| 4 | Effect Correctness | ✓ | No missing yield*, clean provide chains |
| 5 | Schema & Data Modeling | ✓ | Branded types correct |
| 6 | effect-solutions Compliance | ⚠ | 1 deviation in error handling |
| 7 | Observability | ✓ | Effect.fn on all methods |
| 8 | Testing | ✓ | @effect/vitest, it.scoped, mock layers |
| 9 | Resource Management | ✓ | acquireRelease pattern used |
| 10 | Concurrency | ✓ | Ref-based state, bounded concurrency |
| 11 | Import Hygiene | ✓ | Single version, barrel imports |
| 12 | Idiomatic Assessment | ✓ | Mostly Idiomatic |

### Priority Fixes

1. **`src/errors/api.ts`** — Migrate `ApiError` to `Schema.TaggedErrorClass`
2. **`src/errors/db.ts`** — Migrate `DbError` to `Schema.TaggedErrorClass`

### Idiomatic Assessment: Mostly Idiomatic

Strong Effect architecture with full service pattern adoption. Two error classes
predate the TaggedErrorClass migration — fixing these would bring the codebase to
fully idiomatic status.
```

---

## effect-solutions Comparison Workflow

When comparing user code against canonical patterns:

### Step 1: Map Code to Topics

| File type | effect-solutions topic |
|-----------|----------------------|
| Service files (`*Service.ts`) | `services-and-layers` |
| Error files, TaggedErrorClass/Data.TaggedError | `error-handling` |
| Schema definitions | `schema-data-modeling` |
| Test files (`*.test.ts`) | `testing` |
| Config, Layer composition | `dependency-injection` |
| Resource management, Scope | `resource-management` |
| Queue, PubSub, Stream | `concurrency` |

### Step 2: Fetch Canonical Patterns

```bash
effect-solutions show services-and-layers
effect-solutions show error-handling
# ... for each mapped topic
```

### Step 3: Version-Aware Structural Comparison

Detect Effect version first, then compare against appropriate canonical:

**For Effect 4.x:**

| Aspect | Canonical | User Code | Match? |
|--------|----------|-----------|--------|
| Service definition | `ServiceMap.Service` | `ServiceMap.Service` | ✓ |
| Service definition | `ServiceMap.Service` | `Context.Tag` | ⚠ Legacy — flag as migration note |
| Error definition | `Schema.TaggedErrorClass` | `Schema.TaggedErrorClass` | ✓ |
| Error definition | `Schema.TaggedErrorClass` | `Data.TaggedError` | ⚠ Migration note |
| Layer composition | `Layer.provide` pipeline | `Layer.mergeAll` only | ✓ Acceptable |
| Test setup | `it.scoped` + mock layer | `it.effect` + real DB | ⚠ No isolation |

**For Effect 3.x:**

| Aspect | Canonical (v3) | User Code | Match? |
|--------|----------------|-----------|--------|
| Service definition | `Effect.Service` + `Context.Tag` | `Effect.Service` + `Context.Tag` | ✓ |
| Error definition | `Data.TaggedError` | `Data.TaggedError` | ✓ |
| Error definition | `Data.TaggedError` | `Schema.TaggedErrorClass` | ⚠ v4 pattern in v3 |
| Brand type | `Brand.nominal` | `Brand.nominal` | ✓ |
| Brand type | `Brand.nominal` | `Schema.brand` + `withStatics` | ⚠ v4 pattern in v3 |

### Step 4: Report Deviations

Only flag findings that matter:

| Deviation type | Severity | Flag? |
|----------------|----------|-------|
| Bug or correctness issue | Critical | Always |
| Type safety gap | Warning | Always |
| v3 pattern in v4 codebase | Migration note | Yes, clearly labeled |
| v4 pattern in v3 codebase | Migration note | Yes, clearly labeled |
| Unjustified deviation from canonical | Suggestion | Yes, with rationale |
| Project-specific adaptation with clear reason | — | Do NOT flag |

**Example justified adaptation (do not flag):**
```ts
// Using Context.Tag instead of ServiceMap.Service because this service
// is consumed by a v3 library that expects the old tag shape.
```

**Example v3 legacy pattern (flag as migration note, not defect):**
```ts
// Using Context.Tag — this is v3 canonical, plan migration to ServiceMap.Service
// for Effect 4.x compatibility
```
