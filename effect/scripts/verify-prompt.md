# Effect Verification Loop

Execute these steps after generating or modifying Effect code.

## Step 0: Check CLI Availability

```
Bash tool: bunx @effect/language-service --version 2>&1
```

- If version prints → proceed to Step 1
- If command fails → **tell the user:**

> "@effect/language-service is not installed. Install it for full Effect diagnostics (70+ checks with auto-fix):
> `bun add --dev @effect/language-service`
> Or run: `bash skills/effect/scripts/setup-lsp.sh`
> Falling back to manual anti-pattern checks for now."

Then skip to Step 3b (manual fallback) instead of Steps 1-2.

## Step 1: Run Effect Diagnostics

```
Bash tool: bunx @effect/language-service diagnostics --file FILE_PATH --format json 2>&1
```

Parse the JSON output. Each entry has: file, line, column, severity, message, code.

- If no diagnostics → Step 4
- If diagnostics found → Step 2

## Step 2: Get Quick Fixes

For each diagnostic with severity error or warning:

```
Bash tool: bunx @effect/language-service quickfixes --file FILE_PATH --code DIAGNOSTIC_CODE 2>&1
```

The CLI outputs proposed code changes. Apply them using the Edit tool.

If no quickfix available for a diagnostic, look up the fix in `references/lsp-integration.md` diagnostic→fix map and apply manually.

## Step 3b: Manual Fallback (when CLI unavailable)

If Step 0 detected CLI is not installed, check manually against SKILL.md anti-patterns table:

1. Missing `yield*` on Effect calls → scan for Effect-returning calls without `yield*`
2. `throw` inside `Effect.gen` → should be `Effect.fail`
3. `Effect.runPromise` inside service → should be in facades only
4. `console.log` → should be `Effect.log`
5. `process.env` → should be `Config.string`
6. `try/catch` in generators → should use `Effect.catchTag`
7. `let` mutable state → should be `Ref`
8. Mixed `.pipe` + `Effect.gen` → pick one style

Then proceed to Step 4 (type check).

## Step 3: Re-verify (max 3 iterations)

Run Step 1 again on the same file.

- If clean → Step 4
- If iteration < 3 → Step 2
- If iteration = 3 → proceed with remaining issues noted

## Step 4: Type Check

```
Bash tool: bunx tsc --noEmit --pretty 2>&1 | head -50
```

- If type errors → fix them, return to Step 1
- If clean → Step 5

## Step 5: Run Tests

<HARD-GATE>
Do NOT skip test execution. "We can test later" is a rationalization.
If no test file exists, note this in the report as a gap — but still run any existing tests.
</HARD-GATE>

```
Bash tool: bunx vitest run FILE_TEST_PATH --reporter=verbose 2>&1 | tail -30
```

- If failures → fix, return to Step 1
- If pass → Step 6
- If no test file exists → note "No test file found — testing gap" in report, proceed to Step 6

## Step 6: Report

Output one of:

```
Verified: 0 Effect diagnostics in FILE. Type check clean. Tests pass.
```

```
Verified: N issues remaining in FILE (listed below). Type check clean.
- line 42: globalConsole (suggestion, intentional in CLI entry point)
```
