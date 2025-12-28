# Documentation Audit Report

**Audit Date:** 2025-12-28
**Repository:** /home/vx/nixos
**Total Documentation Files:** 40 (excluding nixos_docs_md/)
**Total Lines:** 4,737

---

## 1. Documentation Inventory

### 1.1 Root-Level Documentation

| File      | Lines | Last Modified | Bytes  |
| --------- | ----- | ------------- | ------ |
| README.md | 117   | 2025-10-25    | 4,858  |
| CLAUDE.md | 405   | 2025-12-28    | 27,182 |

### 1.2 docs/ Directory - Root Level

| File                             | Lines | Last Modified | Bytes  |
| -------------------------------- | ----- | ------------- | ------ |
| acme-cloudflare-sample.md        | 34    | 2025-10-26    | 1,119  |
| android-emulator-network-plan.md | 127   | 2025-10-28    | 7,289  |
| apps-module-style-guide.md       | 83    | 2025-10-10    | 4,583  |
| cloudflared-tunnel-sample.md     | 39    | 2025-10-26    | 1,417  |
| codex-update-package.md          | 61    | 2025-10-26    | 3,848  |
| configuration-architecture.md    | 246   | 2025-10-26    | 16,191 |
| dendritic-pattern-reference.md   | 111   | 2025-10-26    | 6,204  |
| espanso-usage.md                 | 334   | 2025-10-08    | 7,611  |
| github-deployments.md            | 414   | 2025-11-06    | 11,394 |
| home-manager-aggregator.md       | 86    | 2025-10-26    | 4,106  |
| home-manager-bridge-debug-log.md | 60    | 2025-10-26    | 12,292 |
| module-structure-guide.md        | 216   | 2025-12-26    | 7,901  |
| nix-debugging-manual.md          | 204   | 2025-12-26    | 13,244 |
| pentesting-devshell.md           | 43    | 2025-10-26    | 1,353  |
| pentesting-tools-reference.md    | 425   | 2025-11-12    | 13,072 |
| stylix-integration.md            | 187   | 2025-12-28    | 6,147  |
| system76-crash-diagnostics.md    | 119   | 2025-10-10    | 3,680  |
| workstation-removal-tasks.md     | 38    | 2025-10-10    | 5,622  |

### 1.3 docs/duplicati/

| File                                | Lines | Last Modified | Bytes |
| ----------------------------------- | ----- | ------------- | ----- |
| duplicati-r2-backups.md             | 278   | 2025-10-15    | 9,601 |
| duplicati-r2-implementation-plan.md | 48    | 2025-10-15    | 3,940 |

### 1.4 docs/flake-parts-docs/

| File                                 | Lines | Last Modified | Bytes |
| ------------------------------------ | ----- | ------------- | ----- |
| best-practices-for-module-writing.md | 40    | 2025-10-26    | 2,686 |
| cheat-sheet.md                       | 60    | 2025-10-26    | 1,575 |
| debug.md                             | 77    | 2025-10-26    | 1,594 |
| define-custom-flake-attribute.md     | 30    | 2025-10-26    | 2,323 |
| define-module-in-separate-file.md    | 93    | 2025-10-26    | 2,458 |
| dogfood-a-reusable-module.md         | 99    | 2025-10-26    | 4,171 |
| generate-documentation.md            | 83    | 2025-10-26    | 3,268 |
| getting-started.md                   | 48    | 2025-10-26    | 1,204 |
| intro-continued.md                   | 7     | 2025-10-26    | 232   |
| module-arguments.md                  | 211   | 2025-10-26    | 7,947 |
| overlays.md                          | 109   | 2025-10-26    | 4,042 |
| SUMMARY.md                           | 26    | 2025-10-26    | 1,014 |
| system.md                            | 19    | 2025-10-26    | 1,069 |

### 1.5 docs/sops/

| File                      | Lines | Last Modified | Bytes |
| ------------------------- | ----- | ------------- | ----- |
| README.md                 | 89    | 2025-10-26    | 2,944 |
| secrets-act.md            | 62    | 2025-10-26    | 2,046 |
| sops-dotfile.example.yaml | 66    | 2025-10-26    | 2,285 |

