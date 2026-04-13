# Effect-TS Debugging Patterns

Step-by-step workflows for diagnosing and fixing common Effect-TS issues.

## Quick Index

| # | Problem | Symptom |
|---|---------|---------|
| [1. Missing Service](#1-missing-service--layer-not-provided) | Layer not wired | `Type 'X' is not assignable to 'never'` in R channel |
| [2. Forgot yield*](#2-forgot-yield--got-effect-instead-of-value) | Missing `yield*` | Value is an Effect object, not unwrapped |
| [3. Type Narrowing](#3-type-narrowing-after-effectfail) | Narrowing lost after fail | TypeScript thinks variable undefined after guard |
| [4. Fiber Interrupted](#4-fiber-interrupted-unexpectedly) | Fiber dies early | Code stops mid-execution, no visible error |
| [5. Schema Decode Failure](#5-schema-decode-failure) | Invalid input | `Schema.decodeUnknown` throws |
| [6. Circular Layers](#6-circular-layer-dependencies) | Layer cycle | App hangs or stack overflow on startup |
| [7. Wrong Import](#7-effect-is-not-a-function--wrong-import) | Wrong import path | `Effect is not a function` |
| [8. Unhandled Defect](#8-unhandled-defect-die) | Defect reaches top | `Cause.Die` with stack trace |
| [9. Concurrency Issues](#9-concurrency-issues) | Race conditions | Data races, unbounded parallelism |
| [10. Fiber Repro Template](#10-minimal-reproduction-template-for-fiber-issues) | Debugging fibers | Minimal repro for fiber bugs |
| [11. Error Accumulation](#11-error-accumulation-parallel-operations) | Partial failures lost | Only first error reported |
| [12. match vs matchTag vs matchEffect](#12-match-vs-matchtag-vs-matcheffect--when-to-use-which) | Error handler confusion | Wrong handler for the situation |
| [13. Runtime vs Provide](#13-runtime-vs-provide--when-to-use-which) | Runtime choice | Which runtime pattern to use |
| [General Debugging Toolkit](#general-debugging-toolkit) | Spans, logging, Cause inspection | Visibility into running Effects |

## 1. Missing Service / Layer Not Provided

**Symptom:**
```
Type 'Effect<User, Error, Database>' is not assignable to type 'Effect<User, Error, never>'
  Type 'Database' is not assignable to type 'never'
```

**Diagnosis steps:**
1. Read the type error — the service name in the `R` position tells you what's missing
2. Trace backward to find where `Layer.provide` should wire it in
3. Check if the Layer exists but isn't composed into the final stack

**Fix (canonical Effect 4.x — ServiceMap.Service + Layer.provide):**
```ts
import { ServiceMap } from "effect"

// Add missing layer via provide
const fullLayer = layer.pipe(
  Layer.provide(Database.Default),
)
```

> **Legacy note:** `Context.Tag` is **FORBIDDEN** in Effect 4.x — it must never appear in new or migrated code. `Effect.Service` is legacy-compatible only. Use `ServiceMap.Service` + `Layer.provide` as the only canonical pattern.

**`Layer.provide` API — variadic arguments, NOT an array:**
```ts
// WRONG — array argument
Effect.runPromise(program.pipe(Layer.provide([layerA, layerB])))

// CORRECT — variadic
Effect.runPromise(program.pipe(Layer.provide(layerA, layerB)))

// For a dynamic list, use Layer.mergeAll first
const combined = Layer.mergeAll(layerA, layerB)
Effect.runPromise(program.pipe(Layer.provide(combined)))
```

## 2. Forgot yield* (Got Effect Instead of Value)

**Symptom:** TypeScript says a property doesn't exist, or value is an `Effect` object.

**Diagnosis:**
```ts
// Wrong — missing yield*
const user = getUser(id)
// user: Effect<User, UserError, Database>  ← still an Effect!

// Right
const user = yield* getUser(id)
// user: User  ← unwrapped value
```

**Rule:** Inside `Effect.gen`, every call to a function returning an `Effect` needs `yield*`.

## 3. Type Narrowing After Effect.fail

**Symptom:** TypeScript thinks a variable might be undefined after a guard that calls `Effect.fail`.

**Fix:** Use `return yield*` to signal exit:
```ts
if (!user) {
  return yield* Effect.fail(new UserNotFound({ id }))
}
user.name // Works! TypeScript knows we can't reach here
```

## 4. Fiber Interrupted Unexpectedly

**Symptom:** Code stops executing partway through with no visible error.

**Diagnosis steps:**
1. Check if effect runs inside a scope that might close early (`Effect.timeout`, `Effect.race`, `Effect.scoped`, parent fiber interrupted)
2. Check if `Effect.fork` was used without `Fiber.join`
3. Look for `Effect.disconnect` if you need the fiber to outlive its parent

**Fork vs forkScoped vs forkDaemon — When to Use Which:**

| Fork Type | Lifetime | Use When |
|-----------|---------|----------|
| `Effect.fork` | Tied to parent fiber | Short-lived, need result via `Fiber.join` |
| `Effect.forkScoped` | Tied to current scope | Background work that should end when scope closes |
| `Effect.forkDaemon` | outlives parent | Long-running daemon that must keep running |

```ts
// fork: tied to parent fiber lifecycle
const fiber = yield* Effect.fork(task)  // dies if parent dies

// forkScoped: tied to scope ( Effect.scoped, Stream.runForEach scope)
const fiber = yield* Effect.forkScoped(task)  // dies when scope closes

// forkDaemon: truly long-running
const fiber = yield* Effect.forkDaemon(task)  // outlives parent, YOU must interrupt
```

**Fixes:**
```ts
// If the work MUST complete:
yield* Effect.uninterruptible(criticalWork)

// If you need the fiber to outlive its scope:
yield* Effect.forkDaemon(backgroundTask)

// If you want to handle interruption gracefully:
yield* Effect.onInterrupt(myEffect, () => cleanup())
```

## 5. Schema Decode Failure

**Symptom:** Runtime error like "Expected string, got number".

**Diagnosis:** Schema decode errors are structured — they tell you exactly which field failed:
```ts
Schema.decodeUnknownSync(User)({ id: 123, age: "twenty" })
// Error tree shows:
//   id: expected string, got 123
//   age: expected number, got "twenty"
```

## 6. Circular Layer Dependencies

**Symptom:** Stack overflow or hang during layer construction.

**Fix:** Use `Layer.unwrap` to defer resolution:
```ts
const ALayer = Layer.unwrap(
  Effect.sync(() =>
    aImplementation.pipe(Layer.provide(BLayer)),
  ),
)
```

## 7. "Effect is not a function" / Wrong Import

**Diagnosis:**
- In Effect 4.x, most things import from `"effect"` barrel:
  ```ts
  import { Effect, Layer, Schema, Stream } from "effect"
  ```
- Some platform-specific modules use deep imports:
  ```ts
  import * as FileSystem from "effect/FileSystem"
  ```
- **Use the effect-docs MCP** (`effect_docs_search`) to verify the current API surface

## 8. Unhandled Defect (Die)

**Symptom:** `FiberFailure: Error: ...` with a stack trace pointing to `throw` or null dereference.

**Fix:** Replace `throw` with `Effect.fail`. Wrap external code with `Effect.try` or `Effect.tryPromise`:
```ts
// Wrong: throw becomes a defect
Effect.gen(function* () {
  throw new Error("oops") // ← defect
})

// Right: Effect.fail keeps it tracked
Effect.gen(function* () {
  return yield* Effect.fail(new MyError()) // ← in E channel
})

// Wrapping code that might throw:
Effect.try({
  try: () => JSON.parse(input),
  catch: (cause) => new ParseError({ cause }),
})
```

## 9. Concurrency Issues

### Unbounded Parallelism

**Symptom:** Memory spike, connection pool exhaustion, rate limit errors.

**Fix:** Use a bounded concurrency limit:
```ts
yield* Effect.all(tasks, { concurrency: 10 })
```

### Race Condition on Shared State

**Symptom:** Intermittent wrong values, non-deterministic test failures.

**Fix:** Use `SynchronizedRef` for atomic updates or `Semaphore` for mutual exclusion:
```ts
const sem = yield* Semaphore.make(1)
yield* sem.withPermits(1)(criticalSection)
```

## 10. Minimal Reproduction Template for Fiber Issues

When debugging fiber interruption issues, having a minimal reproduction helps isolate the problem:

```ts
import { Effect, Fiber, Cause, PubSub, Stream, Schedule, Scope } from "effect"

// Minimal repro template
const repro = Effect.gen(function* () {
  const pubsub = yield* PubSub.bounded<Event>({ capacity: 100 })

  // Subscribe and process
  const processStream = Stream.fromPubSub(pubsub).pipe(
    Stream.mapEffect((event) => processEvent(event), { concurrency: 10 }),
    Stream.groupedWithin(100, "5 seconds"),
    Stream.runForEach((batch) => writeBatch(batch)),
  )

  // Fork the processor
  const fiber = yield* Effect.forkScoped(processStream)

  // Publish some events
  yield* PubSub.publish(pubsub, { type: "test", data: "hello" })

  // Wait for processing
  yield* Effect.sleep("1 second")

  // Check fiber status
  const dump = yield* Fiber.dump(fiber)
  console.log("Fiber dump:", dump)

  return yield* Fiber.join(fiber)
}).pipe(Effect.scoped)

// To diagnose interruption:
repro.pipe(
  Effect.catchAllCause((cause) => {
    console.error("CAUSE:", Cause.pretty(cause))
    return Effect.fail(cause)
  }),
  Effect.runPromise
)
```

## General Debugging Toolkit

### Add Spans for Visibility
```ts
// On functions (preferred):
const myFn = Effect.fn("MyService.myFn")(function* () { ... })

// Add attributes:
yield* Effect.annotateCurrentSpan({ userId, action: "create" })
```

### Structured Logging
```ts
yield* Effect.logInfo("Processing user", { userId })
yield* Effect.logWarning("Retry attempt", { attempt: 3 })
yield* Effect.logError("Failed to connect", { host })
```

### Inspect Full Cause
```ts
program.pipe(
  Effect.catchAllCause((cause) => {
    console.error(Cause.pretty(cause))
    return Effect.fail(cause)
  }),
)
```

### Use Effect DevTools

The VS Code extension (`effectful-tech.effect-vscode`) with the Effect language service provides:
- Live fiber context inspection
- Span stack visualization
- Diagnostics for missing `yield*`, wrong Layer wiring
- Quick-fix refactors

### Consult the MCP

When stuck, use `effect_docs_search` to find current documentation on any API.

## 11. Error Accumulation (Parallel Operations)

When multiple parallel operations can fail, accumulate errors rather than failing on first:

```ts
// Accumulate all failures, succeed if any succeed
const results = yield* Effect.all(
  operations.map((op) => op.pipe(Effect.either)),
  { concurrency: 10 },
)

// Separate successes from failures
const [failures, successes] = results.partition(Either.isLeft)

if (failures.length > 0) {
  const errors = failures.map((e) => e.left).filter(Schema.isTransportError)
  yield* Effect.logWarning("Some operations failed", { errorCount: errors.length })
}

// Process successes
for (const success of successes) {
  yield* processResult(success.right)
}
```

### Using Cause.failures() for Hierarchical Introspection

```ts
Effect.catchAllCause((cause) => {
  // Inspect all failures in a Cause tree
  const failures = Cause.failures(cause)  // Array<Fail<E>>
  const defects = Cause.defects(cause)    // Array<Die<unknown>>
  const interrupts = Cause.interrupts(cause) // FiberRef values

  yield* Effect.logError("Operation failed", {
    failureCount: failures.length,
    defectCount: defects.length,
    cause: Cause.pretty(cause),
  })

  // Check specific error types
  const matching = failures.filter((f) => f.error._tag === "NetworkError")
  if (matching.length > 0) {
    return retryWithBackoff()
  }
  return Effect.fail(cause)
})
```

## 12. match vs matchTag vs matchEffect — When to Use Which

### match — Transform Both Channels
```ts
Effect.mapError(effect, (e) => new DomainError(e))
// or
Effect.match(effect, { onSuccess: (a) => a, onFailure: (e) => fallback })
```

### matchTag — Handle Specific Error Tags
```ts
yield* service.operation().pipe(
  Effect.matchTag({
    onNotFound: () => Effect.succeed(defaultValue),
    onUnauthorized: () => Effect.fail(new AuthError()),
    onConflict: (e) => Effect.succeed(mergeValues(existing, e.conflicting)),
  }),
)
```

### matchEffect — When You Need Effects in Handlers
```ts
yield* service.operation().pipe(
  Effect.matchEffect({
    onSuccess: (a) => Effect.succeed(a),
    onFailure: (e) =>
      e._tag === "RetryableError"
        ? retryOperation()
        : Effect.fail(e),
  }),
)
```

**Rule:** Prefer `matchTag` when handling discriminated errors — it's exhaustive and typed.

## 13. Runtime vs Provide — When to Use Which

### Effect.provide (Runtime Composition)
```ts
// provide wires layers at the boundary — use for application entry points
const program = myApp.pipe(
  Effect.provide(LiveLayer),
  Effect.provide(TracingLayer),
)
```
- Composes layers into a complete runtime
- Layers are merged in order (later layers override earlier)
- Best for: application entry points, test setup

### ManagedRuntime (Scoped Services)
```ts
// ManagedRuntime creates a reusable runtime with lifecycle management
const { runPromise, layers } = makeRuntime(Service, defaultLayer)

// Use when you need to:
// - Run multiple effects with the same layer stack
// - Manage scoped resources that need cleanup
// - Share runtime across multiple calls
```
- Keeps runtime alive across multiple calls
- Manages scoped resource lifecycles properly
- Best for: long-running services, HTTP handlers, test runners

### Scope — Manual Resource Management
```ts
// Use Scope directly for explicit resource scoping
yield* Effect.scope(scope => Effect.gen(function* () {
  const resource = yield* acquireResource()
  yield* Effect.addFinalizer(() => releaseResource(resource))
  return yield* process(resource)
}), Scope)
```
- Explicit scope management for complex scenarios
- `addFinalizer` for cleanup on scope close
- Best for: integration with external lifecycle systems
