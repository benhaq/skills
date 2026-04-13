# Scheduling Patterns

## Schedule Basics

### Spaced Repetition
```ts
// Repeat every hour
Effect.repeat(task, Schedule.spaced(Duration.hours(1)))
```

### Exponential Backoff
```ts
Effect.retry(task, { schedule: Schedule.exponential(Duration.seconds(1), 2) })
```

### Cron Expressions
```ts
// Run every day at midnight
Schedule.cron("0 0 * * *")

// Run every Monday at 9am
Schedule.cron("0 9 * * 1")

// Run every 15 minutes
Schedule.cron("*/15 * * * *")
```

## Background Task Patterns

### ForkDaemon with Schedule
```ts
// Long-running daemon that processes every hour
yield* work.pipe(
  Effect.repeat(Schedule.spaced(Duration.hours(1))),
  Effect.forkDaemon,
)
```

### Cron with Jitter (Thundering Herd Prevention)
```ts
// Add jitter to prevent all workers running at the same moment
Schedule.cron("0 * * * *").pipe(Schedule.jittered)
```

## Retry Patterns

### Retry with Max Attempts
```ts
Effect.retry(task, {
  schedule: Schedule.recurs(3).pipe(
    Schedule.compose(Schedule.exponential(Duration.millis(100))),
  ),
})
```

### Retry with Timeout
```ts
Effect.retry(task, {
  schedule: Schedule.elapsed.pipe(Schedule.whileOutput((ms) => ms < 5000)),
})
```

## Provider-Aware Retry

> **⚠️ Verification required** — `Schedule.fromStepWithMetadata` API shape unverified. Verify before use.

```ts
// Conceptual sketch — API may differ. Verify with Context7 MCP:
// mcp__context7__query-docs({ libraryId: "effect-ts", query: "Schedule retry with metadata" })
const retryPolicy = Schedule.fromStepWithMetadata(Effect.succeed((meta) => {
  const error = parseError(meta.input)
  if (!isRetryable(error)) return Cause.done(meta.attempt)
  return Effect.gen(function* () {
    const wait = getDelay(meta.attempt, error)
    return [meta.attempt, Duration.millis(wait)]
  })
}))

Effect.retry(task, { schedule: retryPolicy })
```