### 1.6 docs/manual/

| File               | Lines | Last Modified | Bytes |
| ------------------ | ----- | ------------- | ----- |
| writing-modules.md | 9     | 2025-10-26    | 479   |

---

## 2. Document Contents Summary

### 2.1 Root Documentation

#### README.md (117 lines)

**Title:** "NixOS Configuration"

**Sections:**

- Automatic import (lines 7-15)
- Module Aggregators (lines 17-39)
- System76 Host Layout (lines 41-52)
- Development Shell (lines 54-67)
- Adding a new secret with sops-nix (lines 69-86)
- Generated files (lines 88-96)
- Flake inputs for deduplication are prefixed (lines 98-106)
- Trying to disallow warnings (lines 108-117)

**Topics Covered:**

- Dendritic Pattern description
- `flake.nixosModules` and `flake.homeManagerModules` aggregators
- Module composition code example
- System76 host layout overview
- `nix develop` and `nix fmt` commands
- sops-nix secret workflow with code example
- Generated files list (`.actrc`, `.gitignore`, `.sops.yaml`, `README.md`)
- `dedupe_` input prefix convention
- `nixConfig.abort-on-warn = true` setting

#### CLAUDE.md (405 lines)

**Title:** "CLAUDE.md"

**Sections:**

- Critical Safety Rules (lines 5-49)
- Repository Overview (lines 51-66)
- Nix Configuration (lines 68-78)
- Quick-Start Checklist (lines 80-89)
- Architecture & Module System (lines 91-189)
- Execution Playbooks (lines 191-258)
- Coding Style & Verification (lines 260-275)
- Secret Management (lines 277-294)
- Safety & Escalation (lines 296-319)
- Local Mirrors (lines 321-335)
- MCP Tools (lines 337-358)
- Prompt Snippets & Templates (lines 360-387)
- Important Reminders (lines 389-405)

**Topics Covered:**

- Git stash operation rules
- Data safety requirements
- Dendritic Pattern description
- Module aggregators
- Automatic module discovery
- Module composition pattern with code example
- Flake input deduplication
- Repository layout table
- Module authoring guidelines with code example
- Branch workflow
- Development environment commands
- Validation and build commands
- build.sh options table
- GitHub Actions local testing
- Repository maintenance
- Coding style guidance
- Commit and PR expectations
- sops-nix secret workflow with code example
- Guardrails table
- Escalation procedures
- Local mirror paths table
- MCP tools table
- Prompt templates

---

### 2.2 Architecture Documentation

#### docs/configuration-architecture.md (246 lines)

**Title:** "Trees Nix Configuration Architecture"

**Sections:**

1. Flake Composition & Auto-Import
2. Aggregator Map (System Layer)
3. Home Manager Aggregator & Secrets
4. Host Composition (System76 Example)
5. Packages, perSystem, and Tooling
6. Validation & Continuous Checks
7. Troubleshooting & Patterns
8. Resource & Reference Index
9. Task Playbooks & Examples
10. External Tooling & Integrations
11. Glossary

**Topics Covered:**

- `flake.nix` composition
- import-tree usage
- Default systems declaration
- `_module.args` configuration
- App registry helpers (`getApp`, `getApps`, `hasApp`, `getAppOr`)
- Per-app module pattern
- System76 host modules
- Shared system helpers
- System-level utilities
- Home Manager base wiring
- App catalog and GUI bundle
- Secrets helpers
- Host definitions
- Custom derivations
- Dev shells
- Git hooks and formatting
- Generation manager
- Validation command sequence
- Troubleshooting scenarios
- Resource links
- Task playbooks for adding apps and hosts
- External tooling references
- Glossary definitions

**Cross-References:**

- References `docs/dendritic-pattern-reference.md`
- References `docs/module-structure-guide.md`
- References `docs/home-manager-aggregator.md`
- References `docs/apps-module-style-guide.md`
- References `docs/sops/` directory

