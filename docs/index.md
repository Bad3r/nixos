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
  - Explains host definition under configurations.nixos, the per-host file structure under `modules/<host>/`, host-conditional helpers, and validation.
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

## R2 Cloud

- [r2-cloud/README.md](r2-cloud/README.md)
  - Index for `nix-R2-CloudFlare-Flake` consumer integration docs in this repo.
- [r2-cloud/input-and-module-wiring.md](r2-cloud/input-and-module-wiring.md)
  - How `inputs.r2-flake` is wired into System76 NixOS and Home Manager imports.
- [r2-cloud/secrets-and-rendered-files.md](r2-cloud/secrets-and-rendered-files.md)
  - Mapping from `secrets/r2.yaml` to `/run/secrets/r2/*` and HM env templates.
- [r2-cloud/system76-runtime.md](r2-cloud/system76-runtime.md)
  - Runtime contract for sync/restic/git-annex/r2 wrapper on this host.
- [r2-cloud/home-manager-r2-cloud.md](r2-cloud/home-manager-r2-cloud.md)
  - HM-side `programs.r2-cloud` load path and credential-source behavior.
- [r2-cloud/validation-and-drift-checks.md](r2-cloud/validation-and-drift-checks.md)
  - Operator checks to prove integration is still intact.
- [r2-cloud/troubleshooting.md](r2-cloud/troubleshooting.md)
  - Integration-specific failure diagnosis and repair paths.

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
- [guides/tray-icon-theming.md](guides/tray-icon-theming.md)
  - i3/i3bar tray icon theming guide with protocol classification, runtime verification, and remediation workflow.

## MCP

- [mcp/logseq.md](mcp/logseq.md)
  - Logseq MCP server documentation for AI assistant integration with knowledge graphs (DB graphs only).

## mpv

- [mpv/README.md](mpv/README.md)
  - Index for the mpv documentation set covering module composition, configuration, scripts, integrations, customization, and troubleshooting.
- [mpv/1-architecture.md](mpv/1-architecture.md)
  - Module layering, aggregator namespaces, host gating, and the NixOS-to-Home-Manager activation contract.
- [mpv/2-configuration.md](mpv/2-configuration.md)
  - Reference for every key the Home Manager mpv module writes to `mpv.conf` with rationale for non-default values.
- [mpv/3-scripts-and-bindings.md](mpv/3-scripts-and-bindings.md)
  - Script loading model (the `extraScripts` vs HM `scripts` distinction), bundled scripts, the inline Lua hooks, and the keybindings table.
- [mpv/4-integrations.md](mpv/4-integrations.md)
  - XDG MIME defaults, MPRIS via playerctl, the orthogonal `media-toolchain` bundle, the `open-in-mpv` browser bridge, and the `video-cache` helper.
- [mpv/5-customizing.md](mpv/5-customizing.md)
  - Patterns for adding scripts, overriding configuration keys, replacing the package, layering personal overrides, and opting out per host.
- [mpv/6-troubleshooting.md](mpv/6-troubleshooting.md)
  - MIME default-assertion failures, codec gaps, and silent hwdec fallback.

## Packaging

- [packaging/javascript-packages.md](packaging/javascript-packages.md)
  - Packaging npm, pnpm, and bun applications in NixOS including monorepos, native modules, and Electron apps.

## Cybersecurity

- [csec/toolkit.md](csec/toolkit.md)
  - Catalog of cybersecurity-relevant apps managed by this configuration covering recon, web testing, credential attacks, RE, forensics, and dual-use utilities.
- [csec/additional-tools-reference.md](csec/additional-tools-reference.md)
  - Reference catalog of pentesting tools available via `nix run`/`nix shell` that complement the active toolkit, grouped by AD, recon, web testing, credential attacks, wireless, RE, forensics, stego, SAST, cloud, and pivoting.
- [csec/additional-tools-runtime-status.md](csec/additional-tools-runtime-status.md)
  - Smoke-test report for the additional-tools reference; records which entries launched cleanly on the active flake pin and which failed with build, attribute, or invocation issues.

## Reference

- [reference/github-labels.md](reference/github-labels.md)
  - GitHub label taxonomy, application rules, and label-family reference for issues and pull requests.
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

## Technical Writing

- [technical-writing/scope-and-audience.md](technical-writing/scope-and-audience.md)
  - Rules for audience definition, content type selection, and information architecture.
- [technical-writing/drafting.md](technical-writing/drafting.md)
  - Rules for titles, structure, voice, paragraphs, lists, and callouts.
- [technical-writing/editing.md](technical-writing/editing.md)
  - Rules for multi-pass editing, peer review, and feedback discipline.
- [technical-writing/code-samples.md](technical-writing/code-samples.md)
  - Rules for sample trustworthiness, conciseness, naming, and autogeneration.
- [technical-writing/visual-content.md](technical-writing/visual-content.md)
  - Rules for diagram comprehension, accessibility, screenshots, and video.
- [technical-writing/lifecycle.md](technical-writing/lifecycle.md)
  - Rules for publishing, feedback triage, measurement, maintenance, and deprecation.

## Usage

- [usage/README.md](usage/README.md)
  - Index of user-facing documentation for specific modules and features.
- [usage/duplicati-r2-backups.md](usage/duplicati-r2-backups.md)
  - Duplicati backup setup for Cloudflare R2 including SOPS secrets, schedules, verification, and restore.
- [usage/espanso-usage.md](usage/espanso-usage.md)
  - Espanso text expander usage including default triggers, custom matches, and troubleshooting.
- [usage/pentesting-devshell.md](usage/pentesting-devshell.md)
  - Pentesting tools devshell usage including desktop launchers and adding new tools.
