---
name: effect
description: This skill should be used when the user asks to "build a service", "add a layer", "scaffold an Effect project", "debug this error", "fix this type error", "explain Effect.gen", "why is this failing", "review this Effect code", "add error handling", or needs help with Effect-TS 4.x patterns (ServiceMap.Service, Layer.provide, Effect.fn, Schema.decodeUnknown, TaggedErrorClass, Effect.log).
---

# EffectTS Master Skill

**Effect version target:** 4.x — barrel imports from `effect`, no separate `@effect/schema` package.

## Prerequisites

Before using this skill, install the required tools:

### Required: effect-solutions CLI
Canonical pattern reference for Effect best practices:
```bash
bun add -g effect-solutions
```
Then clone the reference implementations:
```bash
git clone --depth 1 https://github.com/Effect-TS/effect-smol.git ~/.local/share/effect-solutions/effect
```
Verify: `effect-solutions list`

### Required: Context7 MCP
For authoritative Effect API documentation (auto-configured in Claude Code):
```bash
# Verify MCP is configured:
claude mcp list
# Expected: context7 (or restart Claude Code to enable)
```

## Task Router

| Task | User says | Action |
|------|-----------|--------|
| **Build/scaffold/refactor** | "build a service", "add a new layer", "scaffold an Effect app", "implement this feature" | Primary Mode — see `references/service-architecture.md` |
| **Explain/mental model** | "explain Effect.gen", "how does Layer work", "what is yield*", "help me understand" | See `references/mental-models.md` |
| **Debug** | "debug this error", "why is this failing", "fix the type error", "what's wrong with this code" | See `references/debugging-patterns.md` |
| **Review/audit** | "review this code", "check if this is idiomatic", "audit this", "is this correct Effect" | 12-point pipeline — see `references/code-review.md` |
| **Setup** | "setup LSP", "install Effect tools", "configure the language server" | Prerequisites above + run `scripts/setup-lsp.sh` |

---

## Primary Mode: Production Code

### Match the Prompt Before Writing Code

Before generating code, state the interpretation: *"I'll build [Y] from your prompt about [X]. If you meant [Z], please clarify."*

### Canonical Six-Step Pattern

```
Interface → ServiceMap.Service → Layer.effect + Effect.fn → Layer.provide → makeRuntime → facade
```

**Full pattern in `references/service-architecture.md`**

### Quality Verification (HARD-GATE)

```
1. Write file
2. bunx @effect/language-service diagnostics --file FILE --format json
3. Quick fixes: bunx @effect/language-service quickfixes --file FILE --code DIAG_CODE
4. Re-verify (max 3 iterations)
5. bunx tsc --noEmit
6. bunx vitest run TEST_FILE --reporter=verbose
7. Present with verification status
```

**floatingEffect fix:** `bunx @effect/language-service quickfixes --file FILE --code floatingEffect`

### Correct Imports

```ts
import { Effect, Layer, Schema } from "effect"           // CORRECT — barrel
import { makeRuntime } from "@effect/platform"          // CORRECT
// WRONG: @effect/schema (deprecated), subpath imports
```

### Key Anti-Patterns (MUST NOT appear in any output)

| Anti-Pattern | Fix |
|-------------|-----|
| `Context.Tag`, `Context.GenericTag` | FORBIDDEN in v4 — use `ServiceMap.Service<Service, Interface>()("@app/Name")` |
| `throw new Error()` in Effect.gen | `return yield* Effect.fail(new MyError(...))` |
| `Effect.runPromise` in a service | `yield*` the effect instead |
| `console.log` (global) | `yield* Console.log(...)` or `yield* Effect.logInfo(...)` |
| `process.env.KEY` | `Config.string("KEY")` inside Effect |
| Missing `yield*` | Always `yield*` or `return yield*` |
| `Layer.provide` with array argument | `Layer.provide(effect, layer1, layer2, ...)` — variadic, NOT `[layers]` |
| Service method without `Effect.fn` | Wrap in `Effect.fn("Service.method")(function* (...) { ... })` |

**Detailed explanations:** See `references/patterns-catalog.md`

> **CRITICAL:** `Context.Tag` is FORBIDDEN in Effect 4.x. Every occurrence is a bug. Do not suggest it, do not use it in examples, do not mention it as acceptable. Only `ServiceMap.Service` is correct.

**Logging inside Effect.gen — use `Console.log` for simple output, `Effect.logInfo` for structured fields:**
```ts
// ✅ CORRECT — Console.log is the Effect 4.x canonical way
yield* Console.log("User created")

// ❌ WRONG — console.log is the Node.js global (outside Effect system)
console.log("User created")
```
See `references/observability.md` for structured logging with `Effect.logInfo` for production observability.

### Branded Types & Errors

**⚠️ FORBIDDEN — Manual `Brand` constructor without `withStatics`:**
```ts
// ❌ WRONG — no withStatics
import { Schema, Brand } from "effect"
type UserId = Brand<string, "UserId">
const UserIdSchema = Schema.String.pipe(Schema.nonEmpty(), Schema.brand("UserId"))

// ✅ CORRECT — Schema.brand + withStatics
import { Schema, withStatics } from "effect"
export const UserID = Schema.String.pipe(
  Schema.brand("UserID"),
  withStatics((s) => ({
    make: (id: string) => s.makeUnsafe(id),
    isValid: (t: unknown): t is Schema.Schema.Type<typeof UserID> => typeof t === "string" && t.length > 0,
  })),
)
export type UserID = Schema.Schema.Type<typeof UserID>
```
See `references/schema-data-modeling.md` for full patterns.

### Effect-Docs MCP

For uncertain APIs, use the Context7 MCP (see `references/effect-docs.md` for usage):
1. Resolve library: `mcp__context7__resolve-library-id` with `effect-ts` or `Effect-TS`
2. Query docs: `mcp__context7__query-docs` with the resolved library ID

**Fallback when MCP unavailable:** Use `bunx @effect/language-service diagnostics` for local API verification, or browse https://effect.website/docs for canonical patterns.

---

## Code Review

Trigger: `review`, `audit`, `check code`, `idiomatic`

**HARD-GATE: Run all 12 checks. No skipping.**

Full pipeline in `references/code-review.md`

---

## Keep It Lean

**HARD RULES:**
1. ❌ NO `package-lock.json`, `bun.lock`, `node_modules/`
2. ❌ NO `Console.log` or `console.log` inside Effect.gen — use `yield* Effect.logInfo(...)` instead
3. ❌ NO `Effect.runPromise` inside services

---

## Reference Files

| File | Purpose |
|------|---------|
| `references/service-architecture.md` | 6-step pattern, Layer composition |
| `references/schema-data-modeling.md` | Branded types, TaggedErrorClass |
| `references/debugging-patterns.md` | floatingEffect, missing layers |
| `references/patterns-catalog.md` | Concurrency, streams, HTTP |
| `references/observability.md` | Effect.fn tracing, logging |
| `references/testing-guide.md` | @effect/vitest, TestClock |
| `references/code-review.md` | 12-point review pipeline |
| `references/lsp-integration.md` | CLI commands, quickfixes |
| `scripts/setup-lsp.sh` | LSP installation |
