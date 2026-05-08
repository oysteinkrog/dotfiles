# Google OAuth Setup - Paste-Ready Instructions

## Before Pasting

Replace these placeholders:
- `PROJECT_ID` → Your GCloud project ID (e.g., `my-app-prod`)
- `APP_NAME` → Display name (e.g., `My App`)
- `PROD_DOMAIN` → Production URL (e.g., `https://myapp.com`)
- `SUPABASE_CALLBACK` → Callback URL (e.g., `https://xxx.supabase.co/auth/v1/callback`)

---

## Instructions to Paste

**Step 1: Configure OAuth Consent Screen**

URL: `https://console.cloud.google.com/apis/credentials/consent?project=PROJECT_ID`

1. If prompted for user type, select "External"
2. Click "Create"
3. In "App name" field, enter: `APP_NAME`
4. In "User support email", select your email from dropdown
5. Scroll to bottom
6. In "Developer contact information", enter your email
7. Click "Save and Continue"
8. On Scopes page, click "Save and Continue" (skip scopes)
9. On Test users page, click "Save and Continue" (skip)
10. Click "Back to Dashboard"

**Step 2: Create OAuth 2.0 Client ID**

URL: `https://console.cloud.google.com/apis/credentials?project=PROJECT_ID`

1. Click "+ CREATE CREDENTIALS" button (top of page)
2. Select "OAuth client ID" from dropdown
3. In "Application type", select "Web application"
4. In "Name" field, enter: `APP_NAME Web Client`
5. Under "Authorized JavaScript origins":
   - Click "ADD URI"
   - Enter: `PROD_DOMAIN`
   - Click "ADD URI" again
   - Enter: `http://localhost:3000`
6. Under "Authorized redirect URIs":
   - Click "ADD URI"
   - Enter: `SUPABASE_CALLBACK`
7. Click "Create"

**Step 3: Copy Credentials**

A dialog appears with your credentials.

Report back:
- Client ID (format: `123456789-xxxx.apps.googleusercontent.com`)
- Client Secret (format: `GOCSPX-xxxxxxxxxxxx`)

---

## After User Reports Credentials

```bash
# 1. Update Supabase auth config
curl -s -X PATCH \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -d '{
    "external_google_enabled": true,
    "external_google_client_id": "CLIENT_ID_HERE",
    "external_google_secret": "CLIENT_SECRET_HERE"
  }'

# 2. Update .env.local
cat >> .env.local << 'EOF'
GOOGLE_CLIENT_ID=CLIENT_ID_HERE
GOOGLE_CLIENT_SECRET=CLIENT_SECRET_HERE
EOF

# 3. Update Vault (if using)
vault kv patch secret/project-name \
  GOOGLE_CLIENT_ID="CLIENT_ID_HERE" \
  GOOGLE_CLIENT_SECRET="CLIENT_SECRET_HERE"

# 4. Update Vercel
echo "CLIENT_ID_HERE" | vercel env add GOOGLE_CLIENT_ID production
echo "CLIENT_SECRET_HERE" | vercel env add GOOGLE_CLIENT_SECRET production
```

## Verification

```bash
# Check Supabase config
curl -s -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  | jq '{google_enabled: .external_google_enabled, google_client_id: .external_google_client_id}'
```
