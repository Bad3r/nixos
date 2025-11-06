# GitHub Deployments via CLI

This guide documents how to create and manage deployment records using GitHub's Deployments API via the `gh` CLI tool.

## Overview

**Important:** GitHub Deployments are **metadata tracking only**. They record that a deployment happened but do not actually deploy code to your infrastructure.

### What GitHub Deployments Do

- ✅ Track deployment events in GitHub's UI
- ✅ Record deployment status (pending, in_progress, success, failure)
- ✅ Link deployments to specific commits/releases
- ✅ Provide deployment history and audit trail
- ✅ Integrate with GitHub's environment protection rules

### What They Don't Do

- ❌ Don't execute deployment scripts
- ❌ Don't SSH into servers
- ❌ Don't trigger any automated processes
- ❌ Don't run `./build.sh` or other deployment commands

**Actual deployment** must still be done separately (locally or via CI/CD).

## Prerequisites

```bash
# Install GitHub CLI if not already installed
# Already available in this NixOS configuration via gh package

# Authenticate
gh auth login

# Verify access
gh auth status
```

## Available Environments

This repository has two configured environments:

- `production` - Main system76 host
- `staging` - Testing environment

View environments:

```bash
gh api repos/Bad3r/nixos/environments | jq -r '.environments[].name'
```

## Creating a Deployment

### Basic Deployment Creation

```bash
# Create deployment to production
gh api repos/Bad3r/nixos/deployments \
  --method POST \
  --field ref="main" \
  --field environment="production" \
  --field description="Deploy release 2025.11.06" \
  --field auto_merge=false \
  --field production_environment=true
```

**Response includes:**

- `id` - Deployment ID (needed for status updates)
- `sha` - Git commit SHA being deployed
- `environment` - Target environment name
- `created_at` - Timestamp

**Example output:**

```json
{
  "id": 3264963045,
  "environment": "production",
  "ref": "main",
  "sha": "7033949ee31a0f709bc575378010b89a9c2cf054",
  "description": "Deploy release 2025.11.06"
}
```

### Deployment to Staging

```bash
# Create staging deployment
gh api repos/Bad3r/nixos/deployments \
  --method POST \
  --field ref="feat/my-feature" \
  --field environment="staging" \
  --field description="Test feature XYZ" \
  --field auto_merge=false \
  --field production_environment=false
```

## Updating Deployment Status

After creating a deployment, update its status to reflect the actual deployment progress.

### Set Status to In Progress

```bash
DEPLOYMENT_ID=3264963045

gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
  --method POST \
  --field state="in_progress" \
  --field description="Deploying to system76 host" \
  --field environment="production"
```

### Set Status to Success

```bash
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
  --method POST \
  --field state="success" \
  --field description="Successfully deployed release 2025.11.06" \
  --field environment="production" \
  --field log_url="https://github.com/Bad3r/nixos/releases/tag/2025.11.06"
```

### Set Status to Failure

```bash
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
  --method POST \
  --field state="failure" \
  --field description="Deployment failed: flake check error" \
  --field environment="production" \
  --field log_url="https://github.com/Bad3r/nixos/actions/runs/123456789"
```

### Available Status States

| State         | Description           | When to Use                   |
| ------------- | --------------------- | ----------------------------- |
| `pending`     | Deployment queued     | Before starting deployment    |
| `in_progress` | Deployment running    | During deployment process     |
| `success`     | Deployment completed  | After successful deployment   |
| `failure`     | Deployment failed     | If deployment fails           |
| `error`       | System error occurred | For infrastructure errors     |
| `inactive`    | Deployment superseded | When newer deployment created |

## Complete Deployment Workflow

### Example: Production Deployment

```bash
#!/bin/bash
set -e

# 1. Create deployment record
DEPLOYMENT_JSON=$(gh api repos/Bad3r/nixos/deployments \
  --method POST \
  --field ref="main" \
  --field environment="production" \
  --field description="Deploy release 2025.11.06 with language module architecture" \
  --field production_environment=true)

DEPLOYMENT_ID=$(echo "$DEPLOYMENT_JSON" | jq -r '.id')
echo "Created deployment: $DEPLOYMENT_ID"

# 2. Mark as in progress
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
  --method POST \
  --field state="in_progress" \
  --field description="Running ./build.sh on system76"

# 3. Actually deploy (this is where real work happens)
if ./build.sh; then
  # 4. Mark as success
  gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
    --method POST \
    --field state="success" \
    --field description="Deployment successful"
else
  # 4. Mark as failure
  gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
    --method POST \
    --field state="failure" \
    --field description="Build failed: $?"
  exit 1
fi
```

## Querying Deployments

### List Recent Deployments

```bash
# Get last 5 deployments
gh api repos/Bad3r/nixos/deployments | jq -r '.[] | {
  id: .id,
  environment: .environment,
  ref: .ref,
  description: .description,
  created_at: .created_at
}' | head -20
```

