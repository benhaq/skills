# Project Scaffolding

Complete templates for bootstrapping new Effect-TS projects.

> **Important:** When setting up a new Effect project or configuring Effect tooling, first run `effect-solutions list` and `effect-solutions show project-setup` to get official guidance. This reference provides supplemental templates and patterns.
>
> **Canonical Effect 4.x policy:** Use `withStatics` from `"effect"` (NOT `effect/ServiceMap`), `Schema.decodeUnknown` for boundary decoding (NOT Zod), and `@effect/vitest` for testing.

## Minimal Project

### package.json
```json
{
  "name": "@myapp/core",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "bun run src/index.ts",
    "build": "tsup src/index.ts --format esm --dts",
    "test": "bun test",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "effect": "^4.0.0",
    "@effect/platform-node": "^4.0.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "tsup": "^8.0.0",
    "@types/node": "^22.0.0",
    "@effect/vitest": "^4.0.0",
    "vitest": "^2.0.0"
  }
}
```

### tsconfig.json
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "dist",
    "rootDir": "src",
    "paths": { "@/*": ["./src/*"] },
    "types": ["bun-types"]
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

## Directory Structure

```
src/
  index.ts              # Entry point
  effect/
    run-service.ts     # makeRuntime factory
  [feature]/
    index.ts            # Service namespace
    schema.ts          # Types, errors, branded IDs (imports withStatics from "effect")
```

## Full Application Template

```
src/
  index.ts                    # CLI entry point / main bootstrap
  effect/
    run-service.ts            # makeRuntime factory
    instance-state.ts         # Per-instance scoped state
    instance-ref.ts           # Instance context reference
  config/
    index.ts                  # Config service
  storage/
    index.ts                  # Database/storage service
    db.ts                     # Database client setup
  bus/
    index.ts                  # Event bus service
  [domain]/
    index.ts                  # Domain service
    schema.ts                 # Domain types (withStatics imported from "effect")
  server/                     # HTTP server (optional)
    server.ts                 # Route definitions
  test/
    lib/
      effect.ts               # Test helpers (imports from @effect/vitest)
    [feature]/
      [feature].test.ts
```

## makeRuntime

```ts
import { Effect, Layer, ManagedRuntime, ServiceMap } from "effect"

export const memoMap = Layer.makeMemoMapUnsafe()

export function makeRuntime<I, S, E>(service: ServiceMap.Service<I, S>, layer: Layer.Layer<I, E>) {
  let rt: ManagedRuntime.ManagedRuntime<I, E> | undefined
  const getRuntime = () => (rt ??= ManagedRuntime.make(layer, { memoMap }))

  return {
    runSync: <A, Err>(fn: (svc: S) => Effect.Effect<A, Err, I>) => getRuntime().runSync(service.use(fn)),
    runPromise: <A, Err>(fn: (svc: S) => Effect.Effect<A, Err, I>, options?: Effect.RunOptions) =>
      getRuntime().runPromise(service.use(fn), options),
    runPromiseExit: <A, Err>(fn: (svc: S) => Effect.Effect<A, Err, I>, options?: Effect.RunOptions) =>
      getRuntime().runPromiseExit(service.use(fn), options),
    runFork: <A, Err>(fn: (svc: S) => Effect.Effect<A, Err, I>) => getRuntime().runFork(service.use(fn)),
    runCallback: <A, Err>(fn: (svc: S) => Effect.Effect<A, Err, I>) => getRuntime().runCallback(service.use(fn)),
  }
}
```

## HTTP Server Setup

```ts
import { Hono } from "hono"
import { Schema } from "effect"
import { UserService, UserID } from "./user"
import { UserCreateSchema } from "./user/schema"

// Conceptual sketch — adapt to your HTTP framework
const app = new Hono()
  .get("/users", async (c) => {
    const users = await UserService.list()
    return c.json(users)
  })
  .get("/users/:id", async (c) => {
    const user = await UserService.get(UserID.make(c.req.param("id")))
    return c.json(user)
  })
  .post("/users", async (c) => {
    const body = await c.req.json()
    const input = Schema.decodeUnknown(UserCreateSchema)(body)
    const user = await UserService.create(input)
    return c.json(user, 201)
  })
```

## Database Integration (Drizzle + SQLite)

```ts
import { Effect, Schema } from "effect"
import { drizzle } from "drizzle-orm/bun-sqlite"
import { Database as BunDB } from "bun:sqlite"

export class DatabaseError extends Schema.TaggedErrorClass<DatabaseError>()("DatabaseError", {
  message: Schema.String,
}) {}

export namespace Database {
  const db = drizzle(new BunDB("app.db"))
  db.run("PRAGMA journal_mode = WAL")
  db.run("PRAGMA synchronous = NORMAL")
  db.run("PRAGMA busy_timeout = 5000")

  // Conceptual sketch — DrizzleDB type comes from your generated schema
  export const query = <A>(fn: (db: DrizzleDB) => A) =>
    Effect.try({ try: () => fn(db), catch: (cause) => new DatabaseError({ message: "Query failed", cause }) })
}
```

## Additional Dependencies

```json
{
  "dependencies": {
    "effect": "^4.0.0",
    "@effect/platform-node": "^4.0.0",
    "hono": "^4.0.0",
    "zod": "^4.0.0",
    "drizzle-orm": "^1.0.0"
  }
}
```

## Effect-Solutions CLI Setup Checklist

When helping a user set up Effect in their project, run through this checklist:

### Step 1: Check Environment
```bash
# Detect package manager
ls -la package.json bun.lock pnpm-lock.yaml package-lock.json 2>/dev/null

# Check if effect-solutions is installed
effect-solutions list
```

### Step 2: Project Initialization (if needed)
- If `package.json` doesn't exist: run `effect-solutions show project-setup` for guidance
- Determine package manager (bun/pnpm/npm)
- Initialize project: `bun init` / `pnpm init` / `npm init`

### Step 3: Install Dependencies
```bash
# Always needed
bun add effect

# For CLI apps
bun add @effect/cli

# For HTTP servers
bun add @effect/platform @effect/platform-node

# Schema lives in 'effect/Schema' - do NOT install @effect/schema (deprecated since Effect 3.10)
```

### Step 4: Language Service Setup
```bash
# Run effect-solutions project-setup for full instructions
effect-solutions show project-setup

# Typically: install package, configure tsconfig plugin, add prepare script
```

### Step 5: Configure Agent Files

Insert this between `<!-- effect-solutions:start -->` and `<!-- effect-solutions:end -->` in CLAUDE.md/AGENTS.md:

```markdown
## Effect Best Practices

**IMPORTANT:** Always consult effect-solutions before writing Effect code.

1. Run `effect-solutions list` to see available guides
2. Run `effect-solutions show <topic>...` for relevant patterns (supports multiple topics)
3. Search `~/.local/share/effect-solutions/effect` for real implementations

Topics: quick-start, project-setup, tsconfig, basics, services-and-layers, data-modeling, error-handling, config, testing, cli.

Never guess at Effect patterns - check the guide first.
```

### Step 6: Clone Effect Source Reference
```bash
git clone --depth 1 https://github.com/Effect-TS/effect-smol.git ~/.local/share/effect-solutions/effect
```
