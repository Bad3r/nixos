# GitHub Actions Secrets Setup Guide

## ✅ Secrets Successfully Configured

The following secrets have been added to the repository:

| Secret Name | Status | Description |
|-------------|--------|-------------|
| `CLOUDFLARE_ACCOUNT_ID` | ✅ Added | Your Cloudflare account ID |
| `MODULE_API_KEY` | ✅ Added | API key for module upload authentication |
| `CLOUDFLARE_API_TOKEN` | ⚠️ Manual Setup Required | Cloudflare API token for deployments |

## 🔑 Manual Setup Required: CLOUDFLARE_API_TOKEN

You need to create a Cloudflare API token with appropriate permissions:

### Option 1: Create Custom Token (Recommended)

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click **"Create Token"**
3. Use **"Custom token"** template
4. Configure the following permissions:
   - **Account** → Cloudflare Workers Scripts:Edit
   - **Account** → Cloudflare Pages:Edit
   - **Account** → D1:Edit
   - **Account** → Workers KV Storage:Edit
   - **Account** → Workers R2 Storage:Edit
   - **Zone** → Zone:Read (optional, for custom domains)

5. Under **Account Resources**:
   - Include → `28375972d83d8943ad779dc380fea05d`

6. Click **"Continue to summary"** → **"Create Token"**
7. Copy the token (you won't see it again!)

### Option 2: Use Global API Key

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Scroll down to **"Global API Key"**
3. Click **"View"** and enter your password
4. Copy the key

### Add the Token to GitHub

Once you have the token, run:

```bash
gh secret set CLOUDFLARE_API_TOKEN --repo Bad3r/nixos
```

## 📋 Configured Values

- **Account ID**: `28375972d83d8943ad779dc380fea05d`
- **Module API Key**: Generated and stored securely
- **Repository**: `Bad3r/nixos`

## 🚀 Next Steps

1. Create and add the `CLOUDFLARE_API_TOKEN` as described above
2. Create GitHub environments (optional but recommended):
   ```bash
   # Create staging environment
   gh api --method PUT -H "Accept: application/vnd.github+json" \
     /repos/Bad3r/nixos/environments/staging

   # Create production environment
   gh api --method PUT -H "Accept: application/vnd.github+json" \
     /repos/Bad3r/nixos/environments/production
   ```

3. Test the workflow:
   ```bash
   # Trigger the workflow manually
   gh workflow run deploy-module-docs.yml \
     --ref feat/cf-auto-docs-api \
     -f environment=staging
   ```

## 🔧 Troubleshooting

If the workflow fails:

1. **Check secret names**: Ensure all secrets are named exactly as listed
2. **Verify permissions**: The API token needs the permissions listed above
3. **Check logs**: View workflow logs with:
   ```bash
   gh run list --workflow=deploy-module-docs.yml
   gh run view <run-id>
   ```

## 📝 Environment Variables in Worker

The Worker also needs these environment variables set in `wrangler.jsonc`:

```jsonc
{
  "vars": {
    "API_KEY": "use-wrangler-secret-instead",
    "ENVIRONMENT": "staging"
  }
}
```

For production secrets, use:
```bash
cd implementation/worker
npx wrangler secret put API_KEY --env staging
npx wrangler secret put API_KEY --env production
```

---

*Generated: 2025-10-08*