#### docs/dendritic-pattern-reference.md (111 lines)

**Title:** "Dendritic Pattern Reference"

**Opening Statement:** "For a full-stack view of how the flake, aggregators, hosts, Home Manager, and tooling interlock, start with `docs/configuration-architecture.md`."

**Sections:**

- Automatic Module Discovery
- Aggregator Namespaces
- Host Definitions
- Authoring Modules
- Apps and Lookups
- Tooling and Required Commands
- Secrets and SOPS
- Migration Checklist
- Further Reading

**Topics Covered:**

- import-tree behavior
- Underscore prefix convention
- `flake.nixosModules` namespace table
- `flake.homeManagerModules` namespace table
- Code example for module export
- Host definition under `configurations.nixos.<name>.module`
- Module authoring rules
- App helper surface
- Validation commands
- Migration steps

**Cross-References:**

- References `docs/configuration-architecture.md`
- References `docs/module-structure-guide.md`
- References `docs/home-manager-aggregator.md`
- References `docs/apps-module-style-guide.md`
- References `docs/sops/README.md`

#### docs/module-structure-guide.md (216 lines)

**Title:** "Module Structure Guide"

**Opening Statement:** "Start with `docs/configuration-architecture.md` for the end-to-end architecture map, then return here for module-level authoring patterns."

**Sections:**

- Key Concepts
- File Placement Rules
- Authoring Patterns (5 sub-patterns)
- Home Manager Aggregator
- Common Pitfalls (and Fixes)
- Config Access Patterns and Evaluation Order
- Introspection & Debugging
- Migration Tips

**Topics Covered:**

- Module auto-import behavior
- Aggregator registration
- File placement under `modules/apps/` and `modules/<domain>/`
- Pattern 1: Module that needs `pkgs`
- Pattern 2: Module without `pkgs`
- Pattern 3: Multi-namespace module
- Pattern 4: Extending existing namespaces
- Pattern 5: Host modules
- Home Manager aggregator references
- Pitfall table with fixes
- Two-context problem explanation
- Anti-patterns with code examples
- Safe patterns with code examples
- REPL introspection commands
- Migration steps

**Cross-References:**

- References `docs/configuration-architecture.md`
- References `docs/dendritic-pattern-reference.md`
- References `docs/home-manager-aggregator.md`

#### docs/home-manager-aggregator.md (86 lines)

**Title:** "Home Manager Aggregator (`flake.homeManagerModules`)"

**Sections:**

- Namespace Layout
- Default App Imports
- Authoring Rules
- Validation

**Topics Covered:**

- `flake.homeManagerModules.base` description
- `flake.homeManagerModules.gui` description
- `flake.homeManagerModules.apps.<name>` description
- Optional helpers (`r2Secrets`, `context7Secrets`)
- Code examples for module exports
- `loadAppModule` function description
- `defaultAppImports` list
- `home-manager.extraAppImports` extension
- Authoring rules list
- Validation commands

**Cross-References:**

- References `docs/configuration-architecture.md`
- References `docs/sops/README.md`

#### docs/apps-module-style-guide.md (83 lines)

**Title:** "Apps Module Style Guide"

**Sections:**

- Source Gathering
- Scope
- File Layout
- Top-of-File Documentation Block
- Module Body
- Example Skeleton
- Maintenance Checklist

**Topics Covered:**

- Source verification process
- Scope definition (`flake.nixosModules.apps`)
- File storage location
- Documentation block format
- Required header fields (Package, Description, Homepage, Documentation, Repository)
- Subsection requirements (Summary, Tests, Options)
- Bullet style conventions
- Module body lambda structure
- Example skeleton code
- Maintenance steps

**Cross-References:**

- References `modules/apps/ent.nix`
- References `docs/configuration-architecture.md`
- References `docs/module-structure-guide.md`

#### docs/stylix-integration.md (187 lines)

**Title:** "Stylix Integration"

**Sections:**

- Overview
- Key Concept: NixOS vs Home Manager Targets
- The autoEnable Mechanism
- Best Practices for Module Authors
- Common Pitfalls
- Debugging Stylix Issues
- Related Documentation

