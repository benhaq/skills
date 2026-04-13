# Effect-Docs MCP Usage Guide

> **Complement with effect-solutions CLI:** The MCP provides authoritative API docs, while `effect-solutions show <topic>` provides canonical patterns and project setup guidance. Use both together.

## Overview

The `effect-docs` MCP server provides authoritative, up-to-date Effect documentation. It has two tools:
- `effect_docs_search` — search Effect docs by keyword
- `get_effect_doc` — retrieve a specific doc page by ID

> **Fallback:** When the MCP is unavailable, use the official Effect docs at https://effect.website or `effect-solutions show <topic>` for canonical patterns.

**Always consult the MCP before:**
- Explaining any specific API function or module
- Debugging type errors (API surface may have changed)
- Comparing Effect versions or migration paths
- Clarifying the current canonical pattern for a primitive

## Search + Retrieve Pattern

When the user asks about a topic:

1. **Search first** to find relevant doc IDs:
   ```
   effect_docs_search({ query: "Service Layer dependency injection" })
   ```

2. **Then retrieve** the specific page:
   ```
   get_effect_doc({ documentId: 123 })
   ```

3. **Quote from the doc** in your response to ground explanations.

## Common Search Queries

| Topic | Search Query |
|-------|-------------|
| Effect.Service vs Context.Tag | `"Effect.Service Layer canonical pattern"` |
| Layer composition | `"Layer.provide Layer.effect composition"` |
| Schema TaggedError | `"Schema.TaggedErrorClass error handling"` |
| Stream operators | `"Stream.fromPubSub Stream.runForEach"` |
| Fiber interruption | `"Effect.forkScoped Fiber.interrupt"` |
| ManagedRuntime | `"ManagedRuntime effect runtime"` |
| Schedule retry | `"Schedule.exponential retry policy"` |

## When NOT to Use

- The user shows code that clearly follows a pattern and just needs explanation of that pattern (not the API itself)
- Explaining general TypeScript or programming concepts
- Simple questions where you already know the canonical answer (e.g., "use `Effect.gen` for branching logic")

## v3 → v4 Migration Notes

Key API changes that require MCP verification:
- `Context.Tag` → `ServiceMap.Service` (canonical); `Effect.Service` is a legacy-compatible alternative
- `@effect/schema` → `effect` barrel (no separate package)
- `Layer.effect/context` → still valid but `ServiceMap.Service` + `Layer.provide` is canonical
- `Effect.Service` has built-in `Default` layer and `dependencies` array (legacy pattern — use only when maintaining existing v3 code)