# Effect v3 to v4 Migration Guide

This guide covers migrating from Effect v3 to v4. Both versions are production-ready; v4 is the current modern approach while v3 remains stable and supported.

## Overview

| Aspect | v3 | v4 |
|--------|----|----|
| **Package model** | Separate packages | Single barrel import |
| **Service pattern** | `Context.Tag` | `ServiceMap.Service` |
| **Error tagging** | `Data.TaggedError` | `Schema.TaggedErrorClass` |
| **Branding** | `Brand.nominal` | `Schema.brand` with `withStatics` |
| **Import paths** | `@effect/schema`, `@effect/io` | `effect` |

---

## Package Consolidation

### v3: Separate Packages

```ts
import { Effect, Context, Layer } from "@effect/io"
import { Schema, Brand, Data } from "@effect/schema"
```

### v4: Single Barrel Import

```ts
import { Effect, Context, Layer, Schema, Brand, Data } from "effect"
```

**Migration:** Replace multi-package imports with single `effect` import. Update any `@effect/*` package references to use `effect`.

---

## Service Pattern Migration

### v3: Context.Tag Pattern

```ts
import { Effect, Context, Layer } from "effect"

// Define tag
export const UserServiceTag = Context.Tag<UserService.Service>("@app/UserService")

// Define service interface
export namespace UserService {
  export interface Service {
    readonly create: (input: CreateInput) => Effect.Effect<User, UserError>
    readonly get: (id: UserID) => Effect.Effect<User, UserError>
  }

  export const Service = UserServiceTag
}

// Implement service
export const UserServiceLayer = Layer.effect(
  UserServiceTag,
  Effect.gen(function* () {
    const db = yield* DatabaseService
    return UserService.of({
      create: (input) => db.insert(input),
      get: (id) => db.findById(id),
    })
  })
)

// Consume service
const result = yield* UserService
```

### v4: ServiceMap.Service Pattern

```ts
import { Effect, ServiceMap, Layer } from "effect"

// Define service class
export namespace UserService {
  export class Service extends ServiceMap.Service<Service, Interface>()(
    "@app/UserService"
  ) {}

  export interface Interface {
    readonly create: (input: CreateInput) => Effect.Effect<User, UserError>
    readonly get: (id: UserID) => Effect.Effect<User, UserError>
  }
}

// Implement service
export const UserServiceLayer = Layer.effect(
  UserService.Service,
  Effect.gen(function* () {
    const db = yield* DatabaseService
    return UserService.Service.of({
      create: (input) => db.insert(input),
      get: (id) => db.findById(id),
    })
  })
)

// Consume service
const result = yield* UserService.Service
```

### Key Differences

| Aspect | v3 | v4 |
|--------|----|----|
| Tag declaration | `Context.Tag<Service>("@app/Name")` | `ServiceMap.Service<Service, Interface>()("@app/Name")` |
| Service type | `Context.Tag` instance | Class extending `ServiceMap.Service` |
| Consumer access | `yield* ServiceTag` | `yield* Service.Service` |
| Service factory | `Service.of({ ... })` | `Service.of({ ... })` (same) |
| Dependency access | `yield* dependencyTag` | `yield* Dependency.Service` |

### Migration Strategy

1. **Create new ServiceMap.Service class** with same interface name
2. **Update Layer.effect** to use new class instead of Context.Tag
3. **Update all consumers** to use `Service.Service` instead of `ServiceTag`
4. **Update type annotations** from `Context.Tag<Service>` to `ServiceMap.Service<Service, Interface>`

---

## Error Pattern Migration

### v3: Data.TaggedError

```ts
import { Effect, Data } from "@effect/schema"

export class UserNotFoundError extends Data.TaggedError<UserNotFoundError>() {
  constructor(
    public readonly userId: string,
    override readonly message: string = `User not found: ${userId}`
  ) {
    super()
  }
}

export class ValidationError extends Data.TaggedError<ValidationError>() {
  constructor(
    public readonly errors: string[],
    override readonly message: string = `Validation failed: ${errors.join(", ")}`
  ) {
    super()
  }
}

// Usage
return Effect.fail(new UserNotFoundError(userId))
yield* Effect.fail(new ValidationError(["email required"]))
```

