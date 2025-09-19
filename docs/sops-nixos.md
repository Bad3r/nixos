# SOPS on NixOS: Comprehensive Guide to Secret Management

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture-overview)
3. [Installation and Setup](#installation-and-setup)
4. [Key Management](#key-management)
5. [Basic Usage](#basic-usage)
6. [Advanced Patterns](#advanced-patterns)
7. [Security Best Practices](#security-best-practices)
8. [Troubleshooting](#troubleshooting)
9. [Migration Strategies](#migration-strategies)
10. [Real-World Examples](#real-world-examples)
11. [Reference](#reference)
12. [Quick Reference](#quick-reference)
13. [Conclusion](#conclusion)

## Introduction

SOPS (Secrets OPerationS) is Mozilla's encrypted file editor that enables secure storage of secrets in version control. The `sops-nix` project provides atomic, declarative, and reproducible secret provisioning for NixOS, integrating seamlessly with the NixOS philosophy of declarative system configuration.

### Key Benefits

- **Version Control Friendly**: Encrypted files can be committed directly to Git with readable diffs
- **Declarative Configuration**: Secrets are defined alongside system configuration
- **Multiple Encryption Methods**: Supports age, GPG, SSH keys, and cloud KMS
- **Atomic Deployment**: Secrets are updated atomically during system activation
- **Runtime-Only Decryption**: Secrets are never decrypted during build time
- **Fine-Grained Access Control**: Per-secret permissions and ownership

### When to Use SOPS

SOPS is ideal for:

- Application secrets (API keys, database passwords)
- Service configuration with embedded secrets
- User passwords and authentication tokens
- TLS certificates and private keys
- CI/CD secrets for local testing

## Architecture Overview

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Build Time                            │
├─────────────────────────────────────────────────────────────┤
│  .sops.yaml     →  Defines encryption rules and recipients   │
│  secrets/*.yaml →  Encrypted secret files (in Nix store)     │
│  configuration.nix → Secret declarations and permissions     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Activation Time                          │
├─────────────────────────────────────────────────────────────┤
│  sops-nix activation → Decrypts secrets using host keys      │
│  /run/secrets/      → Tmpfs mount with decrypted secrets     │
│  systemd services   → Access secrets via configured paths    │
└─────────────────────────────────────────────────────────────┘
```

### Secret Lifecycle

1. **Creation**: Developer creates/edits secrets with `sops` command
2. **Encryption**: SOPS encrypts values (not keys) using configured recipients
3. **Storage**: Encrypted files stored in version control
4. **Build**: NixOS includes encrypted files in system derivation
5. **Activation**: sops-nix decrypts secrets during `nixos-rebuild switch`
6. **Runtime**: Services access plaintext secrets from `/run/secrets`

### Storage Locations

- **System Secrets**: `/run/secrets` (symlink to `/run/secrets.d/{generation}`)
- **User Secrets**: `$XDG_RUNTIME_DIR/secrets.d` (home-manager)
- **Host Keys**: `/var/lib/sops-nix/key.txt` (age) or GPG keyring
- **Encrypted Files**: Typically in `./secrets/` directory in your config

## Installation and Setup

### 1. Add sops-nix to Your Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Generate Host Keys

#### Using Age (Recommended)

```bash
# Generate age key for the host
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt

# Get the public key for .sops.yaml
sudo grep "public key:" /var/lib/sops-nix/key.txt | cut -d: -f2 | tr -d ' '
```

#### Converting SSH Keys to Age

```bash
# Convert existing SSH host key
nix-shell -p ssh-to-age --run \
  "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
```

### 3. Create .sops.yaml Configuration

> Repository note: `.sops.yaml` is generated from
> `modules/security/sops-policy.nix` via the `files` module. Update that
> module (or rotate the referenced Age keys) rather than editing the
> rendered file in place.

```yaml
# .sops.yaml
keys:
  # User keys for editing secrets
  - &admin_alice age1teupt3wxdyz454jmdf09c6387hafkg26tr8eqm9tawv53p29rfaqjq0dvu

  # Host keys for decryption
  - &host_server1 age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3e8s7p
  - &host_laptop age1xjcuh2cccassyqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqslzq7pq

creation_rules:
  # Default rule for all secrets
  - path_regex: secrets/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - age:
          - *admin_alice
          - *host_server1
          - *host_laptop

  # Production secrets - restricted access
  - path_regex: secrets/production/[^/]+\.yaml$
    key_groups:
      - age:
          - *admin_alice
          - *host_server1

  # Development secrets
  - path_regex: secrets/development/[^/]+\.yaml$
    key_groups:
      - age:
          - *admin_alice
          - *host_laptop
```

### 4. Basic NixOS Configuration

```nix
{ config, pkgs, ... }:
{
  # Configure sops-nix
  sops = {
      # Default sops file
      defaultSopsFile = ./secrets/common.yaml;
      defaultSopsFormat = "yaml";

    # Age key location
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true; # Generate if doesn't exist
      sshKeyPaths = [ ]; # Don't use SSH keys
    };

    # Define secrets
    secrets = {
      # Simple secret
      "database_password" = { };

      # Secret with custom permissions
      "nginx/htpasswd" = {
        mode = "0440";
        owner = config.users.users.nginx.name;
        group = config.users.users.nginx.group;
      };

      # Secret needed before users are created
      "user_password_hash" = {
        neededForUsers = true;
      };
    };
  };
  }
```

> Note
> Using `defaultSopsFile` places the encrypted file in the Nix store (safe — content remains encrypted).
> If you prefer not to reference encrypted files from the store, declare per‑secret `sopsFile` with absolute
> paths and/or set `sops.validateSopsFiles = false` to relax store validation.

## Key Management

### Age vs GPG Comparison

| Feature         | Age                     | GPG                 |
| --------------- | ----------------------- | ------------------- |
| Simplicity      | ✅ Simple, modern       | ❌ Complex, legacy  |
| Key Format      | Single line             | Multi-line armored  |
| SSH Integration | Ed25519 only            | RSA only            |
| Reliability     | ✅ Stable               | ⚠️ Daemon issues    |
| Ecosystem       | Growing                 | Mature              |
| Recommendation  | ✅ Use for new projects | Legacy support only |

### Key Generation Strategies

#### 1. Per-Host Age Keys (Recommended)

```nix
{ config, ... }:
{
  sops.age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    generateKey = true;
  };
}
```

#### 2. SSH-Based Keys

```nix
{ config, ... }:
{
  sops.age = {
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    keyFile = "/var/lib/sops-nix/key.txt";
  };
}
```

#### 3. User Keys for Development

```bash
# Generate personal age key
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Or convert SSH key
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

### Key Rotation

```bash
# Update .sops.yaml with new recipients
vim .sops.yaml

# Update all encrypted files
find secrets -name "*.yaml" -exec sops updatekeys {} \;

# Verify encryption
  sops -d secrets/example.yaml
```

### Optional: Derive age recipients from your GitHub SSH keys (single admin)

You can bootstrap recipients from your GitHub account’s SSH keys, which is convenient if you rotate keys in GitHub and want your `.sops.yaml` to reflect that.

Option A (no extra tooling):

```bash
# Prints age recipients for all your GitHub SSH public keys
curl -s https://github.com/<your-github-username>.keys | ssh-to-age
```

Option B (packaged helper):

```bash
# Explore options
nix run .#github-to-sops -- --help

# Typical flow (inspect output before applying):
# nix run .#github-to-sops -- --user <your-github-username> > /tmp/recipients.age
```

Add or update these recipients under the appropriate rules in `.sops.yaml`, then run `sops updatekeys` on affected files.

## Basic Usage

### Creating Secrets

#### 1. Create a New Secret File

```bash
# Create new encrypted file
sops secrets/database.yaml
```

Example content:

```yaml
postgres:
  password: supersecret123
  connection_string: postgresql://user:pass@localhost/db

redis:
  password: redis-secret-456

  certificates:
    private_key: |
      -----BEGIN EXAMPLE KEY-----
      REDACTED-EXAMPLE-KEY-MATERIAL
      -----END EXAMPLE KEY-----
```

#### 2. Declare in NixOS Configuration

```nix
{ config, ... }:
{
  sops.secrets = {
    "postgres/password" = {
      sopsFile = ./secrets/database.yaml;
    };
    "redis/password" = {
      sopsFile = ./secrets/database.yaml;
      owner = "redis";
    };
  };

  # Enable PostgreSQL; set/change passwords at runtime (not evaluation).
  # See "Example 1: PostgreSQL with Rotating Passwords" below for a
  # postStart pattern that reads the secret file at activation/runtime.
  services.postgresql.enable = true;
}
```

### File Formats

#### YAML (Default)

```yaml
api_key: secret123
nested:
  value: secret456
```

#### JSON

```json
{
  "api_key": "secret123",
  "nested": {
    "value": "secret456"
  }
}
```

#### dotenv

```env
API_KEY=secret123
DATABASE_URL=postgresql://localhost/db
```

#### Binary Files

```bash
# Encrypt binary file
sops -e certificate.pem > certificate.pem.enc

# Use in NixOS
sops.secrets."certificate" = {
  format = "binary";
  sopsFile = ./certificate.pem.enc;
};
```

## Advanced Patterns

### Home Manager example: Context7 MCP API key

1. **Encrypt** the payload so only ciphertext is tracked:

   ```bash
   sops secrets/context7.yaml
   # Add/rotate the `context7_api_key` attribute, save, exit
   ```

2. **Declare** the secret for Home Manager, emitting it to the runtime
   directory with `%r`:

   ```nix
   sops.secrets."context7/api-key" = {
     sopsFile = ./../../secrets/context7.yaml;
     key = "context7_api_key";
     path = "%r/context7/api-key";
     mode = "0400";
   };
   ```

3. **Consume** the decrypted path lazily at runtime (never during
   evaluation):

   ```nix
   let hasContext7 = config.sops.secrets ? "context7/api-key"; in
   tools.mcp_servers =
     (if hasContext7 then {
        context7.command = "${context7Wrapper}/bin/context7-mcp";
        context7.args = [ ];
      } else {})
     // otherServers;
   ```

The wrapper (`pkgs.writeShellApplication`) shells out to `npx` with the
decrypted key. Evaluation stays pure, and the MCP server receives the key
exactly where it expects it during activation.

### Templates

Templates allow embedding multiple secrets into configuration files. By default, rendered templates are written to
`/run/secrets/rendered/<name>`; you can override the destination with the `path` option.

```nix
{ config, ... }:
{
  sops.secrets = {
    db_user = { };
    db_password = { };
    db_host = { };
  };

  sops.templates."database.conf".content = ''
    [database]
    host = ${config.sops.placeholder.db_host}
    user = ${config.sops.placeholder.db_user}
    password = ${config.sops.placeholder.db_password}
    pool_size = 10
  '';

  systemd.services.myapp = {
    serviceConfig.ExecStart =
      "${pkgs.myapp}/bin/myapp --config ${config.sops.templates."database.conf".path}";
  };
}
```

### Service Integration

#### Restart on Secret Change

```nix
{
  sops.secrets."api_key" = {
    restartUnits = [ "myservice.service" ];
  };

  systemd.services.myservice = {
    serviceConfig = {
      EnvironmentFile = config.sops.secrets."api_key".path;
    };
  };
}
```

#### Symlinks to Expected Locations

```nix
{
  sops.secrets."app_config" = {
    path = "/var/lib/myapp/secret.conf";
    owner = "myapp";
    mode = "0400";
  };
}
```

### Home-Manager Integration

```nix
# home.nix
{ config, pkgs, ... }:
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ./secrets/user.yaml;

    secrets = {
      ssh_key = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
        mode = "0600";
      };
      github_token = { };
    };
  };

  home.packages = [
    config.flake.packages.${pkgs.system}.git-credential-sops
  ];

  # Configure Git per-URL to use the credential helper for GitHub.
  # Run these once for the user (helper is provided by the system profile):
  #   export SOPS_GIT_TOKEN_PATH=/run/secrets/act/github_token
  #   git config --global credential.useHttpPath true
  #   git config --global 'credential.https://github.com.helper' '!git-credential-sops'
}
```

> Repository default: the shared Home-Manager base module sets
> `sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt"`
> (via `lib.mkDefault`). Create this file—or override the option—before running
> `home-manager switch` to avoid decryption failures.

### CI/CD Integration

#### GitHub Actions with act

```nix
{ config, ... }:
{
  sops.secrets.github_token = {
    sopsFile = ./secrets/act.yaml;
  };

  sops.templates."act-secrets.env" = {
    content = ''
      GITHUB_TOKEN=${config.sops.placeholder.github_token}
    '';
    path = "/etc/act/secrets.env";
    mode = "0400";
  };
}
```

Usage:

```bash
# Run locally with secrets
act --secret-file /etc/act/secrets.env
```

Recommended: use a stable path such as `/etc/act/secrets.env` with strict permissions (e.g., `0400`) and assign
ownership to the user or service that runs `act`. A user‑scoped path under `$HOME/.config/act/secrets` is an
alternative if system‑wide configuration is not desired.

### Kubernetes Integration (KSOPS)

```yaml
# secret-generator.yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: secret-generator
files:
  - ./secrets/k8s-secrets.enc.yaml
```

```bash
# Build with kustomize
kustomize build --enable-alpha-plugins .
```

## Security Best Practices

### 1. Key Management

- **Never commit plaintext secrets** - Use pre-commit hooks
- **Store age keys securely** - Backup `/var/lib/sops-nix/key.txt`
- **Use separate keys for environments** - Production vs development
- **Rotate keys regularly** - Update recipients and re-encrypt
- **Audit key access** - Track who has decryption capabilities

### 2. File Permissions

```nix
{
  sops.secrets.sensitive = {
    mode = "0400";     # Read-only for owner
    owner = "service"; # Specific service user
    group = "service"; # Specific service group
  };
  }
```

Note: The parent directory for system secrets, `/run/secrets.d/<N>`, is owned by `root` with the `keys` group and
restrictive traversal. Ensure your service user is the file owner or that group ownership/permissions are set appropriately
if group access is required.

### 3. Secret Scope

- **Principle of least privilege** - Only decrypt on hosts that need secrets
- **Separate secret files** - Don't mix production and development
- **Use path_regex** - Fine-grained access control in .sops.yaml

### 4. Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: sops-encryption
        name: Ensure SOPS encryption
        entry: pre-commit-hook-ensure-sops
        language: system
        files: ^secrets/.*\.(yaml|json|env)$
```

### 5. Avoid Common Pitfalls

```nix
# ❌ NEVER: Secrets in Nix strings
services.myapp.config = ''
  password = "plaintext"  # Goes to world-readable Nix store!
'';

# ✅ CORRECT: Reference secret path
services.myapp.configFile = config.sops.secrets.password.path;

# ❌ NEVER: Import secrets at evaluation time
let
  password = builtins.readFile ./secret.txt;  # Evaluation-time read!
in { ... }

# ✅ CORRECT: Use sops-nix activation
sops.secrets.password = { };
```

## Troubleshooting

### Common Issues and Solutions

#### 1. "No such file or directory" Error

**Cause**: Service starting before sops-nix activation

**Solution**:

```nix
systemd.services.myservice.unitConfig = {
  After = [ "sops-nix.service" ];
  Wants = [ "sops-nix.service" ];
};
```

#### 2. Permission Denied

**Cause**: Wrong ownership or permissions

**Debug**:

```bash
ls -la /run/secrets/
stat /run/secrets/mysecret
```

**Solution**:

```nix
sops.secrets.mysecret = {
  owner = config.systemd.services.myservice.serviceConfig.User;
  mode = "0400";
};
```

#### 3. Decryption Failed

**Cause**: Missing or wrong keys

**Debug**:

```bash
# Check key exists
sudo cat /var/lib/sops-nix/key.txt

# Test decryption manually
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt \
  sops -d secrets/test.yaml
```

**Solution**: Ensure host key is in .sops.yaml and run `sops updatekeys`

#### 4. Secrets Not Updated

**Cause**: Cached activation

**Solution**:

```bash
# Force activation
sudo systemctl restart sops-nix
# Or rebuild
sudo nixos-rebuild switch --flake .#hostname
```

#### 5. GPG Issues

**Symptoms**: Hanging, daemon errors

**Solution**: Switch to age

```nix
sops.gnupg.sshKeyPaths = [];
sops.age.keyFile = "/var/lib/sops-nix/key.txt";
```

### Debug Commands

```bash
# Check sops-nix service status
systemctl status sops-nix

# View service logs
journalctl -u sops-nix -b

# List all secrets
ls -la /run/secrets/

# Check secret content (carefully!)
sudo cat /run/secrets/mysecret

# Verify sops file structure
sops -d --extract '["_metadata"]' secrets/file.yaml

# Test template rendering
nix eval --raw .#nixosConfigurations.hostname.config.sops.templates."mytemplate".content
```

## Migration Strategies

### From Environment Files

```bash
# Convert .env to encrypted YAML
cat .env | yq -p props -o yaml | sops -e /dev/stdin > secrets/env.yaml
```

### From pass

```bash
# Export from pass
for secret in $(pass ls | grep -v Password); do
  echo "$secret: |"
  pass show "$secret" | sed 's/^/  /'
done | sops -e /dev/stdin > secrets/migrated.yaml
```

### From Ansible Vault

```bash
# Decrypt Ansible vault
ansible-vault decrypt vault.yml --output=- | \
  sops -e /dev/stdin > secrets/ansible.yaml
```

### From Kubernetes Secrets

```bash
# Export and encrypt
kubectl get secret mysecret -o yaml | \
  yq '.data | map_values(@base64d)' | \
  sops -e /dev/stdin > secrets/k8s.yaml
```

## Real-World Examples

### Example 1: PostgreSQL with Rotating Passwords

```nix
{ config, pkgs, lib, ... }:
{
  sops.secrets = {
    "postgresql/password" = {
      sopsFile = ./secrets/database.yaml;
      owner = "postgres";
      restartUnits = [ "postgresql.service" ];
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "myapp" ];
    ensureUsers = [{
      name = "myapp";
      ensurePermissions = {
        "DATABASE myapp" = "ALL PRIVILEGES";
      };
    }];
  };

  systemd.services.postgresql.postStart = lib.mkAfter ''
    $PSQL -c "ALTER USER myapp PASSWORD '$(cat ${config.sops.secrets."postgresql/password".path})'"
  '';
}
```

### Example 2: Nginx with Basic Auth

```nix
{ config, pkgs, ... }:
{
  sops.templates."nginx-htpasswd" = {
    content = ''
      admin:${config.sops.placeholder."nginx/admin_password_hash"}
      user:${config.sops.placeholder."nginx/user_password_hash"}
    '';
    owner = "nginx";
    mode = "0400";
  };

  services.nginx = {
    enable = true;
    virtualHosts."secure.example.com" = {
      basicAuth = {
        enable = true;
        file = config.sops.templates."nginx-htpasswd".path;
      };
    };
  };
}
```

### Example 3: Backup Encryption Keys

```nix
{ config, pkgs, ... }:
{
  sops.secrets = {
    "backup/encryption_key" = {
      owner = "root";
      mode = "0400";
    };
    "backup/b2_credentials" = {
      owner = "root";
      mode = "0400";
    };
  };

  services.restic.backups.system = {
    repository = "b2:mybucket:system-backups";
    passwordFile = config.sops.secrets."backup/encryption_key".path;
    environmentFile = config.sops.secrets."backup/b2_credentials".path;

    paths = [ "/var/lib" "/etc" ];
    timerConfig = {
      OnCalendar = "daily";
    };
  };
}
```

### Example 4: Multi-Environment Configuration

```nix
{ config, hostname, ... }:
let
  environment = if hostname == "prod-server" then "production" else "development";
in
{
  sops = {
    defaultSopsFile = ./secrets/${environment}/common.yaml;

    secrets = {
      "api_key" = { };
      "database_url" = { };
      "jwt_secret" = { };
    };

    templates."app.env" = {
      content = ''
        NODE_ENV=${environment}
        API_KEY=${config.sops.placeholder.api_key}
        DATABASE_URL=${config.sops.placeholder.database_url}
        JWT_SECRET=${config.sops.placeholder.jwt_secret}
      '';
    };
  };

  systemd.services.webapp = {
    serviceConfig = {
      EnvironmentFile = config.sops.templates."app.env".path;
      ExecStart = "${pkgs.nodejs}/bin/node /var/lib/webapp/index.js";
    };
  };
}
```

### Example 5: GitHub Actions Integration (user‑scoped path)

```nix
{ config, pkgs, ... }:
  {
  sops.secrets.github_token = {
    sopsFile = ./secrets/ci.yaml;
    owner = config.users.users.developer.name;
  };

    # Alternative: write act secrets under the user's home instead of a system path.
    sops.templates."act-secrets" = {
    content = ''
      GITHUB_TOKEN=${config.sops.placeholder.github_token}
      NPM_TOKEN=${config.sops.placeholder.npm_token}
      DOCKER_TOKEN=${config.sops.placeholder.docker_token}
    '';
    path = "/home/developer/.config/act/secrets";
    owner = config.users.users.developer.name;
    mode = "0400";
  };

  environment.systemPackages = with pkgs; [
    (writeScriptBin "ci-test" ''
      #!${stdenv.shell}
      act --secret-file ~/.config/act/secrets "$@"
    '')
  ];
}
```

## Reference

### Essential Commands

```bash
# Create/edit secrets
sops secrets/file.yaml

# Decrypt to stdout
sops -d secrets/file.yaml

# Extract specific key
sops -d --extract '["database"]["password"]' secrets/file.yaml

# Update recipients
sops updatekeys secrets/file.yaml

# Rotate data key
sops -r secrets/file.yaml

# Convert formats
  sops -d secrets/file.yaml | sops -e --input-type yaml --output-type json /dev/stdin
```

### Configuration Options

#### Core Options

```nix
{
  sops = {
    # Default secret file
    defaultSopsFile = ./secrets/default.yaml;

    # Default format (yaml, json, dotenv, ini, binary)
    defaultSopsFormat = "yaml";

    # Validate secrets against sops files at build time
    validateSopsFiles = true;

    # Secret definitions
    secrets = { };

    # Template definitions
    templates = { };
  };
}
```

> Note
> Using `defaultSopsFile` will reference encrypted files from the Nix store (safe). If you prefer to avoid this,
> declare per‑secret `sopsFile` with absolute paths and/or set `sops.validateSopsFiles = false` to relax store validation.

#### Age Configuration

```nix
{
  sops.age = {
    # Age key file location
    keyFile = "/var/lib/sops-nix/key.txt";

    # Generate key if doesn't exist
    generateKey = false;

    # SSH keys to import as age keys
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
```

#### Secret Options

```nix
{
  sops.secrets."name" = {
    # Source file (overrides defaultSopsFile)
    sopsFile = ./secrets/specific.yaml;

    # Format (overrides defaultSopsFormat)
    format = "yaml";

    # Key within the file (empty for whole file)
    key = "path/to/secret";

    # Output path (default: /run/secrets/name)
    path = "/custom/path";

    # File mode (octal)
    mode = "0400";

    # Owner user
    owner = "username";

    # Owner group
    group = "groupname";

    # Restart these units on change
    restartUnits = [ "service.service" ];

    # Reload these units on change
    reloadUnits = [ "other.service" ];

    # Needed before users are created
    neededForUsers = false;
  };
}
```

### Tools and Utilities

| Tool                          | Purpose                 | Installation                       |
| ----------------------------- | ----------------------- | ---------------------------------- |
| `sops`                        | Secret editor           | `pkgs.sops`                        |
| `age`                         | Modern encryption       | `pkgs.age`                         |
| `ssh-to-age`                  | Convert SSH to age keys | `pkgs.ssh-to-age`                  |
| `ssh-to-pgp`                  | Convert SSH to GPG keys | `pkgs.ssh-to-pgp`                  |
| `sops-init-gpg-key`           | Generate GPG keys       | Part of sops-nix                   |
| `pre-commit-hook-ensure-sops` | Pre-commit validation   | `pkgs.pre-commit-hook-ensure-sops` |
| `kustomize-sops`              | Kubernetes integration  | `pkgs.kustomize-sops`              |
| `github-to-sops`              | GitHub SSH → recipients | `pkgs.github-to-sops`              |

### Environment Variables

```bash
# Age key file
export SOPS_AGE_KEY_FILE=/path/to/key.txt

# Age key directly
export SOPS_AGE_KEY="AGE-SECRET-KEY-..."

# GPG executable
export SOPS_GPG_EXEC=/usr/bin/gpg2

# AWS KMS (if using)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
```

### Links and Resources

- [sops-nix Repository](https://github.com/Mic92/sops-nix)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [age Specification](https://github.com/FiloSottile/age)
  - [NixOS Manual - Secrets Management](https://nixos.org/manual/nixos/stable/#sec-secrets)
  - [Example Configurations](https://github.com/nix-community/infra)
  - [Video Tutorial (6min)](https://www.youtube.com/watch?v=G5f6GC7SnhU)

## Quick Reference

- Runtime reads: Never use secrets at evaluation time. Read them at activation/runtime via:
  - `config.sops.secrets.<name>.path` in service commands (e.g., ExecStart scripts, postStart).
  - `config.sops.templates.<name>.path` for rendered configuration files.
  - Avoid `builtins.readFile` on secret paths and storing plaintext in the Nix store.
- Stable paths: Don’t hardcode `/run/secrets.d/<N>`. Use:
  - `config.sops.secrets.<name>.path` or
  - `environment.etc."<name>".source = config.sops.templates."<tmpl>".path` for stable targets (e.g., `/etc/app/secret`).
  - Templates default to `/run/secrets/rendered/<name>`; override with `path` as needed.
- Minimal permissions: Default to `mode = "0400";` with explicit `owner` (and `group` if required). Note that `/run/secrets.d/<N>` is owned by `root` with group `keys`; ensure your service can traverse and read its files.
- Home‑Manager ordering: For user services that consume secrets, ensure ordering with:
  - `systemd.user.services.<name>.unitConfig = { After = [ "sops-nix.service" ]; Wants = [ "sops-nix.service" ]; };`
- Git credentials: Use a credential helper that emits credentials at runtime from a sops‑managed file. Example configuration:
  - Install a helper that prints `username=...` and `password=$(cat /path/to/secret)`.
  - Configure per‑URL usage with Git:
    - `git config --global credential.useHttpPath true`
    - `git config --global 'credential.https://github.com.helper' '!/path/to/git-credential-sops'`
- act secrets: Use a stable path like `/etc/act/secrets.env` with `0400` perms for `--secret-file`. A user‑scoped path under `$HOME/.config/act/secrets` is an alternative.
- Validation: Prefer non‑destructive checks for .nix changes — `nix fmt`, `nix develop -c pre-commit run --all-files`, `generation-manager score`, `nix flake check --accept-flake-config`.

## Conclusion

SOPS with sops-nix provides a robust, secure, and NixOS-native solution for secret management. By following the patterns and practices in this guide, you can:

- Safely version control encrypted secrets
- Declaratively manage secret deployment
- Integrate secrets with any NixOS service
- Maintain security best practices
- Scale from single machines to complex infrastructure

The combination of SOPS's encryption capabilities with NixOS's declarative configuration creates a powerful system for reproducible, secure deployments.
