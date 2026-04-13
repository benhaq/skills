# Patterns Catalog

Detailed examples of every major Effect-TS pattern used in production.

> **Keep Examples Lean:** When generating code, only include what the prompt asks for. Optional dependencies (Logger, Clock, Schema if not needed) should be omitted or mentioned in comments. Extra code adds complexity without value.
>
> **Snippet reliability:** Most snippets here are **conceptual sketches** showing the pattern shape — undefined symbols (like `Config`, `Database`, `log`) are placeholders you'll replace with your actual services. API-heavy snippets (Pool, Cache, Semaphore) use real Effect APIs.

## Quick Index

| Section | When to Read |
|---------|--------------|
| [Generator Composition](#generator-composition) | Writing services with `yield*` |
| [Concurrency Primitives](#concurrency-primitives) | Deferred, SynchronizedRef, Semaphore, Fiber, Cache, Pool |
| [Streams](#streams) | PubSub, async iterables, pipelines |
| [Resource Management](#resource-management) | acquireRelease, addFinalizer, scoped |
| [HTTP Client](#http-client) | HttpClient with schema decoding |
| [Child Processes](#child-processes) | Spawning and streaming subprocess output |
| [Retry & Scheduling](#retry--scheduling) | Schedules, cron, periodic work, retry |
| [State Machines](#state-machines) | SynchronizedRef + Deferred + Fiber |
| [Racing Signals](#racing-signals) | Race multiple exit conditions |

## Generator Composition

`Effect.gen` + `yield*` is the universal composition style:
```ts
// Conceptual sketch — replace Config.Service, Database.Service with your actual services
const process = Effect.gen(function* (input: Input) {
  const config = yield* Config.Service
  const db = yield* Database.Service
  const user = yield* db.findById(input.userId)
  const result = transform(user, config)
  yield* db.save(result)
  return result
})
```

## Concurrency Primitives

### Deferred — One-Shot Promise Bridge
```ts
// Conceptual sketch — replace pendingRequests, bus, PermissionAsked with your actual types
import { Deferred, Effect } from "effect"

const deferred = yield* Deferred.make<void, RejectedError>()
pendingRequests.set(id, deferred)
yield* bus.publish(PermissionAsked, info)
return yield* Effect.ensuring(Deferred.await(deferred), Effect.sync(() => pendingRequests.delete(id)))
```

### SynchronizedRef — Atomic State Transitions
```ts
// Conceptual sketch — verify SynchronizedRef.make/makeUnsafe API in Effect 4.x
import { SynchronizedRef, Effect, Fiber } from "effect"

interface State { _tag: "Idle" } | { _tag: "Running"; fiber: Fiber.Fiber<unknown> }
const ref = SynchronizedRef.makeUnsafe<State>({ _tag: "Idle" })
```

### Semaphore — Mutex for Resources
```ts
// Conceptual sketch — verify Semaphore API in Effect 4.x
import { Semaphore } from "effect"

const locks = new Map<string, Semaphore>()
const locked = (key: string, fx: Effect.Effect<A, E, R>) =>
  locks.get(key)?.withPermits(1)(fx) ?? fx
```

### Fiber — Background Work
```ts
yield* backgroundTask.pipe(
  Effect.repeat(Schedule.spaced(Duration.hours(1))),
  Effect.delay(Duration.minutes(1)),
  Effect.forkScoped,
)
```

### RcMap + TxReentrantLock — Per-Key Locks
```ts
// Conceptual sketch — verify RcMap/TxReentrantLock API in Effect 4.x
```

### Cache — TTL Memoization
```ts
// Conceptual sketch — replace fetchData with your actual lookup function
import { Cache, Duration, Effect } from "effect"

const cache = yield* Cache.make({ capacity: 100, timeToLive: Duration.minutes(5), lookup: fetchData })
```

### Pool with TTL — Connection Pooling

> **⚠️ API verification required** — Pool constructor API may differ. Use Context7 MCP to verify.

Correct pattern uses `Layer.scoped` + `Effect.acquireRelease`:
```ts
import { Pool } from "@effect/platform"

// Create a scoped pool layer
const DatabasePoolLayer = Layer.scoped(
  Pool.Pool,
  Effect.acquireRelease(
    Effect.tryPromise(() => db.connect()),
    (conn) => conn.end(),
  ).pipe(
    Effect.map((conn) =>
      Pool.make({
        acquire: Effect.succeed(conn),
        release: (c) => c.end(),
        size: 10,
      })
    ),
  ),
)
```

Or use `Effect.pool` utilities — verify exact API with `mcp__context7__query-docs`.

## Streams

### From PubSub (Event Subscriptions)
```ts
// Conceptual sketch — replace getPubSub, EventDef, Payload, log with your actual types
import { Stream, Effect } from "effect"

function subscribe<D extends EventDef>(def: D): Stream.Stream<Payload<D>> {
  return Stream.unwrap(Effect.gen(function* () {
    const pubsub = yield* getPubSub(def)
    return Stream.fromPubSub(pubsub)
  })).pipe(Stream.ensuring(Effect.sync(() => log.info("unsubscribing"))))
}
```

### From Async Iterables (LLM Token Streaming)
```ts
// Conceptual sketch — replace LLM with your actual streaming client
import { Stream, Effect } from "effect"

const stream = Stream.scoped(Stream.unwrap(Effect.gen(function* () {
  const ctrl = yield* Effect.acquireRelease(
    Effect.sync(() => new AbortController()),
    (ctrl) => Effect.sync(() => ctrl.abort()),
  )
  const result = yield* Effect.promise(() => LLM.stream({ prompt, abort: ctrl.signal }))
  return Stream.fromAsyncIterable(result.fullStream, (e) => new Error(String(e)))
})))
```

### Processing Pipeline
```ts
yield* eventStream.pipe(
  Stream.tap((event) => handleEvent(event)),
  Stream.takeUntil(() => shouldStop),
  Stream.runDrain,
)
```

## Event Bus (PubSub)

// Conceptual sketch — implement with your PubSub/service infrastructure
// A complete event bus with wildcard + typed subscriptions, scope lifecycle, and finalizers.

## Resource Management

### acquireRelease — Scoped Resources
```ts
const conn = yield* Effect.acquireRelease(
  Effect.tryPromise(() => db.connect()),
  (conn) => Effect.tryPromise(() => conn.close()).pipe(Effect.ignore),
)
```

### addFinalizer — Cleanup on Scope Close
```ts
// Conceptual sketch — replace PubSub, state with your actual services
import { Effect, PubSub } from "effect"

yield* Effect.addFinalizer(() => Effect.gen(function* () {
  yield* PubSub.shutdown(pubsub)
  state.pending.clear()
}))
```

### Effect.scoped — Collapse Scope
```ts
// Conceptual sketch — replace spawner, command, processChunk with your actual values
import { Effect, Stream, ChildProcess } from "effect"

const result = yield* Effect.gen(function* () {
  const handle = yield* spawner.spawn(command)
  yield* Effect.forkScoped(Stream.runForEach(handle.stdout, processChunk))
  return yield* handle.exitCode
}).pipe(Effect.scoped, Effect.orDie)
```

## HTTP Client

```ts
const http = (yield* HttpClient.HttpClient).pipe(HttpClient.mapRequest(HttpClientRequest.acceptJson))
const httpOk = http.pipe(HttpClient.filterStatusOk)

const result = yield* HttpClientRequest.post(url).pipe(
  HttpClientRequest.schemaBodyJson(RequestSchema)(data),
  Effect.flatMap((req) => httpOk.execute(req)),
  HttpClientResponse.schemaBodyJson(ResponseSchema),
)
```

## Child Processes

```ts
// Conceptual sketch — verify @effect/platform ChildProcessSpawner API
import { Stream } from "effect"

const spawner = yield* ChildProcessSpawner
const handle = yield* spawner.spawn(ChildProcess.makeCommand("git", "status", "--porcelain"))
const output = yield* Stream.mkString(Stream.decodeText(handle.stdout))
const exitCode = yield* handle.exitCode
```

## Retry & Scheduling

### Provider-Aware Retry
```ts
// Conceptual sketch — verify Schedule.exponential + retry against Effect 4.x docs
import { Effect, Schedule, Cause, Duration, Clock } from "effect"

const retryPolicy = Schedule.exponential(Duration.millis(100)).pipe(
  Schedule.compose(Schedule.recurs(3)),
  Schedule.jittered,
)

const program = Effect.gen(function* () {
  // ... your Effect code here
}).pipe(
  Effect.retry(retryPolicy),
  Effect.catchAll((e) => Effect.succeed(`Fallback after retries: ${e}`)),
)
```

### Periodic Background Work
```ts
// Conceptual sketch — replace log with your Logger service
yield* cleanup().pipe(
  Effect.catchCause((cause) => Effect.logError(`cleanup failed: ${Cause.pretty(cause)}`)),
  Effect.repeat(Schedule.spaced(Duration.hours(1))),
  Effect.delay(Duration.minutes(1)),
  Effect.forkScoped,
)
```

### Cron-Based Scheduling
```ts
// Run every day at midnight
yield* dailyTask.pipe(
  Effect.repeat(Schedule.cron("0 0 * * *")),
  Effect.forkScoped,
)

// Run every Monday at 9am
yield* weeklyReport.pipe(
  Effect.repeat(Schedule.cron("0 9 * * 1")),
  Effect.forkScoped,
)

// Cron with jitter to prevent thundering herd
yield* scheduledTask.pipe(
  Effect.repeat(Schedule.cron("0 * * * *").pipe(Schedule.jittered)),
  Effect.forkScoped,
)
```

## State Machines

// Conceptual sketch — implement using SynchronizedRef + Deferred + Fiber for atomic state transitions.
// See SynchronizedRef section above for the pattern shape.

## Racing Signals

```ts
const exit = yield* Effect.raceAll([
  handle.exitCode.pipe(Effect.map((code) => ({ kind: "exit" as const, code }))),
  abortSignal.pipe(Effect.map(() => ({ kind: "abort" as const, code: null }))),
  timeoutSignal.pipe(Effect.map(() => ({ kind: "timeout" as const, code: null }))),
])
```
