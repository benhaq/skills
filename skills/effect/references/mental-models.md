# Effect-TS Mental Models

Extended analogies for every major Effect concept. Use these when the user says "explain", "help me understand", "confused about", or needs onboarding analogies.

## Start Here: Effect is a Recipe

The single most important mental model. Everything else follows from this.

**Core analogy:** An Effect is a recipe written on paper. It describes how to make a dish but hasn't been cooked yet.

```ts
// This is a recipe card. Nothing has happened yet.
const recipe = Effect.gen(function* () {
  const eggs = yield* crackEggs()     // "crack 3 eggs"
  const cooked = yield* fry(eggs)    // "fry in butter"
  return yield* plate(cooked)         // "serve on plate"
})

// To actually cook it, you need a kitchen (Runtime):
const breakfast = await Effect.runPromise(recipe)  // "OK, start cooking!"
```

**Why this matters — the superpower of recipes:**
```ts
// Because a recipe isn't cooking yet, you can modify it BEFORE running:
// Add a retry policy — "if it fails, try 3 times"
const robustRecipe = recipe.pipe(Effect.retry({ times: 3 }))

// Add a timeout — "if it takes more than 5 seconds, give up"
const fastRecipe = recipe.pipe(Effect.timeout("5 seconds"))

// Chain it with another recipe — "after breakfast, do the dishes"
const morningRoutine = Effect.gen(function* () {
  const breakfast = yield* recipe
  const dishes = yield* doDishes
  return { breakfast, dishes }
})

// You CAN'T do this with Promises — they're already cooking!
```

**Promise vs Effect comparison:**
```
Promise        = "I'm already in the microwave, here's a token to check on me"
Effect         = "I'm a recipe card. Give me to a chef (Runtime) when you want to cook."
```

## Progressive Mental Models (Build Up Layer by Layer)

Once the recipe analogy clicks, here is how each Effect concept maps to familiar ideas:

| Concept | Analogy | Start With |
|---------|---------|-----------|
| Effect | Recipe | This section |
| Layer | Factory / Supply chain | Section below |
| yield* | useContext / calling another recipe | React section |
| Fiber | Background task / useTransition | React section |
| Scope | useEffect cleanup | React section |
| R channel | Type-level ingredient list | Later sections |

### Recipe in Practice: yield*

Inside a recipe (Effect.gen), `yield*` is like calling another recipe's method:

```ts
Effect.gen(function* () {
  const db = yield* Database.recipe  // "I need Database from the factory"
  const users = yield* db.query()   // "Run the query recipe"
  return users
})
```

This is exactly like React's `useContext` — you're pulling a dependency from context rather than passing it as a parameter.

## Layer: The Factory Model

```
Layer<Database, ConfigError, Config>

Translation:
  "To build a Database, I need a Config.
   If Config is broken, I'll fail with ConfigError.
   If it works, you get a Database."
```

**Composition as a supply chain (Effect 4.x canonical pattern):**
```ts
import { Effect, Layer, ServiceMap } from "effect"

// Step 1: Define interface (in namespace)
export namespace Database {
  export interface Service {
    readonly query: (sql: string) => Effect.Effect<unknown>
  }
  // Step 2: Create Service class
  export class Service extends ServiceMap.Service<Service, Service>()("@app/Database") {}
  // Step 3: Build layer
  export const layer = Layer.effect(Service, Effect.gen(function* () {
    const pool = yield* Pool
    return Service.of({
      query: (sql: string) => pool.execute(sql),
    })
  }))
  // Step 4: defaultLayer wires dependencies
  export const defaultLayer = layer.pipe(Layer.provide(ConfigLayer))
}
```

> **Pedagogical note:** This is for explanation mode, not as production scaffolding. For full six-step pattern, see `service-architecture.md`.

**Key insight:** Layers are **memoized by default**. If two services both need `Config`, they get the same instance.

## Fiber: The Managed Thread Model

```
OS Thread     = expensive, unmanaged lifecycle
Promise       = fire-and-forget, no cancellation
Effect Fiber  = cheap + structured lifetime + cancellation
```

**The structured concurrency guarantee:**
```ts
Effect.gen(function* () {
  const f1 = yield* Effect.fork(task1)
  const f2 = yield* Effect.fork(task2)
  // If THIS generator fails or is interrupted:
  // → f1, f2 are ALL interrupted automatically
  // → No orphaned work, no leaked resources
  return yield* Fiber.join(f1)
})
```