**Topics Covered:**

- Stylix repository link
- NixOS vs Home Manager target table
- Target context rule
- `nix eval` commands for target inspection
- `stylix.autoEnable` mechanism
- Priority and override behavior
- NixOS app module patterns
- Home Manager module patterns
- Code examples
- Pitfall 1: Setting HM targets in NixOS modules
- Pitfall 2: Redundant target enables
- Pitfall 3: Using `_module.check = false`
- Debugging commands

**Cross-References:**

- References `docs/dendritic-pattern-reference.md`
- References `docs/home-manager-aggregator.md`
- References `docs/apps-module-style-guide.md`
- External link to Stylix documentation

---

### 2.3 Operational Guides

#### docs/nix-debugging-manual.md (204 lines)

**Title:** "Nix Ecosystem Debugging Manual"

**Sections:**

1. Introduction
2. Debugging Nix Language Expressions
3. Debugging NixOS Systems
4. Debugging Home Manager
5. Useful Third-Party Debugging Tools
6. Conclusion

**Topics Covered:**

- Nix REPL usage
- `builtins.trace` and `builtins.traceVerbose`
- `lib.debug` helpers
- Common errors and pitfalls
- "Cannot coerce null to string" error analysis
- Binary search debugging strategy
- `nix-tree` usage
- Build failure analysis
- systemd service debugging
- NixOS debugging options
- Nix store inspection
- Home Manager activation issues
- Generated file inspection
- Third-party tools (`nix-tree`, `nh`, `nvd`)

**Citations:** Document contains inline citations (e.g., `citeturn15search0`)

#### docs/github-deployments.md (414 lines)

**Title:** "GitHub Deployments via CLI"

**Sections:**

- Overview
- Prerequisites
- Available Environments
- Creating a Deployment
- Updating Deployment Status
- Complete Deployment Workflow
- Querying Deployments
- Integration with Releases
- Best Practices
- Actual Deployment Process
- Troubleshooting
- Related Commands
- References
- Summary

**Topics Covered:**

- GitHub Deployments API scope
- `gh` CLI authentication
- Production and staging environments
- Deployment creation commands
- Status update commands
- Available status states table
- Complete workflow script example
- Deployment query commands
- Release integration
- Best practices list
- Local deployment process
- Future automated deployment notes
- Troubleshooting commands

#### docs/codex-update-package.md (61 lines)

**Title:** "Updating the `codex` Package"

**Sections:**

1. Pick the Target Commit
2. Prefetch the Source
3. Update `packages/codex/default.nix`
4. Recompute `cargoHash`
5. Defer Final Verification
6. Tips to Minimize Future Hash Runs

**Topics Covered:**

- Target commit selection
- `nix-prefetch-github` usage
- `fetchFromGitHub` hash update
- `cargoHash` placeholder technique
- Build error interpretation
- Verification deferral
- Cache optimization tips

#### docs/system76-crash-diagnostics.md (119 lines)

**Title:** "System76 Crash Diagnostics Playbook"

**Sections:**

1. Configuration Summary
2. Verifying the Instrumentation
3. When a Crash Occurs
4. Stress and Reproduction Tests
5. Post-Crash Analysis Checklist

**Topics Covered:**

- `boot.crashDump` configuration
- `journald.storage = "persistent"`
- `systemd-coredump` enablement
- Diagnostic packages list
- Verification commands
- Crash kernel reservation check
- SysRq and logging verification
- Crash dump collection
- Journal collection
- Hardware telemetry capture
- Stress testing commands
- Kernel dump analysis
- Regression tracking

#### docs/espanso-usage.md (334 lines)

**Title:** "Espanso Text Expander Module"

**Sections:**

- Overview
- Quick Start
- Default Triggers
- Customization
- Display Server Configuration
- Service Management
- Configuration Files
- Troubleshooting
- Integration with This Repository
- References

**Topics Covered:**