### View Specific Deployment

```bash
DEPLOYMENT_ID=3264963045

gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID | jq '{
  id: .id,
  environment: .environment,
  ref: .ref,
  sha: .sha,
  description: .description,
  created_at: .created_at
}'
```

### Get Deployment Statuses

```bash
# View status history for a deployment
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses | jq -r '.[] | {
  state: .state,
  description: .description,
  created_at: .created_at
}'
```

### Filter by Environment

```bash
# Get production deployments only
gh api repos/Bad3r/nixos/deployments | jq -r '.[] | select(.environment == "production") | {
  id: .id,
  ref: .ref,
  description: .description,
  created_at: .created_at
}'
```

## Integration with Releases

Link deployments to releases for better tracking:

```bash
RELEASE_TAG="2025.11.06"
RELEASE_URL="https://github.com/Bad3r/nixos/releases/tag/$RELEASE_TAG"

# Get the commit SHA for the release
COMMIT_SHA=$(git rev-parse $RELEASE_TAG)

# Create deployment pointing to release
gh api repos/Bad3r/nixos/deployments \
  --method POST \
  --field ref="$RELEASE_TAG" \
  --field environment="production" \
  --field description="Deploy release $RELEASE_TAG" \
  --field production_environment=true

# Mark as successful with release link
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID/statuses \
  --method POST \
  --field state="success" \
  --field description="Deployed release $RELEASE_TAG to system76" \
  --field log_url="$RELEASE_URL"
```

## Best Practices

### 1. Always Set Environment Correctly

```bash
# For production
--field production_environment=true

# For staging/testing
--field production_environment=false
```

### 2. Include Descriptive Messages

```bash
# Good
--field description="Deploy release 2025.11.06 with language module architecture"

# Bad
--field description="deploy"
```

### 3. Link to Relevant Resources

```bash
# Link to release
--field log_url="https://github.com/Bad3r/nixos/releases/tag/2025.11.06"

# Link to workflow run
--field log_url="https://github.com/Bad3r/nixos/actions/runs/19128498819"

# Link to commit
--field log_url="https://github.com/Bad3r/nixos/commit/7033949ee"
```

### 4. Update Status Promptly

Don't leave deployments in `in_progress` state indefinitely. Always update to final status.

### 5. Use Consistent Environment Names

Stick to the configured environments: `production` and `staging`.

## Actual Deployment Process

Remember: After creating a deployment record, you still need to **actually deploy**:

### Local Deployment (Current Method)

```bash
# On system76 machine
cd /home/vx/nixos
git pull origin main
./build.sh  # Validates, builds, and switches generation
```

### Automated Deployment (Future)

For actual automated deployment, you would need:

1. **SSH Access** - Configure SSH keys in GitHub Secrets
2. **Deployment Workflow** - Create `.github/workflows/deploy.yml`
3. **Security** - Set up proper authentication and authorization
4. **Rollback Strategy** - Plan for deployment failures

Example workflow (not implemented):

```yaml
name: Deploy to Production
on:
  release:
    types: [published]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Deploy via SSH
        run: |
          ssh system76 "cd /home/vx/nixos && git pull && ./build.sh"
```

## Troubleshooting

### Deployment Creation Fails

```bash
# Check authentication
gh auth status

# Verify repository access
gh api repos/Bad3r/nixos | jq '.permissions'
```

### Can't Update Status

```bash
# Verify deployment exists
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID

# Check if deployment ID is correct
gh api repos/Bad3r/nixos/deployments | jq '.[0].id'
```

### Invalid Environment

```bash
# List available environments
gh api repos/Bad3r/nixos/environments | jq -r '.environments[].name'

# Environment is created automatically on first use
# Just use consistent names: 'production' or 'staging'
```

## Related Commands

```bash
# View deployment in browser
gh api repos/Bad3r/nixos/deployments/$DEPLOYMENT_ID | jq -r '.url' | xargs gh browse

# List all environments
gh api repos/Bad3r/nixos/environments

# View environment details
gh api repos/Bad3r/nixos/environments/production
```

## References

- [GitHub Deployments API Documentation](https://docs.github.com/en/rest/deployments/deployments)
- [GitHub CLI Manual](https://cli.github.com/manual/)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)

## Summary

GitHub Deployments provide deployment tracking but don't execute deployments:

| Action                       | Tool         | Purpose                            |
| ---------------------------- | ------------ | ---------------------------------- |
| **Create deployment record** | `gh api`     | Track that deployment is happening |
| **Update status**            | `gh api`     | Record deployment progress/result  |
| **Actual deployment**        | `./build.sh` | Apply changes to system76 host     |

Always remember: GitHub Deployments are for **tracking**, actual deployment is **separate**.