### v4: Schema.TaggedErrorClass

```ts
import { Effect, Schema } from "effect"

export class UserNotFoundError extends Schema.TaggedErrorClass<UserNotFoundError>()(
  "UserNotFoundError",
  {
    userId: Schema.String,
  }
) {
  override get message() { return `User not found: ${this.userId}` }
}

export class ValidationError extends Schema.TaggedErrorClass<ValidationError>()(
  "ValidationError",
  {
    errors: Schema.Array(Schema.String),
    cause: Schema.optional(Schema.Defect),
  }
) {}

// Usage
return yield* Effect.fail(new UserNotFoundError({ userId }))
yield* Effect.fail(new ValidationError({ errors: ["email required"] }))
```

### Key Differences

| Aspect | v3 | v4 |
|--------|----|----|
| Base class | `Data.TaggedError` | `Schema.TaggedErrorClass` |
| Constructor | Positional args | Object with schema |
| Schema definition | None | Inline `Schema.Struct` |
| Error cause | Manual | `Schema.optional(Schema.Defect)` |
| Discriminator | `_tag` property | `_tag` + schema validation |

### Migration Strategy

1. **Change base class** from `Data.TaggedError` to `Schema.TaggedErrorClass`
2. **Define schema** as second type parameter: `Schema.TaggedErrorClass<MyError>()("MyError", { fields... })`
3. **Convert constructor args** to object: `new MyError({ field1, field2 })` instead of `new MyError(arg1, arg2)`
4. **Add cause handling** with `Schema.optional(Schema.Defect)` if needed

---

## Branded Type Migration

### v3: Brand.nominal

```ts
import { Schema, Brand } from "@effect/schema"

export const UserID = Schema.String.pipe(
  Brand.nominal<UserID>()
)

export const AccessToken = Schema.String.pipe(
  Brand.nominal<AccessToken>()
)

// Constructor
const userId = Brand.nominal<UserID>().make("user-123")

// Type guard
if (Brand.nominal<AccessToken>().is(token)) {
  // token is AccessToken
}
```

### v4: Schema.brand with withStatics

```ts
import { Schema, withStatics } from "effect"

export const UserID = Schema.String.pipe(
  Schema.brand("UserID"),
  withStatics((s) => ({
    make: (id: string) => s.makeUnsafe(id),
    isValid: (t: unknown): t is Schema.Schema.Type<typeof UserID> =>
      typeof t === "string" && t.length > 0,
  }))
)

export const AccessToken = Schema.String.pipe(
  Schema.brand("AccessToken"),
  withStatics((s) => ({
    make: (token: string) => s.makeUnsafe(token),
    isValid: (t: unknown): t is Schema.Schema.Type<typeof AccessToken> =>
      typeof t === "string" && token.startsWith("eyJ"),
  }))
)

// Usage
const userId = UserID.make("user-123")
if (UserID.isValid(value)) { /* ... */ }
```

### Key Differences

| Aspect | v3 | v4 |
|--------|----|----|
| Branding API | `Brand.nominal<T>()` | `Schema.brand("Name")` |
| Constructor | `Brand.nominal<T>().make(value)` | `SchemaName.make(value)` via `withStatics` |
| Type guard | `Brand.nominal<T>().is(value)` | `SchemaName.isValid(value)` via `withStatics` |
| Type extraction | Manual `brand<UserID>()` cast | Automatic via `Schema.Schema.Type<typeof Schema>` |

### Migration Strategy

1. **Replace `Brand.nominal`** with `Schema.brand("TypeName")`
2. **Add `withStatics`** to provide `make` and `isValid` helpers
3. **Update type extraction** from `brand<T>()` to `Schema.Schema.Type<typeof Schema>`

