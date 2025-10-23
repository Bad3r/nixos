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
            options.roles = lib.mkOption {
              type = lib.types.attrsOf (lib.types.listOf lib.types.str);
              default = { };
              description = "Role specifications for Home Manager (data only)";
            };
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
        checks = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Flake-level evaluation checks (kept lightweight to avoid builds).";
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
        description = "Aggregated Home Manager modules with freeform roles";
      };

    };
  };

  config.flake = {
    lib = lib.mkDefault { };
    homeManagerModules = lib.mkDefault { };
    nixosModules = lib.mkDefault { };
  };
}
