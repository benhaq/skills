---
name: effect
description: This skill should be used when the user asks to "build a service", "add a layer", "scaffold an Effect project", "debug this error", "fix this type error", "explain Effect.gen", "why is this failing", "review this Effect code", "add error handling", or needs help with Effect-TS patterns (ServiceMap.Service, Effect.Service, Layer.provide, Effect.fn, Schema.decodeUnknown, TaggedErrorClass, Effect.log). Supports both Effect 3.x and 4.x codebases.
---

# EffectTS Master Skill

**Adaptive for Effect 3.x and 4.x** — automatically detects version and applies appropriate rules.

## Step 1: Detect Effect Version

Before any operation, detect the project's Effect version:

```bash
node -p "require('./package.json').dependencies.effect || require('./package.json').devDependencies.effect || 'unknown'"
```

| Version | Rules |
|---------|-------|
| **4.x** | `ServiceMap.Service`, `Schema.TaggedErrorClass`, barrel imports from `effect` |
| **3.x** | `Effect.Service`, `Data.TaggedError`, `Brand.nominal`, `Context.Tag` allowed |
| **Unknown** | Default to 4.x rules, note uncertainty in output |

## Step 2: Environment Preflight

Run diagnostics commands in this priority order:

```bash
# 1. Local binary (best - no network, no mutation)
command -v effect-language-service && effect-language-service diagnostics --project tsconfig.json --format json && exit

# 2. Package manager exec (respects lockfile)
[ -f pnpm-lock.yaml ] && pnpm exec @effect/language-service diagnostics --project tsconfig.json --format json && exit
[ -f bun.lockb ] && bun node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json --format json && exit
npm exec @effect/language-service diagnostics --project tsconfig.json --format json && exit

# 3. bunx with NODE_PATH workaround (bunx cache doesn't include typescript)
# bunx alone fails: it resolves to /private/tmp/bunx-*/node_modules/ which lacks typescript
# The fix: point Node at your project's node_modules where typescript lives
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json --format json
```

**Important — why bunx fails without NODE_PATH:**
```
Cannot find module 'typescript/lib/tsserverlibrary'
Require stack:
- /private/tmp/bunx-501-@effect/language-service@latest/node_modules/@effect/language-service/cli.js
```
The `@effect/language-service` package internally requires TypeScript's tsserverlibrary. bunx installs only the target package to a temp cache — typescript isn't there. Setting `NODE_PATH=./node_modules` tells Node where to find it.

**Correct usage:**

```bash
# Full project scan (recommended) — --project flag resolves TS correctly
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json

# Single file — also requires --project for TS resolution
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --file FILE --project tsconfig.json
```

**Shell alias for convenience:**
```bash
alias effect-diags="NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics"
# Usage: effect-diags --project tsconfig.json
#        effect-diags --file src/service.ts --project tsconfig.json
```

**Preflight health check:**
```bash
node -v || echo "Node: MISSING"
bun -v || echo "Bun: NOT FOUND"
command -v effect-language-service && echo "LSP: AVAILABLE" || echo "LSP: NOT FOUND"
```

## Prerequisites

### effect-solutions CLI (recommended)
Canonical pattern reference:
```bash
bun add -g effect-solutions
git clone --depth 1 https://github.com/Effect-TS/effect-smol.git ~/.local/share/effect-solutions/effect
effect-solutions list
```

### Context7 MCP (auto-configured)
```bash
claude mcp list  # Expected: context7
```

## Task Router

| Task | User says | Action |
|------|-----------|--------|
| **Build/scaffold/refactor** | "build a service", "add a new layer", "scaffold an Effect app" | See `references/service-architecture.md` |
| **Explain/mental model** | "explain Effect.gen", "how does Layer work", "what is yield*" | See `references/mental-models.md` |
| **Debug** | "debug this error", "why is this failing", "fix the type error" | See `references/debugging-patterns.md` |
| **Review/audit** | "review this code", "audit this", "is this idiomatic" | 12-point pipeline — see `references/code-review.md` |
| **Setup** | "setup LSP", "install Effect tools" | Run `scripts/setup-lsp.sh` |