---

## Fiber and Runtime Changes

### v3: Runtime and FiberRef

```ts
import { Effect, FiberRef, Runtime } from "@effect/io"

const runtimeRef = FiberRef.unsafeMake(initialValue)

// Get/set in Effect
yield* FiberRef.get(runtimeRef)
yield* FiberRef.set(runtimeRef, newValue)

// Runtime for synchronous execution
const runtime = Runtime.defaultRuntime()
Effect.runSync(effect, runtime)
```

### v4: Context.Reference

```ts
import { Effect, Context } from "effect"

// Context.Reference replaces FiberRef
const ref = Context.Reference.unsafeMake(initialValue)

// Get/set in Effect
yield* ref.get()
yield* ref.set(newValue)

// Synchronous execution - no Runtime needed
Effect.runSync(effect) // directly supported
```

### Key Changes

| Aspect | v3 | v4 |
|--------|----|----|
| Fiber-local state | `FiberRef` | `Context.Reference` |
| Synchronous execution | `Runtime.defaultRuntime()` | `Effect.runSync(effect)` directly |
| Runtime management | Manual | Simplified |

---

## Layer Composition

### v3: Layer.provide with array

```ts
const appLayer = Layer.provide(
  [DatabaseLayer, CacheLayer, BusLayer], // array
  UserServiceLayer
)
```

### v4: Variadic Layer.provide

```ts
const appLayer = Layer.provide(
  UserServiceLayer,
  DatabaseLayer,
  CacheLayer,
  BusLayer
)
```

### Migration

Replace array form with variadic arguments:

```ts
// v3
Layer.provide([layerA, layerB, layerC], mainLayer)

// v4
Layer.provide(mainLayer, layerA, layerB, layerC)
```

---

## Import Path Changes

### Complete Import Mapping

| v3 | v4 |
|---|---|
| `import { ... } from "@effect/io"` | `import { ... } from "effect"` |
| `import { ... } from "@effect/schema"` | `import { ... } from "effect"` |
| `import { ... } from "@effect/platform"` | `import { ... } from "@effect/platform-*"` |
| `import { ... } from "@effect/rpc"` | Removed / merged |

### Migration Command

```bash
# Find files with old imports
grep -r "@effect/io\|@effect/schema" src/

# Update imports (example with sed)
sed -i '' 's/@effect\/io/effect/g' src/**/*.ts
sed -i '' 's/@effect\/schema/effect/g' src/**/*.ts
```

---

## Step-by-Step Migration

1. **Update dependencies**
   ```bash
   npm install effect@latest
   npm remove @effect/io @effect/schema @effect/platform
   ```

2. **Fix imports** - Replace all `@effect/*` imports with `effect`

3. **Migrate services** - Convert `Context.Tag` to `ServiceMap.Service`

4. **Migrate errors** - Convert `Data.TaggedError` to `Schema.TaggedErrorClass`

5. **Migrate branded types** - Convert `Brand.nominal` to `Schema.brand` with `withStatics`

6. **Update Layer.provide calls** - Change array form to variadic

7. **Update FiberRef usage** - Replace with `Context.Reference`

8. **Remove Runtime usage** - v4 supports direct `Effect.runSync(effect)`

9. **Run diagnostics**
   ```bash
   NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json
   ```

10. **Test thoroughly** - Run full test suite

---

## Rollback Considerations

If you need to support both v3 and v4 during a transition period:

```ts
// Version-aware service pattern
import { Effect, Context, Layer, ServiceMap } from "effect"

// v3 compatibility shim
export const createServiceTag = <T>(name: string) => {
  const tag = Context.Tag<{ value: T }>(name)
  return {
    tag,
    access: (): Effect.Effect<T> => Effect.contextWithEffect((ctx) =>
      Effect.succeed(Context.get(ctx, tag).value)
    ),
  }
}
```

This allows incremental migration rather than big-bang rewrite.
