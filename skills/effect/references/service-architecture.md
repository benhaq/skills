# Service Architecture

> **Teaching Note:** When scaffolding a new service, consider adding a brief 3-4 line comment at the top of the file explaining the pattern. This helps future maintainers understand the architecture at a glance.

## Service Pattern Selection

Both Effect v3 and v4 are production-ready. Choose the pattern that matches your project's Effect version:

| Version | Service Pattern | Import |
|---------|-----------------|--------|
| **v4** (current) | `ServiceMap.Service` | `import { ServiceMap } from "effect"` |
| **v3** (legacy) | `Context.Tag` | `import { Context } from "effect"` |

---

## Effect 4.x Pattern: ServiceMap.Service

### Step 1: Define the Interface

```ts
export namespace UserService {
  export interface Interface {
    readonly create: (input: CreateInput) => Effect.Effect<User, UserError>
    readonly get: (id: UserID) => Effect.Effect<User, UserError>
    readonly list: () => Effect.Effect<User[], UserError>
    readonly remove: (id: UserID) => Effect.Effect<void, UserError>
  }
}
```

### Step 2: Create the Service Class

```ts
export namespace UserService {
  export class Service extends ServiceMap.Service<Service, Interface>()(
    "@myapp/UserService"
  ) {}
}
```

> **⚠️ Warning — Do not shadow `Service`:** The type parameter `Service` in `ServiceMap.Service<Service, Interface>` is intentional. Do NOT create a separate `interface Service` in the same namespace — doing so causes TypeScript to treat them as separate types and breaks `yield* Service` and `Service.of(...)`. Keep only the class as `Service`.

### Step 3: Build the Layer

```ts
export namespace UserService {
  export const layer: Layer.Layer<Service, never, Database.Service | Bus.Service> =
    Layer.effect(
      Service,
      Effect.gen(function* () {
        const db = yield* Database.Service
        const bus = yield* Bus.Service

        const create = Effect.fn("UserService.create")(function* (input: CreateInput) {
          const user = yield* db.insert(input)
          yield* bus.publish(UserCreated, { userId: user.id })
          return user
        })
        // ... other methods

        return Service.of({ create, get, list, remove })
      }),
    )
}
```

### Step 4: Compose defaultLayer

```ts
export namespace UserService {
  export const defaultLayer = layer.pipe(
    Layer.provide(Database.defaultLayer),
    Layer.provide(Bus.layer),
  )
}
```

### Step 5: Create the Runtime Facade

```ts
const { runPromise } = makeRuntime(Service, defaultLayer)
```

### Step 6: Export Facade Functions

```ts
export async function create(input: CreateInput) {
  return runPromise((svc) => svc.create(input))
}
```

---

## Effect 3.x Pattern: Context.Tag

### Step 1: Define the Interface and Tag

```ts
export namespace UserService {
  export interface Service {
    readonly create: (input: CreateInput) => Effect.Effect<User, UserError>
    readonly get: (id: UserID) => Effect.Effect<User, UserError>
    readonly list: () => Effect.Effect<User[], UserError>
    readonly remove: (id: UserID) => Effect.Effect<void, UserError>
  }

  // Tag declaration - must follow @scope/Name format
  export const Service = Context.Tag<Service>("@myapp/UserService")
}
```

> **⚠️ Warning — Tag string format:** Tags must use `@scope/Name` format. Missing `@` or using wrong separator causes service resolution failures.

### Step 2: Build the Layer

```ts
export namespace UserService {
  export const layer: Layer.Layer<Service, never, Database.Service | Bus.Service> =
    Layer.effect(
      Service,
      Effect.gen(function* () {
        const db = yield* Database.Service
        const bus = yield* Bus.Service

        const create = Effect.fn("UserService.create")(function* (input: CreateInput) {
          const user = yield* db.insert(input)
          yield* bus.publish(UserCreated, { userId: user.id })
          return user
        })
        // ... other methods

        return Service.of({ create, get, list, remove })
      }),
    )
}
```

### Step 3: Compose defaultLayer