- Home Manager import
- Default trigger table
- Custom match examples
- App-specific configuration
- Advanced variables (form, shell, clipboard)
- Regex triggers
- X11 and Wayland support
- Closure size optimization
- Custom package override
- systemd service commands
- Configuration file locations
- Troubleshooting steps
- Module location

**Date Reference:** Document uses `2025-10-08` as example date

---

### 2.4 Sample Configurations

#### docs/acme-cloudflare-sample.md (34 lines)

**Title:** "ACME Cloudflare DNS-01 Sample"

**Content:**

- Nix code block for ACME configuration
- Implementation notes (4 items)
- Reference material links

#### docs/cloudflared-tunnel-sample.md (39 lines)

**Title:** "Cloudflare Tunnel Starter Configuration"

**Content:**

- Nix code block for tunnel configuration
- Setup steps (4 items)
- Reference material links

---

### 2.5 Pentesting Documentation

#### docs/pentesting-tools-reference.md (425 lines)

**Title:** "Pentesting Tools Reference"

**Sections:**

- Table of Contents
- Web Application Testing
- Network Security
- Binary Analysis & Reverse Engineering
- Wireless Security
- Password Cracking
- HTTP Clients & Testing
- Reconnaissance & OSINT
- Vulnerability Scanning
- Traffic Analysis
- Secret Scanning
- API Testing
- Configuration Status
- Usage
- Module Structure

**Tool Count:** 31 tools documented (26 pentesting + 4 HTTP + 1 devshell-only)

**Last Updated:** 2025-11-07

#### docs/pentesting-devshell.md (43 lines)

**Title:** "Pentesting Dev Shell"

**Content:**

- Dev shell command
- Included tools list (11 items)
- Launcher wrappers section
- Notes section

#### docs/android-emulator-network-plan.md (127 lines)

**Title:** "Android Emulator Network Interception Plan"

**Sections:**

- Objectives
- Scope & Assumptions
- Phase 0 – Host Readiness
- Phase 1 – Nix Flake Integration
- Phase 2 – SDK & AVD Provisioning
- Phase 3 – Launch & Interception Pipeline
- Phase 4 – Validation & Observability
- Maintenance & Update Strategy
- Risk Log & Mitigations
- Next Actions

**Status Indicators:**

- Contains "Next Actions" section with unimplemented items
- Contains inline citations

---

### 2.6 Historical/Task List Documents

#### docs/workstation-removal-tasks.md (38 lines)

**Title:** "Workstation Removal Task List"

**Content:** 39 checkbox items, all marked as complete (`[x]`)

**Task Categories:**

- Module migrations from `modules/workstation/`
- Module migrations from `modules/audio/`
- Module migrations from `modules/base/`
- Module migrations from `modules/development/`
- Module migrations from `modules/networking/`
- Module migrations from `modules/security/`
- Module migrations from other directories
- Validation tasks

#### docs/home-manager-bridge-debug-log.md (60 lines)

**Title:** "Home Manager Bridge Debug Log (Living Document)"

**Status Line:** "Status: Investigation in progress"

**Last Updated:** 2025-10-19

**Sections:**

1. Problem Statement
2. Hypotheses Tested (table with 6 entries)
3. Current Understanding
4. Open Questions / Next Lines of Inquiry
5. Update Procedure

---

### 2.7 Secrets Documentation

#### docs/sops/README.md (89 lines)

**Title:** "sops-nix Usage in This Repository"

**Sections:**

- What Ships in the Repo
- Host Preparation
- Home Manager user service
- Adding a New Secret
- Example: GitHub Token for `act`
- Working With `r2.env`
- Quick Checklist
- Common Issues
- Validation Commands

**Topics Covered:**

- `.sops.yaml` generation
- `owner_bad3r` and `host_primary` keys
- `modules/security/secrets.nix` description
- Age key generation commands
- Secret declaration pattern
- Template usage
- Issue resolution table

#### docs/sops/secrets-act.md (62 lines)

**Title:** "GitHub Token for `act` via sops-nix"

**Sections:**

- Overview
- Host Setup (one-time)
- Adding or Rotating the Token
- Using the Token with `act`
- Security Notes

