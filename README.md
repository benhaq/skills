# benhaq/skills

A collection of Claude Code skills for Effect framework development.

## Quick Start

```bash
npx skills add benhaq/skills@effect
```

## Effect Skill

**When to invoke:** `"build a service"`, `"scaffold an Effect project"`, `"debug this error"`, `"fix this type error"`, `"explain Effect.gen"`, `"how does Layer work"`, `"add error handling"`, `"review this Effect code"`

### What it provides

- **Version-aware patterns** — Auto-detects Effect 3.x vs 4.x and applies the right canonical patterns
- **Service architecture** — 6-step canonical pattern for building idiomatic Effect services (Interface → ServiceMap.Service → Layer.effect + Effect.fn → Layer.provide → makeRuntime → facade)
- **Code review** — 12-point audit pipeline that catches real bugs without flagging intentional v3 patterns as defects
- **Debugging** — Type error resolution, floating effect detection, missing yield* identification
- **Mental models** — Effect-as-recipe analogy and progressive layer-by-layer explanations for newcomers
- **LSP integration** — Corrected TypeScript/Effect language service invocation via NODE_PATH workaround
- **TypeScript integration** — Schema validation, branded types, tagged errors, and Effect.fn observability

## Skills Included

| Skill | Triggers |
|-------|----------|
| `effect` | Building services, debugging errors, code review, explaining Effect concepts |

## Requirements

- Node.js 18+ (for Effect language service)