**v3 uses Layer.provide with array (first arg):**
```ts
export namespace UserService {
  export const defaultLayer = Layer.provide(
    [Database.defaultLayer, Bus.layer],  // Array first (v3 style)
    layer,
  )
}
```

### Step 4: Create the Runtime Facade

```ts
const { runPromise } = makeRuntime(Service, defaultLayer)
```

### Step 5: Export Facade Functions

```ts
export async function create(input: CreateInput) {
  return runPromise((svc) => svc.create(input))
}
```

---

## Key Differences Summary

| Aspect | v4 (ServiceMap.Service) | v3 (Context.Tag) |
|--------|-------------------------|------------------|
| Service declaration | `class Service extends ServiceMap.Service` | `const Service = Context.Tag` |
| Tag string | `@myapp/ServiceName` | `@myapp/ServiceName` |
| Consumer access | `yield* Service.Service` | `yield* Service` |
| Layer.provide | Variadic: `provide(main, dep1, dep2)` | Array: `provide([deps], main)` |
| Service factory | `Service.of({ ... })` | `Service.of({ ... })` |

---

## The Three-Layer Pattern

### Layer 1: Raw Layer

`layer` declares dependencies explicitly in the type:
```ts
Layer.Layer<Service, ServiceError, Database.Service | Bus.Service>
```

### Layer 2: Composed defaultLayer

Wires all dependencies, producing a self-contained layer:
```ts
Layer.Layer<Service, ServiceError>  // no remaining requirements
```

### Layer 3: Runtime Facade

`makeRuntime` creates a memoized runtime; facade functions expose async API.

---

## Layer Composition Strategies

### Simple Chain (v4)

```ts
export const defaultLayer = layer.pipe(
  Layer.provide(DepA.defaultLayer),
  Layer.provide(DepB.defaultLayer),
)
```

### Simple Chain (v3)

```ts
export const defaultLayer = Layer.provide(
  [DepA.defaultLayer, DepB.defaultLayer],  // array first
  layer,
)
```

### Layer.mergeAll (both versions)

```ts
const infraLayer = Layer.mergeAll(Database.defaultLayer, Cache.defaultLayer, Bus.layer)
```

### Layer.unwrap (Breaking Circular Imports)

```ts
const defaultLayer = Layer.unwrap(
  Effect.sync(() =>
    layer.pipe(Layer.provide(ServiceA.defaultLayer), Layer.provide(ServiceB.defaultLayer)),
  ),
)
```

---

## Instance-Scoped State

When a single process serves multiple isolated contexts (like multiple project directories), services are singletons but their **state** must be per-context. Use `InstanceState` with `ScopedCache`.

---

## Module Organization

Each feature gets its own directory:
```
src/
  user/
    index.ts      # Namespace: Interface, Service, layer, defaultLayer, facades
    schema.ts     # UserID, User, UserError branded types and schemas
```

---

## Testing Services

Replace dependencies at the layer level — no mocking libraries needed:

### v4 Pattern

```ts
const mockDatabase = Layer.succeed(
  Database.Service,
  Database.Service.of({ query: () => Effect.succeed([]), execute: () => Effect.succeed(undefined) }),
)

const testLayer = UserService.layer.pipe(Layer.provide(mockDatabase))
```

### v3 Pattern

```ts
const mockDatabase = Layer.succeed(
  Database.Service,
  Database.Service.of({ query: () => Effect.succeed([]), execute: () => Effect.succeed(undefined) }),
)

const testLayer = Layer.provide([mockDatabase], UserService.layer)
```

---

## Migration: v3 to v4

See `migration-v3-v4.md` for detailed conversion steps.

**Quick reference:**

1. Replace `Context.Tag<Service>("@name")` with `ServiceMap.Service<Service, Interface>()("@name")`
2. Change `Layer.provide([deps], main)` to `Layer.provide(main, deps...)`
3. Update consumer access from `yield* ServiceTag` to `yield* Service.Service`
4. Consolidate imports from `@effect/io`, `@effect/schema` to `effect`
