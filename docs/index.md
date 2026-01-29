# Documentation Index

## Architecture

- [architecture/README.md](architecture/README.md)
  - Index and reading order for Dendritic Pattern architecture documentation with quick links to common tasks.
- [architecture/01-pattern-overview.md](architecture/01-pattern-overview.md)
  - Explains the Dendritic Pattern's automatic module discovery, aggregator namespaces, and organic configuration growth.
- [architecture/02-module-authoring.md](architecture/02-module-authoring.md)
  - Covers module writing patterns, file placement conventions, the two-context problem, and common pitfalls.
- [architecture/03-nixos-modules.md](architecture/03-nixos-modules.md)
  - Documents the flake.nixosModules namespace, app registry helpers (hasApp, getApp, getApps), and custom packages.
- [architecture/04-home-manager.md](architecture/04-home-manager.md)
  - Covers the flake.homeManagerModules namespace, app loading mechanism, and secrets integration for user configuration.
- [architecture/05-host-composition.md](architecture/05-host-composition.md)
  - Explains host definition under configurations.nixos, the System76 host structure, and how to add new hosts.
- [architecture/06-reference.md](architecture/06-reference.md)
  - Quick reference for validation commands, troubleshooting common issues, introspection via REPL, and glossary of terms.

## Claude Code

- [claude-code/plugins.md](claude-code/plugins.md)
  - Technical reference for the claude-plugins project covering architecture, registry API, installation flows, and CLI commands.
- [claude-code/skills.md](claude-code/skills.md)
  - Technical manual for SKILL.md files covering frontmatter fields, invocation methods, execution lifecycle, and best practices.

## Cloudflare

- [cloudflare/acme-cloudflare-sample.md](cloudflare/acme-cloudflare-sample.md)
  - Sample NixOS configuration for ACME certificate management using Cloudflare DNS-01 challenge.
- [cloudflare/cloudflared-tunnel-sample.md](cloudflare/cloudflared-tunnel-sample.md)
  - Sample NixOS configuration for Cloudflare Tunnel (cloudflared) with ingress rules and credential setup.

## Drafts

- [drafts/android-emulator-network-plan.md](drafts/android-emulator-network-plan.md)
  - Draft plan for Android emulator network interception setup with mitmproxy, KVM acceleration, and CA management.

## Guides

- [guides/README.md](guides/README.md)
  - Index of style guides, coding standards, and how-to documentation.
- [guides/apps-module-style-guide.md](guides/apps-module-style-guide.md)
  - Comprehensive style guide for modules/apps/ including header format, module structure, and HM integration workflow.
- [guides/custom-packages-style-guide.md](guides/custom-packages-style-guide.md)
  - Conventions for packages/ directory including templates for Rust, Go, Python, and binary downloads.
- [guides/github-deployments.md](guides/github-deployments.md)
  - Using GitHub's Deployments API via gh CLI for tracking deployments (metadata only, not actual deployment).
- [guides/nix-debugging-manual.md](guides/nix-debugging-manual.md)
  - Debugging techniques for Nix expressions, NixOS modules, and Home Manager including REPL, tracing, and common errors.
- [guides/stylix-integration.md](guides/stylix-integration.md)
  - Stylix theming integration covering NixOS vs Home Manager targets, autoEnable behavior, and common pitfalls.

## MCP

- [mcp/logseq.md](mcp/logseq.md)
  - Logseq MCP server documentation for AI assistant integration with knowledge graphs (DB graphs only).

## Packaging

- [packaging/javascript-packages.md](packaging/javascript-packages.md)
  - Packaging npm, pnpm, and bun applications in NixOS including monorepos, native modules, and Electron apps.

## Reference

- [reference/local-mirrors.md](reference/local-mirrors.md)
  - List of repositories mirrored locally via ghq for offline access and patching.
- [reference/mcp-tools.md](reference/mcp-tools.md)
  - Quick reference for available MCP tools including context7, cfdocs, cfbrowser, and deepwiki.

## SOPS

- [sops/README.md](sops/README.md)
  - sops-nix secrets management including host preparation, adding secrets, templates, and common issues.
- [sops/secrets-act.md](sops/secrets-act.md)
  - GitHub personal access token setup for act (local GitHub Actions runner) via sops-nix.

## System76

- [system76/system76-configuration.md](system76/system76-configuration.md)
  - System76 Oryx Pro NixOS configuration covering modules, NVIDIA GPU, power management, and LUKS storage.
- [system76/system76-hardware.md](system76/system76-hardware.md)
  - Hardware reference for System76 Oryx Pro including CPU, GPU, cooling, thermal sensors, and firmware.
- [system76/system76-troubleshooting.md](system76/system76-troubleshooting.md)
  - Troubleshooting guide covering thermal management, crash diagnostics, fan issues, and stress testing.

## Usage

- [usage/README.md](usage/README.md)
  - Index of user-facing documentation for specific modules and features.
- [usage/duplicati-r2-backups.md](usage/duplicati-r2-backups.md)
  - Duplicati backup setup for Cloudflare R2 including SOPS secrets, schedules, verification, and restore.
- [usage/espanso-usage.md](usage/espanso-usage.md)
  - Espanso text expander usage including default triggers, custom matches, and troubleshooting.
- [usage/pentesting-devshell.md](usage/pentesting-devshell.md)
  - Pentesting tools devshell usage including desktop launchers and adding new tools.
