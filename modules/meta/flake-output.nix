{ lib, ... }:
{
  # Allow modules to cooperatively contribute to flake.lib.meta and
  # Home Manager role/module aggregators in one options attrset.
  options = {
    flake = {
      lib = {
        meta = lib.mkOption {
          type = lib.types.anything;
          default = { };
          description = "Flake metadata exposed under flake.lib.meta";
        };
        # Home Manager role specifications as data (not modules):
        # role name -> list of app names (symbols under flake.homeManagerModules.apps)
        homeManager.roles = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf lib.types.str);
          default = { };
          description = "Role specifications for Home Manager (data only)";
        };
      };

      # Declare mergeable option schema for flake.nixosModules so that
      # multiple files can contribute NixOS modules without conflicting definitions.
      nixosModules = lib.mkOption {
        type = lib.types.submodule {
          # Allow arbitrary nested namespaces of deferred modules
          freeformType = lib.types.attrsOf lib.types.deferredModule;
          options = {
            # Commonly-used nested namespaces (explicit for documentation/IDE help)
            apps = lib.mkOption {
              type = lib.types.attrsOf lib.types.deferredModule;
              default = { };
              description = "Per-app NixOS modules (merged by name)";
            };
            roles = lib.mkOption {
              type = lib.types.attrsOf lib.types.deferredModule;
              default = { };
              description = "Role aggregators for NixOS (merged by name)";
            };
          };
        };
        default = { };
        description = "Aggregated NixOS modules with freeform nested namespaces";
      };

      # Declare mergeable option schema for flake.homeManagerModules so that
      # multiple files can contribute modules without conflicting definitions.
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

  # No legacy `flake.modules` output; avoid unknown flake output warnings.
}
