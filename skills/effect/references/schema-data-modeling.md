# Schema & Data Modeling

This guide covers both Effect v3 and v4 patterns. Both versions are production-ready.

## Version Selection

| Version | Branding | Error Tagging | Import |
|---------|----------|---------------|--------|
| **v4** (current) | `Schema.brand` + `withStatics` | `Schema.TaggedErrorClass` | `effect` |
| **v3** (legacy) | `Brand.nominal` | `Data.TaggedError` | `@effect/schema` |

---

## Branded Types

### v4: Schema.brand with withStatics

Use `Schema.brand` + `withStatics` for nominal types. Brand **everything** that deserves type safety:

```ts
import { Schema, Effect, withStatics } from "effect"

export const UserID = Schema.String.pipe(
  Schema.brand("UserID"),
  withStatics((s) => ({
    make: (id: string) => s.makeUnsafe(id),
    isValid: (t: unknown): t is Schema.Schema.Type<typeof UserID> =>
      typeof t === "string" && t.length > 0,
  })),
)
export type UserID = Schema.Schema.Type<typeof UserID>

export const AccessToken = Schema.String.pipe(
  Schema.brand("AccessToken"),
  withStatics((s) => ({
    make: (token: string) => s.makeUnsafe(token),
    isValid: (t: unknown): t is Schema.Schema.Type<typeof AccessToken> =>
      typeof t === "string" && t.startsWith("eyJ"),
  })),
)
export type AccessToken = Schema.Schema.Type<typeof AccessToken>
```

### v3: Brand.nominal

```ts
import { Schema, Brand } from "@effect/schema"

export const UserID = Schema.String.pipe(
  Brand.nominal<UserID>()
)
export type UserID = Brand.Brand.Type<UserID>

export const AccessToken = Schema.String.pipe(
  Brand.nominal<AccessToken>()
)
export type AccessToken = Brand.Brand.Type<AccessToken>

// Constructor
const userId = Brand.nominal<UserID>().make("user-123")

// Type guard
if (Brand.nominal<AccessToken>().is(token)) {
  // token is AccessToken
}
```

**Rule:** If two strings have different domains, they should be different branded types.

### v3 Newtype (Nominal wrapper)

For scalar types needing class-based nominal typing with inheritance:
```ts
import { Newtype, Schema } from "@effect/schema"

class SessionID extends Newtype<SessionID>()("SessionID", Schema.String) {}
```

Use `Schema.brand` + `withStatics` for simple IDs. Use `Newtype` when you need class methods or `instanceof` checks.

---

## Data Classes

### v4

```ts
class User extends Schema.Class<User>("User")({
  id: UserID,
  email: Schema.String,
  name: Schema.String,
  createdAt: Schema.DateTimeUtc,
}) {}
```

### v3

```ts
import { Data } from "@effect/schema"

class User extends Data.Class<User>()({
  id: UserID,
  email: Schema.String,
  name: Schema.String,
  createdAt: Schema.DateTimeUtc,
}) {}
```

---

## Tagged Error Classes

### v4: Schema.TaggedErrorClass

```ts
export class UserNotFoundError extends Schema.TaggedErrorClass<UserNotFoundError>()(
  "UserNotFoundError",
  { userId: Schema.String },
) {
  override get message() { return `User not found: ${this.userId}` }
}

export class UserValidationError extends Schema.TaggedErrorClass<UserValidationError>()(
  "UserValidationError",
  { message: Schema.String, cause: Schema.optional(Schema.Defect) },
) {}

export type UserError = UserNotFoundError | UserValidationError
```

Each variant gets its own `_tag`, enabling exhaustive handling:
```ts
yield* userService.get(id).pipe(
  Effect.catchTag("UserNotFoundError", (e) => /* handle missing user */),
  Effect.catchTag("UserValidationError", (e) => /* handle validation failure */),
)
```

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

export type UserError = UserNotFoundError | ValidationError
```

Usage:
```ts
yield* Effect.fail(new UserNotFoundError(userId))
yield* Effect.fail(new ValidationError(["email required"]))
```

---

## Discriminated Unions

When defining variant types, **always** use `.annotate({ discriminator, identifier })`:

### v4

```ts
const AuthInfo = Schema.Union([OAuthAuth, ApiKeyAuth])
  .annotate({ discriminator: "type", identifier: "AuthInfo" })
export type AuthInfo = Schema.Schema.Type<typeof AuthInfo>
```

### v3

```ts
const AuthInfo = Schema.Union([OAuthAuth, ApiKeyAuth])
  .annotate({ discriminator: "type", identifier: "AuthInfo" })
