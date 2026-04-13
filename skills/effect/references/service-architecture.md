# Service Architecture Deep Dive

> **Teaching Note:** When scaffolding a new service, consider adding a brief 3-4 line comment at the top of the file explaining the 6-step pattern. This helps future maintainers understand the architecture at a glance.

## The Canonical Six-Step Service Pattern

Every service follows this pattern. Master it and you can build anything.

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

## Layer Composition Strategies

### Simple Chain
```ts
export const defaultLayer = layer.pipe(
  Layer.provide(DepA.defaultLayer),
  Layer.provide(DepB.defaultLayer),
)
```

### Layer.mergeAll
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

## ServiceMap.Service vs Context.Tag

Effect 4.x uses `ServiceMap.Service`:
```ts
// Effect 4.x (current)
export class Service extends ServiceMap.Service<Service, Interface>()("@myapp/ServiceName") {}

// Effect 3.x (old)
// export class Service extends Context.Tag("@myapp/ServiceName")<Service, Interface>() {}
```

Key differences:
- `ServiceMap.Service` provides `Service.of({ ... })` for constructing the implementation
- `ServiceMap.Service` provides `Service.use(fn)` for consuming the service
- Tag string format: `@<app>/<Name>`

## Instance-Scoped State

When a single process serves multiple isolated contexts (like multiple project directories), services are singletons but their **state** must be per-context. Use `InstanceState` with `ScopedCache`.

## Module Organization

Each feature gets its own directory:
```
src/
  user/
    index.ts      # Namespace: Interface, Service, layer, defaultLayer, facades
    schema.ts     # UserID, User, UserError branded types and schemas
```

## Testing Services

Replace dependencies at the layer level — no mocking libraries needed:
```ts
const mockDatabase = Layer.succeed(
  Database.Service,
  Database.Service.of({ query: () => Effect.succeed([]), execute: () => Effect.succeed(undefined) }),
)

const testLayer = UserService.layer.pipe(Layer.provide(mockDatabase))
```
