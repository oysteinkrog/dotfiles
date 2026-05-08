# CLI Authentication

Secure authentication for Rust CLI companion with subscription enforcement.

---

## Table of Contents

- [Authentication Flow](#authentication-flow)
- [Token Storage](#token-storage)
- [OAuth Login Flow](#oauth-login-flow)
- [Token Refresh](#token-refresh)
- [API Client](#api-client-with-subscription-check)
- [Account Status](#subscription-status-command)
- [Server Endpoints](#server-side-implementation)
- [API Keys Alternative](#alternative-api-keys)
- [Token Abuse Prevention](#token-abuse-prevention)
- [Local Cache Behavior](#local-cache-behavior)
- [Security Considerations](#security-considerations)

---

## Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLI AUTH FLOW                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   User runs: jsm login                                              │
│            │                                                        │
│            ▼                                                        │
│   CLI opens browser → Web app OAuth                                 │
│            │                                                        │
│            ▼                                                        │
│   User authenticates → Callback with code                           │
│            │                                                        │
│            ▼                                                        │
│   CLI exchanges code → Access token + Refresh token                 │
│            │                                                        │
│            ▼                                                        │
│   Tokens stored securely (OS keychain or encrypted file)            │
│                                                                     │
│   ─────────────────────────────────────────────────────────────     │
│                                                                     │
│   User runs: jsm sync (or any API command)                          │
│            │                                                        │
│            ▼                                                        │
│   CLI sends request with Authorization: Bearer <token>              │
│            │                                                        │
│            ▼                                                        │
│   Server validates token + checks subscription status               │
│            │                                                        │
│            ├── Active → Return data                                 │
│            │                                                        │
│            └── Inactive → 402 Payment Required                      │
│                          CLI shows "Please subscribe" message       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Status Response Mapping

| Subscription Status | HTTP Code | CLI Behavior |
|---------------------|-----------|--------------|
| Active | 200 | Full access to all commands |
| Past Due | 200 | Full access (grace period) |
| Canceled/Suspended | 402 | Error with subscribe link |
| No subscription | 402 | Error with subscribe link |
| Invalid token | 401 | Prompt to login again |

---

## Token Storage

Use OS keychain for secure credential storage.

```rust
// src/auth/keyring.rs
use keyring::Entry;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct AuthTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
}

const SERVICE_NAME: &str = "jsm-cli";

pub fn store_tokens(tokens: &AuthTokens) -> Result<(), keyring::Error> {
    let entry = Entry::new(SERVICE_NAME, "auth_tokens")?;
    let json = serde_json::to_string(tokens).unwrap();
    entry.set_password(&json)
}

pub fn get_tokens() -> Result<Option<AuthTokens>, keyring::Error> {
    let entry = Entry::new(SERVICE_NAME, "auth_tokens")?;
    match entry.get_password() {
        Ok(json) => Ok(serde_json::from_str(&json).ok()),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e),
    }
}

pub fn clear_tokens() -> Result<(), keyring::Error> {
    let entry = Entry::new(SERVICE_NAME, "auth_tokens")?;
    entry.delete_credential()
}
```

---

## OAuth Login Flow

```rust
// src/auth/login.rs
use std::io::{BufRead, BufReader, Write};
use std::net::TcpListener;
use webbrowser;

const REDIRECT_PORT: u16 = 8457;

pub async fn login() -> Result<AuthTokens, AuthError> {
    // 1. Start local server for callback
    let listener = TcpListener::bind(format!("127.0.0.1:{}", REDIRECT_PORT))?;

    // 2. Generate PKCE verifier and challenge
    let verifier = generate_pkce_verifier();
    let challenge = generate_pkce_challenge(&verifier);

    // 3. Open browser to auth URL
    let auth_url = format!(
        "{}/api/auth/cli?response_type=code&redirect_uri=http://localhost:{}/callback&code_challenge={}&code_challenge_method=S256",
        API_BASE_URL, REDIRECT_PORT, challenge
    );

    println!("Opening browser for authentication...");
    webbrowser::open(&auth_url)?;

    // 4. Wait for callback
    let (mut stream, _) = listener.accept()?;
    let reader = BufReader::new(&stream);
    let request_line = reader.lines().next().unwrap()?;

    // Parse code from: GET /callback?code=xxx HTTP/1.1
    let code = extract_code_from_request(&request_line)?;

    // Send success response to browser
    let response = "HTTP/1.1 200 OK\r\n\r\n<h1>Login successful!</h1><p>You can close this window.</p>";
    stream.write_all(response.as_bytes())?;

    // 5. Exchange code for tokens
    let tokens = exchange_code_for_tokens(&code, &verifier).await?;

    // 6. Store securely
    store_tokens(&tokens)?;

    println!("Login successful!");
    Ok(tokens)
}

async fn exchange_code_for_tokens(code: &str, verifier: &str) -> Result<AuthTokens, AuthError> {
    let client = reqwest::Client::new();
    let response = client
        .post(format!("{}/api/auth/token", API_BASE_URL))
        .json(&serde_json::json!({
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": format!("http://localhost:{}/callback", REDIRECT_PORT)
        }))
        .send()
        .await?;

    if response.status().is_success() {
        Ok(response.json().await?)
    } else {
        Err(AuthError::TokenExchangeFailed)
    }
}
```

---

## Token Refresh

```rust
// src/auth/refresh.rs
pub async fn ensure_valid_token() -> Result<String, AuthError> {
    let tokens = get_tokens()?.ok_or(AuthError::NotLoggedIn)?;

    // Check if expired (with 5 min buffer)
    let now = chrono::Utc::now().timestamp();
    if tokens.expires_at - 300 > now {
        return Ok(tokens.access_token);
    }

    // Refresh
    let client = reqwest::Client::new();
    let response = client
        .post(format!("{}/api/auth/token", API_BASE_URL))
        .json(&serde_json::json!({
            "grant_type": "refresh_token",
            "refresh_token": tokens.refresh_token
        }))
        .send()
        .await?;

    if response.status().is_success() {
        let new_tokens: AuthTokens = response.json().await?;
        store_tokens(&new_tokens)?;
        Ok(new_tokens.access_token)
    } else if response.status() == 401 {
        // Refresh token expired or revoked
        clear_tokens()?;
        Err(AuthError::SessionExpired)
    } else {
        Err(AuthError::RefreshFailed)
    }
}
```

---

## API Client with Subscription Check

```rust
// src/api/client.rs
use crate::auth::ensure_valid_token;

pub struct ApiClient {
    client: reqwest::Client,
    base_url: String,
}

impl ApiClient {
    pub async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, ApiError> {
        let token = ensure_valid_token().await?;

        let response = self.client
            .get(format!("{}{}", self.base_url, path))
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await?;

        match response.status() {
            status if status.is_success() => {
                Ok(response.json().await?)
            }
            reqwest::StatusCode::UNAUTHORIZED => {
                Err(ApiError::Unauthorized)
            }
            reqwest::StatusCode::PAYMENT_REQUIRED => {
                // Subscription inactive
                Err(ApiError::SubscriptionRequired(
                    "Your subscription is inactive. Visit https://yourapp.com/pricing to subscribe."
                ))
            }
            reqwest::StatusCode::FORBIDDEN => {
                Err(ApiError::Forbidden)
            }
            _ => {
                Err(ApiError::ServerError(response.status().as_u16()))
            }
        }
    }
}
```

---

## Subscription Status Command

```rust
// src/commands/account.rs
#[derive(Deserialize)]
struct AccountInfo {
    email: String,
    subscription_status: Option<String>,
    subscription_ends_at: Option<String>,
    provider: Option<String>,
}

pub async fn show_account_status(client: &ApiClient) -> Result<(), CliError> {
    match client.get::<AccountInfo>("/api/v1/user").await {
        Ok(info) => {
            println!("Email: {}", info.email);

            match info.subscription_status.as_deref() {
                Some("active") => {
                    println!("Status: Active");
                    if let Some(ends) = info.subscription_ends_at {
                        println!("Next billing: {}", ends);
                    }
                    if let Some(provider) = info.provider {
                        println!("Payment: {}", provider);
                    }
                }
                Some("past_due") => {
                    println!("Status: Past Due (payment retry in progress)");
                    eprintln!("\nPlease update your payment method at https://yourapp.com/settings/billing");
                }
                Some(status) => {
                    println!("Status: {}", status);
                    eprintln!("\nSubscribe at https://yourapp.com/pricing");
                }
                None => {
                    println!("Status: No subscription");
                    eprintln!("\nSubscribe at https://yourapp.com/pricing");
                }
            }
            Ok(())
        }
        Err(ApiError::SubscriptionRequired(msg)) => {
            eprintln!("{}", msg);
            Ok(())
        }
        Err(e) => Err(e.into())
    }
}
```

---

## Server-Side Implementation

### CLI Auth Endpoint

```typescript
// app/api/auth/cli/route.ts
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const codeChallenge = searchParams.get('code_challenge');
  const redirectUri = searchParams.get('redirect_uri');

  // Validate redirect_uri is localhost
  if (!redirectUri?.startsWith('http://localhost:') &&
      !redirectUri?.startsWith('http://127.0.0.1:')) {
    return Response.json({ error: 'Invalid redirect_uri' }, { status: 400 });
  }

  // Store code_challenge in session, redirect to login
  // After login, redirect to /api/auth/cli/callback with code
}
```

### Token Exchange Endpoint

```typescript
// app/api/auth/token/route.ts
export async function POST(req: Request) {
  const body = await req.json();

  if (body.grant_type === 'authorization_code') {
    // Verify PKCE challenge
    // Exchange code for tokens
    const accessToken = await generateAccessToken(userId, { expiresIn: '1h' });
    const refreshToken = await generateRefreshToken(userId);

    return Response.json({
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      token_type: 'Bearer'
    });
  }

  if (body.grant_type === 'refresh_token') {
    const userId = await verifyRefreshToken(body.refresh_token);
    if (!userId) {
      return Response.json({ error: 'Invalid refresh token' }, { status: 401 });
    }

    // Check if subscription is still active (optional: block refresh if not)
    const isActive = await isActiveSubscriber(userId);
    // We allow refresh even if inactive - the API calls will fail with 402

    const accessToken = await generateAccessToken(userId, { expiresIn: '1h' });

    return Response.json({
      access_token: accessToken,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      token_type: 'Bearer'
    });
  }
}
```

### API Middleware

```typescript
// middleware.ts or lib/auth.ts
export async function validateApiRequest(req: Request): Promise<{
  userId: string;
  isActive: boolean;
} | null> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return null;
  }

  const token = authHeader.slice(7);
  const payload = await verifyAccessToken(token);
  if (!payload) {
    return null;
  }

  const isActive = await isActiveSubscriber(payload.userId);

  return {
    userId: payload.userId,
    isActive
  };
}

// Usage in API routes
export async function GET(req: Request) {
  const auth = await validateApiRequest(req);

  if (!auth) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  if (!auth.isActive) {
    return Response.json(
      { error: 'Subscription required', subscribe_url: 'https://yourapp.com/pricing' },
      { status: 402 }
    );
  }

  // Proceed with request...
}
```

---

## Alternative: API Keys

For simpler CLI auth, use long-lived API keys instead of OAuth.

### Generate Key

```typescript
// app/api/settings/api-keys/route.ts
import { randomBytes, createHash } from 'crypto';

export async function POST(req: Request) {
  const session = await getServerSession();
  const { name } = await req.json();

  // Generate key (shown once)
  const rawKey = `jsm_${randomBytes(32).toString('hex')}`;

  // Store hash (for validation)
  const keyHash = createHash('sha256').update(rawKey).digest('hex');

  await db.apiKey.create({
    data: {
      userId: session.user.id,
      keyHash,
      name
    }
  });

  // Return raw key only once
  return Response.json({ key: rawKey, name });
}
```

### Validate Key

```typescript
export async function validateApiKey(key: string): Promise<string | null> {
  const keyHash = createHash('sha256').update(key).digest('hex');

  const apiKey = await db.apiKey.findFirst({
    where: {
      keyHash,
      revokedAt: null
    },
    include: { user: true }
  });

  if (!apiKey) return null;

  // Update last used
  await db.apiKey.update({
    where: { id: apiKey.id },
    data: { lastUsedAt: new Date() }
  });

  return apiKey.userId;
}
```

### Revoke on Subscription End

```typescript
// In webhook handler when subscription ends
async function handleSubscriptionEnded(userId: string) {
  // Revoke all API keys
  await db.apiKey.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() }
  });
}
```

### OAuth vs API Keys

| Feature | OAuth (PKCE) | API Keys |
|---------|--------------|----------|
| Security | Higher | Medium |
| Setup complexity | More complex | Simple |
| Token lifetime | Short (1hr) | Long-lived |
| Revocation | On refresh | Immediate |
| Best for | User-facing CLIs | Developer tools |

---

## Token Abuse Prevention

Prevent users from paying for one month, obtaining a token, then canceling.

### How It's Prevented

| Protection | How It Works |
|------------|--------------|
| Short-lived JWTs (1hr) | Tokens expire quickly |
| Refresh checks DB | When token expires, refresh validates subscription |
| RLS policies | Even with valid JWT, database policies block access |
| API keys revoked | Long-lived keys disabled in webhook handler |

### Token Refresh with Subscription Check

```typescript
// Token refresh with subscription check
async function refreshToken(refreshToken: string) {
  const userId = await verifyRefreshToken(refreshToken);
  if (!userId) throw new Error('Invalid refresh token');

  // Check subscription status
  const isActive = await isActiveSubscriber(userId);

  // Option 1: Block refresh entirely (strict)
  // if (!isActive) throw new Error('Subscription inactive');

  // Option 2: Allow refresh but API calls will fail with 402 (recommended)
  // The RLS policies will block actual data access anyway

  return generateAccessToken(userId);
}
```

**Note:** JWTs don't embed subscription status (unless you add custom claims). Always verify against the database on privileged requests.

---

## Local Cache Behavior

The CLI may cache previously downloaded content locally. After subscription ends:

| What Happens | Result |
|--------------|--------|
| Cached data | Remains accessible locally |
| New downloads | Blocked with 402 |
| API calls | Return subscription error |

This is an acceptable trade-off—users keep what they paid for during their active period.

```rust
// CLI behavior for inactive subscription
match client.get::<Skills>("/api/v1/skills").await {
    Ok(skills) => { /* update local cache */ }
    Err(ApiError::SubscriptionRequired(_)) => {
        eprintln!("Subscription inactive. Using cached data only.");
        eprintln!("New content requires active subscription.");
        // Fall back to local cache
        load_cached_skills()
    }
    Err(e) => return Err(e.into())
}
```

---

## Security Considerations

| Consideration | Implementation |
|---------------|----------------|
| Short-lived access tokens | 1hr expiry limits exposure if leaked |
| PKCE for OAuth | Prevents code interception attacks |
| Secure token storage | OS keychain preferred over files |
| TLS everywhere | Never send tokens over HTTP |
| Revoke on subscription end | Prevents continued access |
| Rate limiting | Protect auth endpoints |

---

## See Also

- [DATABASE.md](DATABASE.md) - API keys table schema
- [WEBHOOKS.md](WEBHOOKS.md) - Revoking keys on subscription end
- [TESTING.md](TESTING.md) - CLI auth testing patterns
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Copy-paste Rust patterns