---

### 2.8 Backup Documentation

#### docs/duplicati/duplicati-r2-backups.md (278 lines)

**Title:** "Duplicati → Cloudflare R2 Backups"

**Sections:**

1. Prepare secrets
2. Author the encrypted manifest
3. Wire the module
4. Manual operations
5. Restoring files
6. Add another folder to the backup set
7. Keeping the backup healthy
8. Troubleshooting checklist

#### docs/duplicati/duplicati-r2-implementation-plan.md (48 lines)

**Title:** "Duplicati R2 Module Implementation Checklist"

**Checklist Categories:**

- Module Scaffolding (4 items, all checked)
- Secrets & Environment File Wiring (4 items, all checked)
- Backup & Verify Script Derivations (4 items, all checked)
- Runtime Systemd Unit Generation (4 items, all checked)
- NixOS Test Coverage (5 items, 4 checked, 1 unchecked)
- Validation & Lint Hooks (2 items, all checked)
- Documentation (3 items, all checked)
- CI & Flake Integration (3 items, all unchecked)

---

### 2.9 External Reference Documentation

#### docs/flake-parts-docs/ (13 files)

**Source:** Copied from upstream flake-parts project

**Files:**
| File | Lines | Description |
|------|-------|-------------|
| SUMMARY.md | 26 | Table of contents |
| getting-started.md | 48 | Initial setup guide |
| cheat-sheet.md | 60 | Quick reference |
| module-arguments.md | 211 | Module argument documentation |
| best-practices-for-module-writing.md | 40 | Module writing guidelines |
| overlays.md | 109 | Overlay system documentation |
| debug.md | 77 | Debugging guide |
| define-module-in-separate-file.md | 93 | File separation patterns |
| define-custom-flake-attribute.md | 30 | Custom attribute definition |
| generate-documentation.md | 83 | Documentation generation |
| dogfood-a-reusable-module.md | 99 | Reusable module patterns |
| system.md | 19 | System handling |
| intro-continued.md | 7 | Introduction continuation |

---

### 2.10 Manual Documentation

#### docs/manual/writing-modules.md (9 lines)

**Title:** "Local Manual Mirrors"

**Content:** Pointer to local mirror paths:

- `/home/vx/git/home-manager/docs/manual/`
- `/home/vx/git/home-manager/docs/manual/writing-modules.md`
- `/home/vx/git/nixos_docs_md/`

---

## 3. Content Overlap Analysis

### 3.1 Dendritic Pattern Coverage

The following files contain content about the Dendritic Pattern:

| File                                | Content Description                                              |
| ----------------------------------- | ---------------------------------------------------------------- |
| README.md                           | Lines 1-15: Pattern description, auto-import explanation         |
| CLAUDE.md                           | Lines 53-57, 91-95: Pattern description, auto-import explanation |
| docs/configuration-architecture.md  | Lines 9-28: Flake composition and auto-import                    |
| docs/dendritic-pattern-reference.md | Lines 1-111: Dedicated pattern reference                         |

### 3.2 Module Aggregator Coverage

The following files contain content about module aggregators:

| File                                | Content Description                                     |
| ----------------------------------- | ------------------------------------------------------- |
| README.md                           | Lines 17-39: Aggregator description with code example   |
| CLAUDE.md                           | Lines 93-111: Aggregator description with code examples |
| docs/configuration-architecture.md  | Lines 32-72: Aggregator map with subsections            |
| docs/dendritic-pattern-reference.md | Lines 13-49: Aggregator namespaces                      |
| docs/home-manager-aggregator.md     | Lines 1-86: Dedicated HM aggregator documentation       |

### 3.3 Secret Management Coverage

The following files contain content about sops-nix secrets:

| File                               | Content Description                                        |
| ---------------------------------- | ---------------------------------------------------------- |
| README.md                          | Lines 69-86: Secret workflow with code example             |
| CLAUDE.md                          | Lines 277-294: Secret management section with code example |
| docs/configuration-architecture.md | Lines 75-100: Secrets helpers                              |
| docs/sops/README.md                | Lines 1-89: Dedicated secrets documentation                |
| docs/sops/secrets-act.md           | Lines 1-62: Act-specific secrets                           |

