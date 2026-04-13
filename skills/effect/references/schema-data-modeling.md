# Schema & Data Modeling

## Branded Types

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

**Rule:** If two strings have different domains, they should be different branded types.

## Data Classes

```ts
class User extends Schema.Class<User>("User")({
  id: UserID,
  email: Schema.String,
  name: Schema.String,
  createdAt: Schema.DateTimeUtc,
}) {}
```

## Tagged Error Classes

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

## Discriminated Unions

When defining variant types, **always** use `.annotate({ discriminator, identifier })`:
```ts
const AuthInfo = Schema.Union([OAuthAuth, ApiKeyAuth])
  .annotate({ discriminator: "type", identifier: "AuthInfo" })
export type AuthInfo = Schema.Schema.Type<typeof AuthInfo>
```

**Critical:** Use `.annotate({ discriminator: "fieldName" })` — not `.annotations({...})`.

## Complete Auth Flow Example

A full discriminated union auth schema with webhook validation:

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

## Custom Transforms

```ts
import { Schema, Duration, SchemaGetter } from "effect"

const DurationFromSeconds = Schema.Number.pipe(
  Schema.decodeTo(Schema.Duration, {
    decode: SchemaGetter.transform((n) => Duration.seconds(n)),
    encode: SchemaGetter.transform((d) => Duration.toSeconds(d)),
  }),
)
```

## Newtype (Nominal wrapper)

For scalar types needing class-based nominal typing with inheritance:
```ts
import { Newtype, Schema } from "effect"

class SessionID extends Newtype<SessionID>()("SessionID", Schema.String) {}
```

Use `Schema.brand` + `withStatics` for simple IDs. Use `Newtype` when you need class methods or `instanceof` checks.
