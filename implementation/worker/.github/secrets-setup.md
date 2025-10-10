# GitHub Secrets Setup

## Required Secrets for CI/CD

The following secrets need to be added to your GitHub repository for automated deployments:

### 1. Cloudflare API Token (`CLOUDFLARE_API_TOKEN`)

- Required for deploying Workers
- Create at: https://dash.cloudflare.com/profile/api-tokens
- Permissions needed:
  - Account: Workers Scripts:Edit
  - Account: Workers KV Storage:Edit
  - Account: Workers R2 Storage:Edit
  - Account: D1:Edit
  - Account: Analytics Engine:Edit
  - Account: AI:Edit

### 2. Cloudflare Account ID (`CLOUDFLARE_ACCOUNT_ID`)

- Found in Cloudflare dashboard URL or account settings
- Format: 32-character string

### 3. API Key (`API_KEY`)

- Used for protected admin endpoints
- Generate a secure random key

### 4. AI Gateway Token (`AI_GATEWAY_TOKEN`)

- Authentication token for AI Gateway
- Required for authenticated AI Gateway requests

## How to Add Secrets to GitHub

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with the name and value specified above

## GitHub Actions Workflow Update

Ensure your deployment workflow includes the AI Gateway token:

```yaml
name: Deploy Worker

on:
  push:
    branches: [main, staging]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: "20"

      - name: Install dependencies
        run: npm ci

      - name: Deploy to Cloudflare Workers
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
        run: |
          # Set secrets before deployment
          echo "${{ secrets.API_KEY }}" | npx wrangler secret put API_KEY
          echo "${{ secrets.AI_GATEWAY_TOKEN }}" | npx wrangler secret put AI_GATEWAY_TOKEN

          # Deploy based on branch
          if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
            npx wrangler deploy --env production
          else
            npx wrangler deploy --env staging
          fi
```

## Environment-Specific Secrets

If you have different tokens for staging and production:

- `AI_GATEWAY_TOKEN_STAGING`: Staging environment token
- `AI_GATEWAY_TOKEN_PRODUCTION`: Production environment token

Update the workflow accordingly to use the appropriate secret for each environment.