---

## Primary Mode: Production Code

### Match the Prompt Before Writing Code

State interpretation before coding: *"I'll build [Y] from your prompt about [X]. If you meant [Z], please clarify."*

### Canonical Six-Step Pattern

```
Interface → ServiceMap.Service → Layer.effect + Effect.fn → Layer.provide → makeRuntime → facade
```

**Full pattern in `references/service-architecture.md`**

### Quality Verification (Adaptive)

```
1. Write file
2. Run LSP diagnostics (see adaptive command selection above)
3. Quick fixes: effect-language-service quickfixes --file FILE --code DIAG_CODE
4. Re-verify (max 3 iterations)
5. Run typecheck: tsc --noEmit
6. Run tests: vitest run TEST_FILE --reporter=verbose
7. Present verification status with failure categorization
```

**floatingEffect fix:** `effect-language-service quickfixes --file FILE --code floatingEffect`

### Version-Aware Anti-Patterns

| Version | Anti-Pattern | Fix |
|---------|-------------|-----|
| **Both** | `throw new Error()` in Effect.gen | `return yield* Effect.fail(new MyError(...))` |
| **Both** | `Effect.runPromise` in a service | `yield*` the effect instead |
| **Both** | `console.log` (global) | `yield* Console.log(...)` or `yield* Effect.logInfo(...)` |
| **Both** | `process.env.KEY` | `Config.string("KEY")` inside Effect |
| **Both** | Missing `yield*` | Always `yield*` or `return yield*` |
| **4.x** | `Context.Tag`, `Context.GenericTag` | Use `ServiceMap.Service<Service, Interface>()("@app/Name")` |
| **4.x** | `Layer.provide` with array | Use variadic: `Layer.provide(effect, layer1, layer2, ...)` |
| **3.x** | `Effect.Service` without context tag | Use `Context.Tag` for v3 services |
| **3.x** | `Data.TaggedError` without Schema | Consider `Schema.TaggedErrorClass` for v4 migration |

**Effect 4.x migration notes** (flag for v3 codebases as future guidance, not defects):
- `ServiceMap.Service` replaces `Effect.Service`
- `Schema.TaggedErrorClass` replaces `Data.TaggedError`
- `Schema.brand` with `withStatics` replaces `Brand.nominal`
- Barrel imports from `effect` replace `@effect/schema`, `@effect/io`

**Logging inside Effect.gen:**
```ts
// ✅ CORRECT — Console.log (Effect 4.x canonical)
yield* Console.log("User created")

// ❌ WRONG — global console
console.log("User created")
```

### Effect-Docs MCP

For uncertain APIs:
1. Resolve: `mcp__context7__resolve-library-id` with `effect-ts` or `Effect-TS`
2. Query: `mcp__context7__query-docs` with the resolved ID

---

## Code Review

**Trigger:** `review`, `audit`, `check code`, `idiomatic`

Full 12-point pipeline in `references/code-review.md`. The pipeline is version-aware — v3 and v4 patterns are reviewed differently.

**Validation failure categories** (report in output):
- **Toolchain failure** — command didn't run (missing deps, broken Node/Bun)
- **Product type failure** — command ran, code has type errors
- **Product test failure** — command ran, tests failed
- **External dependency unavailable** — service unavailable, skipped
- **Version mismatch** — v3/v4 rule flagged for future migration, not defect

---

## Reference Files

| File | Purpose |
|------|---------|
| `references/service-architecture.md` | 6-step pattern, Layer composition (v3 + v4) |
| `references/schema-data-modeling.md` | Branded types, TaggedErrorClass (v3 + v4) |
| `references/debugging-patterns.md` | floatingEffect, missing layers |
| `references/patterns-catalog.md` | Concurrency, streams, HTTP |
| `references/observability.md` | Effect.fn tracing, logging |
| `references/testing-guide.md` | @effect/vitest, TestClock |
| `references/code-review.md` | 12-point review pipeline |
| `references/lsp-integration.md` | CLI commands, quickfixes |
| `scripts/setup-lsp.sh` | LSP installation |
