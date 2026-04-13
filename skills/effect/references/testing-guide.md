# Testing Guide

## @effect/vitest

Always use `@effect/vitest` — never plain `vitest`.

## it.effect — The Standard Test Pattern

`it.effect` manages `Scope` for resource cleanup and is the canonical Effect 4.x test pattern:
```ts
describe("UserService", () => {
  it.effect("creates a user successfully", () =>
    Effect.gen(function* () {
      const service = yield* UserService
      const user = yield* service.create({ name: "Alice", email: "a@b.com" })
      assert.strictEqual(user.name, "Alice")
    }).pipe(Effect.provide(TestLayer)),
  )
})
```

## it.layer — Shared Test Setup

Use `it.layer(TestLayer)` to provide services once for an entire describe block:
```ts
const TestLayer = Layer.mergeAll(MockDatabase.Test, MockBus.Test, UserService.defaultLayer)

it.layer(TestLayer)((it) => {
  describe("UserService", () => {
    it.effect("creates a user", () =>
      Effect.gen(function* () {
        const service = yield* UserService
        const user = yield* service.create({ name: "Alice", email: "a@b.com" })
        assert.strictEqual(user.name, "Alice")
      }),
    )
  })
})
```

## Mocking Services via Layers

Replace dependencies at the layer level — no mocking libraries needed:

```ts
const MockDatabase = Layer.succeed(
  Database.Service,
  Database.Service.of({ query: () => Effect.succeed([]), execute: () => Effect.succeed(undefined) }),
)

const testLayer = UserService.layer.pipe(Layer.provide(MockDatabase))
```

## Mocking Config

For testing services that depend on `Config`:

```ts
import { Config } from "effect"

// Correct: provide a layer that supplies Config
const TestConfigLayer = Layer.succeed(
  Config.Config,
  Config.of({ API_KEY: "test-key" }),
)

// Better: use Layer.effect + Config to resolve at runtime
const TestConfigLayer = Layer.effect(
  Config.Config,
  Effect.sync(() => ({ API_KEY: "test-key" })),
)

// Testing missing config: use Layer.fail for the Config aspect
// Note: Config.fail is NOT the same as Layer.fail — config failures
// happen at Effect build time, not runtime
```

**Anti-pattern — `Layer.fail(Config.Config, ...)` does NOT simulate missing config:**
```ts
// WRONG — Layer.fail creates a layer that fails immediately,
// not a config that fails when requested
const WrongFailLayer = Layer.fail(Config.Config, new Error("missing"))

// CORRECT — use Config_secret with a dummy value and test
// the actual missing-config path by providing an empty provider
```

## Error Testing with Effect.either

Never use `try/catch` in Effect tests:
```ts
it.effect("fails for missing user", () =>
  Effect.gen(function* () {
    const result = yield* UserService.get(invalidId).pipe(Effect.either)
    assert.isTrue(Either.isLeft(result))
    if (Either.isLeft(result)) {
      assert.strictEqual(result.left._tag, "UserNotFoundError")
    }
  }),
)
```

## Testing with Effect.flip

Put the error in the success channel for easier assertion:
```ts
it.effect("fails with correct error", () =>
  Effect.gen(function* () {
    const error = yield* service.get(invalidId).pipe(Effect.flip)
    assert.strictEqual(error._tag, "UserNotFoundError")
  }),
)
```

## TestClock — Deterministic Time

```ts
import { TestClock, Fiber } from "effect"

it.effect("retries after delay", () =>
  Effect.gen(function* () {
    const fiber = yield* Effect.fork(operationWithRetry)
    yield* TestClock.adjust("5 seconds")
    const result = yield* Fiber.join(fiber)
    assert.strictEqual(result, "success")
  }),
)
```

## Property-Based Testing with it.prop

```ts
it.prop("never produces negative totals", {
  price: Schema.Number.pipe(Schema.positive()),
  quantity: Schema.Int.pipe(Schema.positive()),
}, ({ price, quantity }) =>
  Effect.gen(function* () {
    const total = yield* calculateTotal(price, quantity)
    assert(total >= 0)
  }),
)
```

## Error Accumulation Testing

When testing batch operations that can have partial failures:

```ts
import { Chunk, Either } from "effect"

it.effect("accumulates errors from failed operations", () =>
  Effect.gen(function* () {
    const results = yield* Effect.all(
      [op1, op2, op3].map((op) => op.pipe(Effect.either)),
      { concurrency: 3 },
    )

    const failures = Chunk.filter(results, Either.isLeft)
    const successes = Chunk.filter(results, Either.isRight)
    assert.strictEqual(Chunk.size(successes), 2)
    assert.strictEqual(Chunk.size(failures), 1)
  }),
)
```

## TestClock for Scheduled Tasks

```ts
it.effect("retries on schedule", () =>
  Effect.gen(function* () {
    // Fork the operation (it will retry)
    const fiber = yield* Effect.fork(retryingOperation)

    // Advance clock past retry intervals
    yield* TestClock.adjust(Duration.minutes(1))

    // Check result
    const result = yield* Fiber.join(fiber)
    assert(result._tag === "Success")
  }),
)
```

## Testing with MockLayer

For services with multiple dependencies:

```ts
const MockServices = Layer.mergeAll(
  Layer.succeed(Database.Service, Database.Service.of({ query: () => Effect.succeed([]) })),
  Layer.succeed(Cache.Service, Cache.Service.of({ get: () => Effect.none() })),
  Logger.minimumLogLevel(LogLevel.None),
)

it.layer(MockServices)((it) => {
  describe("UserService", () => {
    it.effect("finds user by id", () =>
      Effect.gen(function* () {
        const service = yield* UserService
        const user = yield* service.findById("123")
        assert.strictEqual(user.id, "123")
      }),
    )
  })
})
```

## Test Anti-Patterns

### FORBIDDEN: throw inside Effect.gen
```ts
// WRONG
if (!user) throw new Error("Not found")

// CORRECT
if (!user) return yield* Effect.fail(new UserNotFoundError({ userId: id }))
```

### FORBIDDEN: try/catch for error testing
```ts
// WRONG — loses Effect composition
try {
  await effect
} catch (e) { /* check error */ }

// CORRECT — use Effect.either or Effect.flip
const result = yield* effect.pipe(Effect.either)
```

### FORBIDDEN: console.log in tests (use assert)
```ts
// WRONG
console.log("result:", result)

// CORRECT — use assert with structured messages
assert.strictEqual(result.value, expected)
```

### FORBIDDEN: jest.fn() or vi.fn() for mocking in Effect context
```ts
// WRONG — plain mocks don't integrate with Effect's fiber system
const mockFn = vi.fn(() => Effect.succeed("result"))

// CORRECT — use Layer.succeed to mock services
const mockService = Layer.succeed(
  Database.Service,
  Database.Service.of({ query: () => Effect.succeed([]) }),
)
```

### FORBIDDEN: mutable shared state in concurrent tests
```ts
// WRONG — mutable counters in concurrent fibers can race
let count = 0
const fiber = yield* Effect.fork(
  Effect.forEach(list, (x) =>
    Effect.sync(() => { count++ }))
)

// CORRECT — use Effect-native refs or deterministic coordination
const countRef = yield* Ref.make(0)
const fiber = yield* Effect.fork(
  Effect.forEach(list, (x) => Ref.update(countRef, (n) => n + 1))
)
```