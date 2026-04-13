# Effect Language Service Integration

**CLI quick reference:**
```bash
# Diagnostics (70+ Effect checks) — requires --project flag for TS resolution
# Full project scan (recommended):
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json

# Single file:
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --file src/x.ts --project tsconfig.json

# Or with shell alias:
# alias effect-diags="NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics"
# effect-diags --project tsconfig.json

# Auto-fix suggestions
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js quickfixes --file src/x.ts --code floatingEffect

# Effect exports overview
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js overview --project tsconfig.json

# Layer dependency analysis
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js layerinfo --file src/x.ts --name defaultLayer

# Regenerate @effect-codegens
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js codegen

# Interactive setup
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js setup
```

> **Important:** Always use `NODE_PATH=./node_modules` AND `--project tsconfig.json` when running the CLI directly. Without `--project`, TypeScript's module resolution doesn't know where to find `typescript/lib/tsserverlibrary` — causing `Cannot find module 'typescript/lib/tsserverlibrary'`. The `--project` flag enables proper TS resolution from your project.
>
> **Verification loop:** After running diagnostics, re-verify with `bun tsc --noEmit` and `bun test` before presenting results.

## Quick Index

| Section | When to Read |
|---------|--------------|
| [Setup & Installation](#setup--installation) | First-time setup, installing language service |
| [Diagnostic Reference](#diagnostic-reference) | Lookup specific diagnostic codes and meanings |
| [Diagnostic-to-Fix Map](#diagnostic-to-fix-map) | `floatingEffect`, `missingYieldStar`, `classSelfMismatch`, etc. — fixes per code |
| [Code Generation Directives](#code-generation-directives) | Inline LSP directives, CLI usage |
| [Agent Verification Workflow](#agent-verification-workflow) | The full loop: diagnostics → typecheck → test → present |
| [Fallback When CLI Is Not Available](#fallback-when-cli-is-not-available) | Manual diagnostic interpretation |

## Setup & Installation

Install the language service as a dev dependency:

```bash
bun add --dev @effect/language-service
```

### tsconfig.json Plugin Configuration

Add the plugin to your `compilerOptions.plugins` array with diagnostic severity tuning:

```jsonc
{
  "compilerOptions": {
    "plugins": [
      {
        "name": "@effect/language-service",
        // Correctness — these are bugs, treat as errors
        "floatingEffect": "error",
        "missingYieldStar": "error",
        "classSelfMismatch": "error",
        "multipleEffectVersions": "error",
        // Anti-patterns — not bugs, but lead to bugs
        "tryCatchInGenerator": "warning",
        "effectInFailure": "warning",
        "multipleEffectProvide": "warning",
        "layerMergeAllWithDependencies": "warning",
        "deterministicKeys": "warning",
        // Effect-native preference — use Effect APIs instead
        "asyncFunction": "suggestion",
        "globalConsole": "suggestion",
        "globalFetch": "suggestion",
        "globalDate": "suggestion",
        "processEnv": "suggestion",
        "nodeBuiltinImport": "suggestion",
        "globalFetchInEffect": "suggestion",
        // Style — cleaner code
        "unnecessaryEffectGen": "suggestion",
        "missedPipeableOpportunity": "suggestion",
        "redundantSchemaTagIdentifier": "suggestion",
        "catchOnNonFailingEffect": "suggestion",
        // Features
        "completions": true,
        "quickinfo": true,
        "refactors": true,
        "namespaceImportPackages": ["effect"]
      }
    ]
  }
}
```

### Editor Setup

| Editor | Setup |
|--------|-------|
| VS Code / Cursor | Install the Effect extension, or set `"typescript.tsserver.pluginPaths"` in settings.json |
| Zed / NeoVim | Use the TypeScript language server — the tsconfig plugin loads automatically |
| Emacs (lsp-mode / eglot) | Point `lsp-typescript` at the workspace tsconfig; plugin loads via tsserver |

### Build-Time Diagnostics

The language service runs inside tsserver (editor only). To surface diagnostics in CI:

```bash
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js patch
```

Add a prepare script so it patches automatically after install:

```jsonc
{
  "scripts": {
    "prepare": "effect-language-service patch"
  }
}
```

This patches the local TypeScript installation so `tsc` reports Effect diagnostics alongside normal type errors.

## Diagnostic Reference

### Correctness (error / warning)

| Diagnostic | Severity | What It Catches |
|------------|----------|-----------------|
| `floatingEffect` | error | An Effect expression whose result is ignored — almost always a bug |
| `missingYieldStar` | error | Assigning an Effect to a variable without `yield*` — value is still wrapped |
| `classSelfMismatch` | error | `ServiceMap.Service<WrongClass, ...>` — the self-type parameter doesn't match the class |
| `multipleEffectVersions` | error | Two copies of `effect` in node_modules — causes runtime identity mismatches |
| `extendsNativeError` | warning | A class extending `Error` instead of `Schema.TaggedErrorClass` |
| `missingEffectError` | warning | An `Effect.gen` body that can throw but has `never` in the error channel |
| `missingEffectContext` | warning | A service dependency used but not reflected in the context type |

### Anti-Patterns (warning)

| Diagnostic | What It Catches |
|------------|-----------------|
| `tryCatchInGenerator` | `try/catch` inside `Effect.gen` — bypasses the Effect error channel |
| `effectInFailure` | `Effect.fail(Effect.log(...))` — passing an Effect where a plain value is expected |
| `multipleEffectProvide` | Chained `.pipe(Effect.provide(A), Effect.provide(B))` — merge layers instead |
| `layerMergeAllWithDependencies` | `Layer.mergeAll` including a layer that depends on another in the same merge |
| `deterministicKeys` | Non-deterministic keys in records passed to Effect APIs |

### Effect-Native Preference (suggestion)

| Diagnostic | Replace With |
|------------|-------------|
| `asyncFunction` | `Effect.fn("Name")(function* (...) { ... })` |
| `globalConsole` | `Effect.logInfo` / `Effect.logDebug` / `Effect.logError` |
| `globalFetch` | `HttpClient.HttpClient` service |
| `globalDate` | `Clock.Clock` service |
| `processEnv` | `Config.string("KEY")` / `Config.secret("KEY")` |
| `nodeBuiltinImport` | `@effect/platform` services (`FileSystem`, `Path`, etc.) |
| `globalFetchInEffect` | `HttpClient.HttpClient` inside an Effect context |

### Style (suggestion)

| Diagnostic | What It Catches |
|------------|-----------------|
| `unnecessaryEffectGen` | `Effect.gen(function* () { return yield* x })` — just use `x` directly |
| `missedPipeableOpportunity` | Nested calls that read better as `.pipe(...)` chains |
| `redundantSchemaTagIdentifier` | `Schema.TaggedErrorClass<Foo>()("Foo", ...)` where the tag matches the class name and can be omitted |
| `catchOnNonFailingEffect` | `.pipe(Effect.catchAll(...))` on an Effect that cannot fail |

## Diagnostic-to-Fix Map

### `floatingEffect`

A function call that returns an Effect but whose result is silently discarded.

```ts
// BEFORE
Effect.gen(function* () {
  userService.validate(input) // floating — result ignored
  const user = yield* userService.create(input)
})

// AFTER
Effect.gen(function* () {
  yield* userService.validate(input)
  const user = yield* userService.create(input)
})
```

### `missingYieldStar`

Assigning an Effect to a variable without unwrapping it.

```ts
// BEFORE
const user = getUser(id) // still Effect<User, ...>

// AFTER
const user = yield* getUser(id) // unwrapped User
```

### `classSelfMismatch`

The self-type parameter in `ServiceMap.Service` doesn't match the enclosing class.

```ts
// BEFORE
class UserService extends ServiceMap.Service<AuthService, Interface>()("@app/UserService") {}
//                                           ^^^^^^^^^^^ doesn't match class

// AFTER
class UserService extends ServiceMap.Service<UserService, Interface>()("@app/UserService") {}
```

### `extendsNativeError`

A class extending native `Error` instead of using Effect's tagged error system.

```ts
// BEFORE
class MyError extends Error {
  constructor(public message: string) {
    super(message)
  }
}

// AFTER
class MyError extends Schema.TaggedErrorClass<MyError>()("MyError", {
  message: Schema.String,
}) {}
```

### `tryCatchInGenerator`

Using `try/catch` inside `Effect.gen` bypasses the Effect error channel entirely.

```ts
// BEFORE
Effect.gen(function* () {
  try {
    const data = yield* fetchData()
  } catch (e) {
    console.error(e)
  }
})

// AFTER
Effect.gen(function* () {
  const data = yield* fetchData().pipe(
    Effect.catchTag("FetchError", (e) =>
      Effect.gen(function* () {
        yield* Effect.logError("Fetch failed")
        return yield* Effect.fail(new ProcessingError({ cause: e }))
      })
    )
  )
})
```

### `multipleEffectProvide`

Chaining multiple `Effect.provide` calls instead of merging layers.

```ts
// BEFORE
program.pipe(
  Effect.provide(LayerA),
  Effect.provide(LayerB),
  Effect.provide(LayerC),
)

// AFTER
const AppLayer = Layer.mergeAll(LayerA, LayerB, LayerC)
program.pipe(Effect.provide(AppLayer))
```

### `effectInFailure`

Passing an Effect expression where `Effect.fail` expects a plain error value.

```ts
// BEFORE
Effect.fail(Effect.log("something failed"))

// AFTER
Effect.gen(function* () {
  yield* Effect.log("something failed")
  return yield* Effect.fail(new MyError({ reason: "something failed" }))
})
```

### `asyncFunction`

An `async/await` function that should be expressed as an Effect.

```ts
// BEFORE
async function getUser(id: string) {
  const res = await fetch(`/api/users/${id}`)
  return res.json()
}

// AFTER
const getUser = Effect.fn("getUser")(function* (id: string) {
  const client = yield* HttpClient.HttpClient
  return yield* client.get(`/api/users/${id}`).pipe(
    Effect.flatMap(HttpClientResponse.schemaBodyJson(User)),
  )
})
```

### `globalConsole`

Using `console.log` instead of Effect's structured logging.

```ts
// BEFORE
console.log("User created:", userId)

// AFTER
yield* Effect.logInfo("User created", { userId })
```

### `processEnv`

Accessing `process.env` directly instead of using Effect's Config system.

```ts
// BEFORE
const apiKey = process.env.API_KEY!

// AFTER
const apiKey = yield* Config.string("API_KEY")
```

### `nodeBuiltinImport`

Importing Node.js built-in modules instead of using `@effect/platform` services.

```ts
// BEFORE
import fs from "node:fs"
const content = fs.readFileSync("config.json", "utf-8")

// AFTER
import { FileSystem } from "@effect/platform"
const fs = yield* FileSystem.FileSystem
const content = yield* fs.readFileString("config.json")
```

### `unnecessaryEffectGen`

Wrapping a single `yield*` in `Effect.gen` when the inner effect can be used directly.

```ts
// BEFORE
const result = Effect.gen(function* () {
  return yield* someEffect
})

// AFTER
const result = someEffect
```

## Code Generation Directives

The language service supports inline code generation via special comments.

### Inline Directives

```ts
// @effect-codegens annotate
// Auto-generate type annotations for Effect expressions

// @effect-codegens accessors
// Implement service accessors from interface definition

// @effect-codegens typeToSchema
// Convert a TypeScript interface into an Effect Schema declaration
```

Place the directive comment directly above the target declaration. The language service will offer a code action to expand it.

### CLI Usage

Run code generation from the command line:

```bash
# Process a single file
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js codegens --file src/services/UserService.ts

# Process the entire project
NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js codegens --project tsconfig.json
```

## Agent Verification Workflow

### Verification Loop

When generating or modifying Effect code, follow this cycle:

1. **Write** — generate the code
2. **Diagnostics** — run `NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json`
3. **Fix** — resolve any reported issues using the diagnostic-to-fix map above
4. **Re-verify diagnostics** — confirm zero remaining diagnostics
5. **Typecheck** — run `bun tsc --noEmit` to confirm type correctness
6. **Test** — run `bun test` to confirm runtime behavior
7. **Present** — deliver the code with a verification note

### Verification Note Format

After confirming clean diagnostics, typecheck, and tests, include:

```
Verified:
- 0 Effect Language Service diagnostics in <file>
- bun tsc --noEmit passed
- bun test passed
```

If diagnostics remain intentionally (e.g., a `globalConsole` in a CLI entry point), note the exception:

```
Verified: 1 Effect Language Service diagnostic in <file> (globalConsole in CLI entry point — intentional).
```

### Fallback When CLI Is Not Available

When `@effect/language-service` is not installed, **always prompt the user first:**

> "@effect/language-service is not installed. Install it for 70+ automated Effect checks:
> `bun add --dev @effect/language-service`
> Or run: `bash skills/effect/scripts/setup-lsp.sh`"

If the user declines or installation isn't possible (CI, remote editing), use manual checks:

1. Manually check for floating effects — every Effect-returning call inside `Effect.gen` must be `yield*`-ed or explicitly `void`-ed
2. Verify no `try/catch` inside `Effect.gen` bodies
3. Confirm `ServiceMap.Service<Self, ...>` self-type matches the class name
4. Check that errors extend `Schema.TaggedErrorClass`, not native `Error`
5. Look for chained `Effect.provide` calls that should be `Layer.mergeAll`
6. Flag `process.env`, `console.log`, `async function` for migration

### LSP Refactoring Suggestions

The language service also provides refactoring actions:

| Refactoring | Trigger |
|-------------|---------|
| Wrap in `Effect.gen` | Selecting an expression that returns an Effect |
| Extract to service method | Selecting a block inside a Layer implementation |
| Convert `async` to `Effect.fn` | Cursor on an `async function` declaration |
| Inline `Effect.gen` | Cursor on an unnecessary `Effect.gen` wrapper |
| Add `yield*` | Cursor on a floating Effect expression |
| Merge `Effect.provide` calls | Cursor on chained `.pipe(Effect.provide(...))` |
