# 12-Point Effect Code Review Pipeline

Execute each check. Aggregate findings into the report format from `references/code-review.md`.

**Tool priority:** Always try the CLI directly with `NODE_PATH` pointing at project node_modules first — this avoids the bunx cache issue where typescript isn't available. Use the full project scan for best coverage.

## Step 0: Check CLI Availability

```
Bash tool: NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js --version 2>&1
```

- If version prints → proceed with CLI-first checks below
- If command fails → **tell the user:**

> "@effect/language-service is not installed. For the best review (70+ automated checks), run:
> `bun add --dev @effect/language-service`
> Or run: `bash skills/effect/scripts/setup-lsp.sh`
> Proceeding with grep-based checks — rerun after installation for full coverage."

When CLI is unavailable, Checks 1 and 2 fall back to grep. All other checks work without the CLI.

## Scope Detection

Determine which files to review:

- **Single file:** User provided FILE_PATH
- **Diff:** `Bash tool: git diff --name-only HEAD~1 -- '*.ts' '*.tsx' 2>&1`
- **Full codebase:** `Bash tool: find src/ -name '*.ts' -o -name '*.tsx' 2>&1`

## Check 1: Effect Diagnostics

```
Bash tool: NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js diagnostics --project tsconfig.json 2>&1
```

Parse JSON. Group by file. Record each: {file, line, severity, code, message}.
This catches 70+ Effect-specific issues with zero false positives.

## Check 2: Service Architecture

**ALWAYS try the CLI overview first** — it gives structured output with zero false positives:

```
Bash tool: NODE_PATH=./node_modules node ./node_modules/@effect/language-service/cli.js overview --project tsconfig.json 2>&1
```

The overview lists all Effect exports: services, layers, facades.
For each service, verify 6-step completeness from the overview output:
1. Interface, 2. ServiceMap.Service, 3. Layer, 4. defaultLayer, 5. makeRuntime, 6. Facade

**Only if CLI fails** (not installed, no tsconfig), fall back to grep:
```
Grep tool: pattern="ServiceMap\.Service" path="src/" type="ts"
```
For each match, Read 50 lines around it to check for all 6 steps.

## Check 3: Error Handling

From Check 1 diagnostics, extract: extendsNativeError, tryCatchInGenerator.

Supplemental (CLI can't catch these):
```
Grep tool: pattern="\.catchAll\(" path="src/" type="ts" output_mode="content"
```
Read context around each match: if catchAll handler re-throws a generic Error → Warning.

## Check 4: Effect Correctness

From Check 1 diagnostics, extract: floatingEffect, missingYieldStar, multipleEffectProvide.

Supplemental — runPromise misuse detection:
```
Grep tool: pattern="runPromise|runSync" path="src/" type="ts" output_mode="content" -n=true
```
For each match, Read 10 surrounding lines:
- Inside makeRuntime() or `export async function` → CORRECT (facade pattern)
- Inside Effect.gen or Layer.effect → CRITICAL (service-internal misuse)

## Check 5: Schema & Data Modeling

```
Grep tool: pattern="Schema\.brand\(" path="src/" type="ts" output_mode="files_with_matches"
```
For each file:
```
Grep tool: pattern="withStatics" path=SAME_FILE
```
Missing withStatics → Warning.

```
Grep tool: pattern="Schema\.Union\(" path="src/" type="ts" output_mode="content"
```
Check for `.annotate.*discriminator` nearby → Warning if missing.

## Check 6: effect-solutions Compliance

```
Bash tool: bash skills/effect/scripts/effect-solutions-check.sh 2>&1
```

Compare each topic's canonical output against codebase patterns:
- Service pattern matches? Layer composition matches? Error base class matches?

## Check 7: Observability

From Check 1 diagnostics, extract: globalConsole.

```
Grep tool: pattern="Effect\.fn\(" path="src/" type="ts" output_mode="files_with_matches"
```
Compare against service files from Check 2 overview.
Service methods without Effect.fn → Warning.

## Check 8: Testing

```
Grep tool: pattern="from [\"']vitest[\"']" path="test/" type="ts" output_mode="content"
```
(Not from "@effect/vitest") → Warning.

```
Grep tool: pattern="it\.scoped|it\.effect" path="test/" type="ts" output_mode="count"
```
Low count relative to test file count → Suggestion.

## Check 9: Resource Management

```
Grep tool: pattern="\.(close|destroy|disconnect)\(\)" path="src/" type="ts" output_mode="content"
```
Read context: if outside acquireRelease block → Warning.

## Check 10: Concurrency

```
Grep tool: pattern="let\s+\w+\s*=" path="src/services/" type="ts" output_mode="content"
```
Read context: module-level mutable state in service → Critical.
Skip: loop variables, destructuring, test files.

```
Grep tool: pattern="Effect\.all\(" path="src/" type="ts" output_mode="content"
```
Check for `{ concurrency:` option nearby → Warning if missing.

## Check 11: Import Hygiene

From Check 1 diagnostics, extract: multipleEffectVersions.

```
Grep tool: pattern="from [\"']@effect/(schema|io)[\"']" path="src/" type="ts"
```
→ Warning (v3 imports).

```
Bash tool: bun pm ls --all 2>&1 | grep -c "effect@"
```
If > 1 version → Critical.

## Check 12: Idiomatic Assessment

Use Check 2 overview output:
- How many services follow 6-step pattern vs ad-hoc?
- Ratio of Effect.fn methods to plain arrow functions?

Use Check 1 diagnostic summary:
- Mostly suggestions → Intermediate
- Warnings present → Beginner
- Errors present → Critical issues

Use Check 4 runPromise analysis:
- All in facades → Good
- Scattered → "TypeScript with Effect sprinkled on"

## Aggregate Report

Use the output format templates from `references/code-review.md`:
- Single file → Single File Review template
- Diff → Diff/PR Review template
- Full codebase → Full Codebase Audit template

Count: critical / warning / suggestion per check.
Health score: X/12 checks passing (passes if 0 critical + 0 warning in that check).