### 3.4 Validation Commands Coverage

The following files contain validation command sequences:

| File                                | Commands Listed                                                                        |
| ----------------------------------- | -------------------------------------------------------------------------------------- |
| CLAUDE.md                           | `nix fmt`, `pre-commit run --all-files`, `nix flake check`                             |
| docs/configuration-architecture.md  | `nix fmt`, `pre-commit run --all-files`, `generation-manager score`, `nix flake check` |
| docs/dendritic-pattern-reference.md | `nix fmt`, `pre-commit run --all-files`, `generation-manager score`, `nix flake check` |
| docs/module-structure-guide.md      | `nix fmt`, `pre-commit run --all-files`, `generation-manager score`, `nix flake check` |
| docs/home-manager-aggregator.md     | `nix fmt`, `pre-commit run --all-files`, `nix flake check`                             |
| docs/sops/README.md                 | `nix fmt`, `pre-commit run --all-files`, `generation-manager score`, `nix flake check` |

---

## 4. Cross-Reference Map

### 4.1 Documents That Reference Other Documents

| Source Document                     | References                                                                                                                       |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| docs/configuration-architecture.md  | dendritic-pattern-reference.md, module-structure-guide.md, home-manager-aggregator.md, apps-module-style-guide.md, sops/         |
| docs/dendritic-pattern-reference.md | configuration-architecture.md, module-structure-guide.md, home-manager-aggregator.md, apps-module-style-guide.md, sops/README.md |
| docs/module-structure-guide.md      | configuration-architecture.md, dendritic-pattern-reference.md, home-manager-aggregator.md                                        |
| docs/home-manager-aggregator.md     | configuration-architecture.md, sops/README.md                                                                                    |
| docs/apps-module-style-guide.md     | configuration-architecture.md, module-structure-guide.md                                                                         |
| docs/stylix-integration.md          | dendritic-pattern-reference.md, home-manager-aggregator.md, apps-module-style-guide.md                                           |

### 4.2 Documents With No Outgoing References

- README.md
- docs/acme-cloudflare-sample.md
- docs/android-emulator-network-plan.md
- docs/cloudflared-tunnel-sample.md
- docs/codex-update-package.md
- docs/espanso-usage.md
- docs/github-deployments.md
- docs/home-manager-bridge-debug-log.md
- docs/nix-debugging-manual.md
- docs/pentesting-devshell.md
- docs/pentesting-tools-reference.md
- docs/system76-crash-diagnostics.md
- docs/workstation-removal-tasks.md
- docs/duplicati/\*.md
- docs/flake-parts-docs/\*.md
- docs/manual/writing-modules.md
- docs/sops/secrets-act.md

---

## 5. Document Status Indicators

### 5.1 Documents Containing Completion Markers

| Document                                           | Marker Type      | Count                   |
| -------------------------------------------------- | ---------------- | ----------------------- |
| docs/workstation-removal-tasks.md                  | `[x]` checkboxes | 39 (all checked)        |
| docs/duplicati/duplicati-r2-implementation-plan.md | `[x]` checkboxes | 22 checked, 4 unchecked |

### 5.2 Documents Containing Status Statements

| Document                              | Status Statement                    |
| ------------------------------------- | ----------------------------------- |
| docs/home-manager-bridge-debug-log.md | "Status: Investigation in progress" |
| docs/home-manager-bridge-debug-log.md | "Last Updated: 2025-10-19"          |

### 5.3 Documents Containing "Last Updated" Dates

| Document                              | Date                                              |
| ------------------------------------- | ------------------------------------------------- |
| docs/pentesting-tools-reference.md    | 2025-11-07                                        |
| docs/home-manager-bridge-debug-log.md | 2025-10-19                                        |
| CLAUDE.md                             | 2025-12-28 (in metadata table as "Last reviewed") |

---