## The R Channel: Compile-Time DI

```ts
// Regular function: explicit about what it needs
function getUser(db: Database, id: string): User

// Effect: explicit about what it needs, but via the type system
const getUser: (id: string) => Effect<User, UserError, Database>
//                                                       ^^^^^^^^
//                                              "I need a Database"
```

**When R = never, the program is self-contained and ready to run.**

## Schema: The Codec Model

```
         decode
unknown -------→ TypedValue
         encode
TypedValue ----→ unknown
```

**Zod comparison:**
```
Zod:    validate(input) → TypedValue | Error    (one direction)
Schema: decode(input)   → TypedValue | Error    (unknown → typed)
        encode(value)   → unknown    | Error    (typed → unknown)
```

## Cause: The Error Archaeology Model

```
Simple error:    "Database connection failed"
Cause:           "Database connection failed (after 3 retries)
                  while also: Config reload interrupted
                  because: parent fiber timed out"
```

**The Cause tree:**
```
Cause
├── Fail(error)              ← expected domain error
├── Die(defect)              ← unexpected bug (throw, null ref)
├── Interrupt(fiberId)       ← clean cancellation
├── Sequential(cause, cause) ← "A happened, then B"
└── Parallel(cause, cause)   ← "A and B happened at the same time"
```

## Scope: The Resource Bracket Model

```ts
const managed = Effect.acquireRelease(
  openConnection(),           // acquire
  (conn) => conn.close(),     // release (runs no matter what)
)
```

## React/Frontend Analogies

| Effect Concept | React Analog | Key Difference |
|---------------|-------------|---------------|
| Layer | Context.Provider | Provides services to tree |
| yield* (service) | useContext hook | Pulls service from context |
| Scope | useEffect cleanup | Runs on unmount, always |
| Fiber | useTransition | Background work, can cancel |
| R channel | Type-level DI | "Compile-time" ingredients |
| PubSub | Event bus | Subscribe/notify |
| Schema | PropTypes + TypeScript | Validate at boundary |
| Effect.gen | async/await | Sequential composition |

### R Channel: The Type-Level Ingredient List

The `R` in `Effect<A, E, R>` is like TypeScript's type parameter for dependencies — but checked at compile time:

```ts
// React: props must be passed down
function UserProfile({ db, userId }: { db: Database, userId: string })

// Effect: R channel IS the type
const getUser: (id: string) => Effect<User, NotFound, Database>
//                                                      ^^^^^^^^
//                                         "I REQUIRE a Database"
```

If `R = never`, the Effect needs nothing — it's self-contained like a hook with no dependencies.

### Effect vs Promise (React Concurrent Analogy)

| Promise | Effect |
|---------|--------|
| Already executing | Recipe (not executed yet) |
| `await promise` blocks | `yield* effect` composes |
| `.then()` chains | `.pipe(Effect.map)` chains |
| No structured cancellation | Fibers auto-cancel on scope exit |
| Race is `Promise.race` (unreliable) | `Effect.race` (guaranteed) |
| useTransition aborts render | Fiber.interrupt aborts work |

```tsx
// React Suspense: shows old UI until data arrives
const User = suspend(() => fetchUser(id))
// Effect: same pattern but with typed errors
const user = yield* getUser(id)  // errors are typed, not thrown
```

## Go/Rust Analogies

| Effect Concept | Go | Rust |
|---------------|-----|------|
| Effect<A, E, R> | `(value, error)` return | `Result<A, E>` |
| Layer | wire (DI) | trait impl |
| Fiber | goroutine | tokio::task |
| Scope | defer | RAII / Drop |
| acquireRelease | defer close | Drop trait |
| Deferred | chan (one-shot) | oneshot::channel |

## When to Use Mental Models

**Trigger phrases:**
- "I don't get Effect"
- "explain why"
- "help me understand"
- "mental model"
- "coming from [React/async/Go/FP]"
- Any onboarding scenario

**When to skip mental models and go straight to code:**
- "build me a service"
- "add feature X"
- "refactor this code"
- "fix this bug"
- Anything where the user needs production code, not explanations
