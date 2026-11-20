client:
{ config, lib, ... }:
let
  catalog = import ./_plugins.nix;
  cfg = config.programs.${client}.extended;
in
{
  options.programs.${client}.extended.plugins = lib.mkOption {
    description = "Plugin enablement for ${client}, keyed by plugin@marketplace. Null omits an entry.";
    default = { };
    type = lib.types.submodule {
      options = lib.mapAttrs (
        key: plugin:
        assert lib.assertMsg (
          builtins.match "[^@]+@[^@]+" key != null
        ) "Invalid plugin key '${key}' in modules/agents/_plugins.nix; expected plugin@marketplace";
        lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = plugin.${client} or null;
          description = "Whether ${client} enables this plugin.";
        }
      ) catalog;
    };
    apply = lib.filterAttrs (_: enabled: enabled != null);
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge (
      lib.mapAttrsToList (
        key: plugin:
        lib.mkIf (cfg.plugins.${key} or false) {
          programs.${plugin.program}.extended.enable = lib.mkOverride 1050 true;
        }
      ) (lib.filterAttrs (_: plugin: plugin ? program) catalog)
    )
  );
}
