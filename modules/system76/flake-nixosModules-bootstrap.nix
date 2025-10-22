{ lib, ... }@args:
let
  flag = (args ? system76NeedsFlakeBootstrap) && args.system76NeedsFlakeBootstrap;
in
if flag then
  {
    options.flake.nixosModules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      apply = lib.mapAttrs (
        name: value: {
          _file = "flake.nixosModules.${name}";
          imports = [ value ];
        }
      );
      description = "NixOS modules published under flake.nixosModules.";
    };
  }
else
  { }
