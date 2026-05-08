{ lib, ... }:
{
  options = {
    flake = {
      lib = {
        meta = lib.mkOption {
          type = lib.types.anything;
          default = { };
          description = "Flake metadata exposed under flake.lib.meta";
        };
        # Home Manager helper namespace with freeform functions and small metadata.
        homeManager = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
          };
          default = { };
          description = "Helper functions and data for Home Manager (functions + small metadata only)";
        };
        nixos = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.anything;
          default = { };
          description = "Helper functions and small metadata for NixOS modules (pure/idempotent; no heavy evaluation or side effects).";
        };
        security = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Security helper data and utilities shared across modules.";
        };
        nixvim = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Helper functions and data for NixVim integrations.";
        };
        checks = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Flake-level evaluation checks (kept lightweight to avoid builds).";
        };
        xdg = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "XDG desktop file mappings and MIME type helpers.";
        };
        agents = lib.mkOption {
          type = lib.types.submodule {
            freeformType = lib.types.attrsOf lib.types.anything;
          };
          default = { };
          description = "Agent helper libraries, registries, and compiled outputs for skills and MCP integrations.";
        };
      };

      homeManagerModules = lib.mkOption {
        type = lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.deferredModule;
          options = {
            base = lib.mkOption {
              type = lib.types.deferredModule;
              default = { };
              description = "Base Home Manager module (merged)";
            };
            gui = lib.mkOption {
              type = lib.types.deferredModule;
              default = { };
              description = "GUI Home Manager module (merged)";
            };
            apps = lib.mkOption {
              type = lib.types.attrsOf lib.types.deferredModule;
              default = { };
              description = "Per-app Home Manager modules (merged by name)";
            };
          };
        };
        default = { };
        description = "Aggregated Home Manager modules loaded into each NixOS host's `home-manager.users.<owner>.imports` via `modules/home-manager/nixos.nix`";
      };

      # Cybersecurity-tooling NixOS modules. Declared with attrsOf
      # deferredModule so each feature (`flake.csec.<feature>`) is a
      # first-class entry rather than collapsing into the parent module
      # like sub-keys under `flake.nixosModules.*` would.
      csec = lib.mkOption {
        type = lib.types.attrsOf lib.types.deferredModule;
        default = { };
        description = "Per-feature csec NixOS modules (merged by name).";
      };

      # Per-app nixpkgs overlay modules, auto-discovered from
      # `modules/custom-overlays/`. Declared with attrsOf deferredModule for
      # the same reason as `flake.csec` above: each entry must be a
      # first-class submodule rather than collapse into the parent.
      # Imported into each host by `modules/<host>/custom-overlays-base.nix`.
      customOverlays = lib.mkOption {
        type = lib.types.attrsOf lib.types.deferredModule;
        default = { };
        description = "Per-app nixpkgs overlay modules, gated on the matching app's `programs.<name>.extended.enable`.";
      };

    };
  };
}
