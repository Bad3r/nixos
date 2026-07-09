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
- [claude-code/writing-CLAUDE.md](claude-code/writing-CLAUDE.md)
  - How to write CLAUDE.md files: persistent, always-active agent instructions loaded at session start.

## Cloudflare

- [cloudflare/README.md](cloudflare/README.md)
  - Index for Cloudflare developer platform docs and local NixOS samples.
- [cloudflare/acme-cloudflare-sample.md](cloudflare/acme-cloudflare-sample.md)
  - Sample NixOS configuration for ACME certificate management using Cloudflare DNS-01 challenge.
- [cloudflare/cloudflared-tunnel-sample.md](cloudflare/cloudflared-tunnel-sample.md)
  - Sample NixOS configuration for Cloudflare Tunnel (cloudflared) with ingress rules and credential setup.
- [cloudflare/containers/README.md](cloudflare/containers/README.md)
  - Technical documentation index for Cloudflare Containers.
- [cloudflare/containers/architecture.md](cloudflare/containers/architecture.md)
  - Architecture, request flow, and rollout model for Cloudflare Containers.
- [cloudflare/containers/configuration.md](cloudflare/containers/configuration.md)
  - Wrangler, Dockerfile, environment, and deployment configuration for Cloudflare Containers.
- [cloudflare/containers/api-reference.md](cloudflare/containers/api-reference.md)
  - Container package properties, helper functions, methods, and TypeScript interfaces.
- [cloudflare/containers/lifecycle.md](cloudflare/containers/lifecycle.md)
  - Cold starts, warm requests, sleep behavior, shutdown, storage lifetime, and rollouts.
- [cloudflare/containers/storage-networking.md](cloudflare/containers/storage-networking.md)
  - Disk, R2 mount, ingress, egress, DNS, and network-isolation notes for Containers.
- [cloudflare/containers/use-cases.md](cloudflare/containers/use-cases.md)
  - Practical Cloudflare Containers examples and application patterns.
- [cloudflare/containers/limitations-roadmap.md](cloudflare/containers/limitations-roadmap.md)
  - Beta limitations, platform gaps, and roadmap notes for Cloudflare Containers.

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
- [drafts/duplicati-r2-readonly-mount-investigation.md](drafts/duplicati-r2-readonly-mount-investigation.md)
  - Investigation into a read-only mount for encrypted R2 backup archives (issue #204).
- [drafts/tpnix-cryptographic-identity-bootstrap-plan.md](drafts/tpnix-cryptographic-identity-bootstrap-plan.md)
  - Draft plan for bootstrapping cryptographic identity on the tpnix host.

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

## NixOS manual

- [nixos-manual/README.md](nixos-manual/README.md)
  - Entry point for the mirrored upstream NixOS manual under `docs/nixos-manual/`.
- [nixos-manual/manual.md](nixos-manual/manual.md)
  - Upstream manual structure file for chapters, appendices, options, and release notes.

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

## PDF Tooling

- [pdf/toolkit.md](pdf/toolkit.md)
  - Catalog of PDF-focused applications managed by this configuration covering viewers, structural inspectors, content extractors, and OCR engines.
- [pdf/additional-tools-reference.md](pdf/additional-tools-reference.md)
  - Reference catalog of PDF tools that complement the active toolkit, invocable ad hoc via `nix run`, `nix shell`, or `uvx`.

## Cybersecurity

- [csec/toolkit.md](csec/toolkit.md)
  - Catalog of cybersecurity-relevant apps managed by this configuration covering recon, web testing, credential attacks, RE, forensics, and dual-use utilities.
- [csec/additional-tools-reference.md](csec/additional-tools-reference.md)
  - Reference catalog of pentesting tools available via `nix run`/`nix shell` that complement the active toolkit, grouped by AD, recon, web testing, credential attacks, wireless, RE, forensics, stego, SAST, cloud, and pivoting.
- [csec/additional-tools-runtime-status.md](csec/additional-tools-runtime-status.md)
  - Smoke-test report for the additional-tools reference; records which entries launched cleanly on the active flake pin and which failed with build, attribute, or invocation issues.

## RDP

- [rdp/README.md](rdp/README.md)
  - Index for Remote Desktop (RDP) operator docs covering One Identity Safeguard RemoteApp access.
- [rdp/safeguard-remoteapp-file-export.md](rdp/safeguard-remoteapp-file-export.md)
  - Why file export/download fails inside a Safeguard RemoteApp session and the Safeguard channel-policy changes to request from the administrator.

## Reference

- [reference/fork-sync-automation.md](reference/fork-sync-automation.md)
  - Scheduled upstream sync workflow installed in each flake-input fork, its conflict behavior, and the installer for adding new forks.
- [reference/github-labels.md](reference/github-labels.md)
  - GitHub label taxonomy, application rules, and label-family reference for issues and pull requests.
- [reference/local-mirrors.md](reference/local-mirrors.md)
  - List of repositories mirrored locally via `git-mirror` for offline access and patching.
- [reference/mcp-tools.md](reference/mcp-tools.md)
  - Quick reference for available MCP tools including context7, cfdocs, cfbrowser, and deepwiki.
- [reference/useful-commands.md](reference/useful-commands.md)
  - Collection of handy general-purpose CLI commands not tied to NixOS or this repository.
- [reference/worktree-prune.md](reference/worktree-prune.md)
  - Pruning of local branches with gone upstreams and their worktrees, the scheduled cleanup timer, safety guarantees, and recovery paths.

## Security

- [security/owner-group-privileges.md](security/owner-group-privileges.md)
  - Security-relevant access granted by owner group membership.
- [security/owner-no-sudo-operations.md](security/owner-no-sudo-operations.md)
  - Configuration-managed operations available to the owner user without a sudo password.

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

## tpnix

- [tpnix/IMPLEMENTATION_PLAN.md](tpnix/IMPLEMENTATION_PLAN.md)
  - Hardware migration plan for the tpnix host on a Lenovo ThinkPad P15s Gen 2i.

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

## Troubleshooting

- [troubleshooting/nix-store-maintenance.md](troubleshooting/nix-store-maintenance.md)
  - Runbook defining the default Nix store repair workflow for each opted-in host.

## USBGuard

- [usbguard/README.md](usbguard/README.md)
  - USBGuard USB device access control with rules stored encrypted via sops.

## Usage

- [usage/README.md](usage/README.md)
  - Index of user-facing documentation for specific modules and features.
- [duplicati/README.md](duplicati/README.md)
  - Maintainer reference for the duplicati-r2 service: architecture, options, runbooks, recovery, security.
- [duplicati/operations.md](duplicati/operations.md)
  - Runbooks for everyday duplicati-r2 changes: provisioning secrets, editing the manifest, manual backup and restore, post-deploy validation.
- [duplicati/recovery.md](duplicati/recovery.md)
  - Failure modes, repair flow, and the impact-analysis playbook for missing or damaged remote volumes.
- [duplicati/reference.md](duplicati/reference.md)
  - Complete option surface, manifest schema, and runtime artifact catalog for `services.duplicati-r2`.
- [duplicati/security.md](duplicati/security.md)
  - Threat model, secret layout, state-directory access controls, credential rotation, and bucket lifecycle posture.
- [usage/espanso-usage.md](usage/espanso-usage.md)
  - Espanso text expander usage including default triggers, custom matches, and troubleshooting.
- [usage/pentesting-devshell.md](usage/pentesting-devshell.md)
  - Pentesting tools devshell usage including desktop launchers and adding new tools.