## 6. External Links Inventory

### 6.1 GitHub Repository Links

| Document                            | Link Target                |
| ----------------------------------- | -------------------------- |
| README.md                           | github.com/mightyiam/infra |
| README.md                           | github.com/vic/import-tree |
| README.md                           | github.com/mightyiam/files |
| docs/dendritic-pattern-reference.md | github.com/mightyiam/infra |
| docs/stylix-integration.md          | github.com/danth/stylix    |

### 6.2 External Documentation Links

| Document                           | Link Target                                 |
| ---------------------------------- | ------------------------------------------- |
| docs/acme-cloudflare-sample.md     | search.nixos.org, developers.cloudflare.com |
| docs/cloudflared-tunnel-sample.md  | developers.cloudflare.com                   |
| docs/espanso-usage.md              | espanso.org                                 |
| docs/github-deployments.md         | docs.github.com, cli.github.com             |
| docs/stylix-integration.md         | danth.github.io/stylix                      |
| docs/pentesting-tools-reference.md | Multiple tool homepages                     |

---

## 7. Code Examples Inventory

| Document                               | Code Block Count | Languages             |
| -------------------------------------- | ---------------- | --------------------- |
| README.md                              | 3                | Nix, Bash             |
| CLAUDE.md                              | 7                | Nix, Bash, Text       |
| docs/configuration-architecture.md     | 8                | Nix, Bash             |
| docs/dendritic-pattern-reference.md    | 4                | Nix, Bash             |
| docs/module-structure-guide.md         | 12               | Nix, Bash             |
| docs/home-manager-aggregator.md        | 4                | Nix                   |
| docs/apps-module-style-guide.md        | 2                | Nix                   |
| docs/stylix-integration.md             | 8                | Nix, Bash             |
| docs/nix-debugging-manual.md           | 10               | Nix, Bash             |
| docs/github-deployments.md             | 20+              | Bash, JSON, YAML      |
| docs/espanso-usage.md                  | 15+              | Nix, Bash, YAML       |
| docs/duplicati/duplicati-r2-backups.md | 10+              | Nix, Bash, JSON, YAML |

---

## 8. File Modification Timeline

### 8.1 Most Recently Modified (2025-12)

| File                           | Date       |
| ------------------------------ | ---------- |
| CLAUDE.md                      | 2025-12-28 |
| docs/stylix-integration.md     | 2025-12-28 |
| docs/module-structure-guide.md | 2025-12-26 |
| docs/nix-debugging-manual.md   | 2025-12-26 |

### 8.2 Modified in 2025-11

| File                               | Date       |
| ---------------------------------- | ---------- |
| docs/pentesting-tools-reference.md | 2025-11-12 |
| docs/github-deployments.md         | 2025-11-06 |

### 8.3 Modified in 2025-10

| File                                  | Date       |
| ------------------------------------- | ---------- |
| docs/android-emulator-network-plan.md | 2025-10-28 |
| All docs/flake-parts-docs/\*.md       | 2025-10-26 |
| docs/configuration-architecture.md    | 2025-10-26 |
| docs/dendritic-pattern-reference.md   | 2025-10-26 |
| docs/home-manager-aggregator.md       | 2025-10-26 |
| docs/home-manager-bridge-debug-log.md | 2025-10-26 |
| docs/sops/\*.md                       | 2025-10-26 |
| README.md                             | 2025-10-25 |
| docs/duplicati/\*.md                  | 2025-10-15 |
| docs/apps-module-style-guide.md       | 2025-10-10 |
| docs/system76-crash-diagnostics.md    | 2025-10-10 |
| docs/workstation-removal-tasks.md     | 2025-10-10 |
| docs/espanso-usage.md                 | 2025-10-08 |

---

## 9. Excluded Documentation

### 9.1 nixos_docs_md/ Directory

**Status:** Not included in this audit

**Content:** 461 markdown files containing NixOS 25.11 official documentation

**Total Lines:** Approximately 17,241

**Source:** Upstream NixOS manual exported as markdown

---

_Report generated: 2025-12-28_