export type AuthInfo = Schema.Schema.Type<AuthInfo>
```

**Critical:** Use `.annotate({ discriminator: "fieldName" })` — not `.annotations({...})`.

---

## Complete Auth Flow Example

### v4 Pattern

```ts
// Branded token types
export const AccessToken = Schema.String.pipe(
  Schema.brand("AccessToken"),
  withStatics((s) => ({
    make: (token: string) => s.makeUnsafe(token),
    isValid: (t: unknown): t is Schema.Schema.Type<typeof AccessToken> =>
      typeof t === "string" && t.startsWith("eyJ"),
  })),
)

export const RefreshToken = Schema.String.pipe(
  Schema.brand("RefreshToken"),
  withStatics((s) => ({ make: (token: string) => s.makeUnsafe(token) })),
)

// Error hierarchy
export class AuthError extends Schema.TaggedErrorClass<AuthError>()("AuthError", {
  message: Schema.String,
}) {}

export class TokenExpiredError extends Schema.TaggedErrorClass<TokenExpiredError>()("TokenExpiredError", {
  tokenType: Schema.String,
}) {}

// Discriminated union variants
export const OAuthAuth = Schema.Struct({
  type: Schema.Literal("oauth"),
  code: Schema.String,
  redirectUri: Schema.String,
}).annotate({ identifier: "OAuthAuth" })

export const ApiKeyAuth = Schema.Struct({
  type: Schema.Literal("apikey"),
  key: Schema.String,
}).annotate({ identifier: "ApiKeyAuth" })

export const DeviceCodeAuth = Schema.Struct({
  type: Schema.Literal("device_code"),
  deviceCode: Schema.String,
  userCode: Schema.String,
}).annotate({ identifier: "DeviceCodeAuth" })

// Union of all auth flows
export const AuthFlow = Schema.Union(OAuthAuth, ApiKeyAuth, DeviceCodeAuth)
  .annotate({ discriminator: "type", identifier: "AuthFlow" })

export type AuthFlow = Schema.Schema.Type<typeof AuthFlow>

// Webhook payload union
export const OAuthWebhookPayload = Schema.Struct({
  event_type: Schema.Literal("oauth"),
  authorization_code: Schema.String,
  redirect_uri: Schema.String,
})

export const ApiKeyWebhook = Schema.Struct({
  event_type: Schema.Literal("apikey"),
  api_key: Schema.String,
})

export const DeviceCodeWebhook = Schema.Struct({
  event_type: Schema.Literal("device_code"),
  device_code: Schema.String,
  user_code: Schema.String,
})

export const AuthWebhook = Schema.Union(
  OAuthWebhookPayload,
  ApiKeyWebhook,
  DeviceCodeWebhook,
).annotate({ discriminator: "event_type", identifier: "AuthWebhook" })

// Exhaustive decoding with switch
export const processWebhook = (payload: unknown): Effect.Effect<AuthFlow, AuthError> =>
  Effect.gen(function* () {
    const decoded = yield* Schema.decodeUnknown(AuthWebhook)(payload)
    switch (decoded.event_type) {
      case "oauth":
        return yield* Effect.succeed({
          type: "oauth" as const,
          code: decoded.authorization_code,
          redirectUri: decoded.redirect_uri,
        })
      case "apikey":
        return yield* Effect.succeed({
          type: "apikey" as const,
          key: decoded.api_key,
        })
      case "device_code":
        return yield* Effect.succeed({
          type: "device_code" as const,
          deviceCode: decoded.device_code,
          userCode: decoded.user_code,
        })
    }
  }).pipe(
    Effect.mapError((e) => new AuthError({ message: `Invalid webhook: ${e}` })),
  )
```

---

## Custom Transforms

### v4

```ts
import { Schema, Duration, SchemaGetter } from "effect"

const DurationFromSeconds = Schema.Number.pipe(
  Schema.decodeTo(Schema.Duration, {
    decode: SchemaGetter.transform((n) => Duration.seconds(n)),
    encode: SchemaGetter.transform((d) => Duration.toSeconds(d)),
  }),
)
```

### v3

```ts
import { Schema, Duration, SchemaGetter } from "@effect/schema"

const DurationFromSeconds = Schema.Number.pipe(
  Schema.transform(
    Schema.Duration,
    Schema.Number,
    (n) => Duration.seconds(n),
    (d) => Duration.toSeconds(d),
  ),
)
```

---

## Key Migration Points: v3 to v4

| Aspect | v3 | v4 |
|--------|----|----|
| Branding | `Brand.nominal<T>()` | `Schema.brand("Name")` + `withStatics` |
| Error tagging | `Data.TaggedError` | `Schema.TaggedErrorClass` |
| Class-based data | `Data.Class` | `Schema.Class` |
| Newtype | `Newtype<T>()("Name", Schema)` | `Newtype<NewtypeT>()("Name", Schema)` |
| Imports | `@effect/schema` | `effect` |

See `migration-v3-v4.md` for complete migration guide.
