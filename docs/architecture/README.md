# Architecture Documentation

This directory explains how the Dendritic Pattern organizes this NixOS configuration.

## Reading Order

| #   | Document                                   | Purpose                                                 |
| --- | ------------------------------------------ | ------------------------------------------------------- |
| 1   | [Pattern Overview](01-pattern-overview.md) | What is Dendritic, why it exists, auto-import mechanism |
| 2   | [Module Authoring](02-module-authoring.md) | How to write modules, patterns, anti-patterns           |
| 3   | [NixOS Modules](03-nixos-modules.md)       | System-level aggregators and app registry               |
| 4   | [Home Manager](04-home-manager.md)         | User-level aggregators and app loading                  |
| 5   | [Host Composition](05-host-composition.md) | How hosts are assembled from modules                    |
| 6   | [Reference](06-reference.md)               | Validation, glossary, troubleshooting                   |

## Quick Links

| Task                                 | Go to                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Adding a new app module              | [02-module-authoring.md](02-module-authoring.md)                                                 |
| "Cannot coerce null to string" error | [02-module-authoring.md#the-two-context-problem](02-module-authoring.md#the-two-context-problem) |
| Understanding aggregator namespaces  | [03-nixos-modules.md](03-nixos-modules.md)                                                       |
| Home Manager app loading             | [04-home-manager.md](04-home-manager.md)                                                         |
| Adding a new host                    | [05-host-composition.md](05-host-composition.md)                                                 |
| Validation commands                  | [06-reference.md#validation](06-reference.md#validation)                                         |
| Glossary of terms                    | [06-reference.md#glossary](06-reference.md#glossary)                                             |

## Related Guides

- [Apps Module Style Guide](../guides/apps-module-style-guide.md) -- header comments and per-app conventions
- [Custom Packages Style Guide](../guides/custom-packages-style-guide.md) -- building packages under `packages/`
- [Stylix Integration](../guides/stylix-integration.md) -- theming constraints
- [SOPS Usage](../sops/README.md) -- secrets management
