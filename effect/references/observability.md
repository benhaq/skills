# Observability

## Effect.fn Creates Automatic Spans

`Effect.fn("Name")` creates a span for every invocation:
```ts
const findById = Effect.fn("UserService.findById")(function* (id: UserID) {
  yield* Effect.annotateCurrentSpan("userId", id)
  return yield* db.query("SELECT * FROM users WHERE id = ?", [id])
})
```

### Span Naming Convention

Follow `ServiceName.methodName` format:
- `UserService.findById`
- `Database.query`
- `AuthService.refreshToken`

### What to Annotate

```ts
// GOOD — entity IDs, actions, discriminators, counts
yield* Effect.annotateCurrentSpan("userId", userId)
yield* Effect.annotateCurrentSpan("action", "create")
yield* Effect.annotateCurrentSpan("resultCount", results.length)

// BAD — PII, secrets, large payloads
yield* Effect.annotateCurrentSpan("email", email)
yield* Effect.annotateCurrentSpan("apiKey", apiKey)
yield* Effect.annotateCurrentSpan("body", JSON.stringify(req))
```

## Structured Logging (Production)

For production observability with structured fields and span integration:
```ts
yield* Effect.logDebug("Cache miss", { key })
yield* Effect.logInfo("User created", { userId: user.id })
yield* Effect.logWarning("Rate limit approaching", { remaining: 5 })
yield* Effect.logError("Payment failed", { orderId, reason })
```

### Annotate Logs with Context
```ts
yield* Effect.annotateLogs({ requestId, sessionId })(
  Effect.gen(function* () {
    yield* Effect.logInfo("Processing request")
    // All logs in this scope include requestId and sessionId
  }),
)
```

### Disable Logging in Tests
```ts
import { Logger, LogLevel } from "effect"

const TestLayer = Layer.mergeAll(UserService.layer, Logger.minimumLogLevel(LogLevel.None))
```

## OpenTelemetry Integration

```ts
import { NodeSdk } from "@effect/opentelemetry"
import { BatchSpanProcessor, ConsoleSpanExporter } from "@opentelemetry/sdk-trace-base"

const TracingLayer = NodeSdk.layer(() => ({
  resource: { serviceName: "my-app" },
  spanProcessor: new BatchSpanProcessor(new ConsoleSpanExporter()),
}))

const program = myApp.pipe(Effect.provide(TracingLayer))
```

## Structured Logging vs Simple Console Output

Effect provides two logging mechanisms inside `Effect.gen`:

### `Console.log` — Simple Output (Most Common)
```ts
import { Effect, Console } from "effect"

const program = Effect.gen(function* () {
  const user = yield* Effect.succeed({ name: "Alice", id: 1 })
  yield* Console.log(`Processing user: ${user.name}`)  // ✅ Simple console output
  return user
})
```

### `Effect.logInfo` — Structured Production Logging
```ts
import { Effect } from "effect"

const program = Effect.gen(function* () {
  yield* Effect.logInfo("User created", { userId: user.id })  // ✅ Structured with spans
  yield* Effect.annotateCurrentSpan("userId", user.id)
  return user
})
```

**When to use which:**
- `Console.log` — tests, dev scripts, simple output (most common)
- `Effect.logInfo` — production observability with structured fields and span annotations

### FORBIDDEN: new Date() / Date.now()
```ts
// WRONG — non-deterministic, untestable
const now = Date.now()

// CORRECT — use Clock for determinism
const now = yield* Clock.currentTimeMillis
```

### FORBIDDEN: step counters in spans
```ts
// WRONG — noise
yield* Effect.annotateCurrentSpan("step", "3")

// CORRECT — meaningful attributes
yield* Effect.annotateCurrentSpan("retryCount", 3)
```

## Error Observability

```ts
program.pipe(
  Effect.catchAllCause((cause) => {
    yield* Effect.logError("Operation failed", { cause: Cause.pretty(cause) })
    return Effect.fail(cause)
  }),
)
```

## Metrics with Metric.histogram

Track distributions of values (latencies, request sizes, etc.):

```ts
import { Metric, MetricState } from "effect"

// Define metrics at module level
const requestLatency = Metric.histogram("http_request_latency_ms", {
  bins: [10, 50, 100, 250, 500, 1000, 2500, 5000],
  description: "HTTP request latency in milliseconds",
})

const requestSize = Metric.histogram("http_request_size_bytes", {
  bins: [100, 1024, 10240, 102400],
  description: "HTTP request body size in bytes",
})

// Record measurements
const trackLatency = (latencyMs: number) =>
  requestLatency.record(latencyMs)

const trackRequestSize = (sizeBytes: number) =>
  requestSize.record(sizeBytes)

// Use in an HTTP service
const httpService = Effect.fn("HttpService.request")(function* (req: Request) {
  const start = yield* Clock.currentTimeMillis
  const result = yield* executeRequest(req)
  const latency = yield* Clock.currentTimeMillis.pipe(Effect.map((end) => end - start))
  yield* trackLatency(latency)
  yield* trackRequestSize(req.body.length)
  return result
})
```

### Percentile Metrics

```ts
import { Metric, MetricState } from "effect"

// P95/P99 tracking via custom bins
const p99Latency = Metric.histogram("p99_latency_ms", {
  bins: [50, 100, 200, 300, 500, 1000, 2000, 5000],
})

// Record with exact value
const recordP99 = (ms: number) => p99Latency.record(ms)
```
