{
  flake ? builtins.getFlake (toString ./..),
  lib ? flake.inputs.nixpkgs.lib,
}:
let
  optionStub =
    { lib, ... }:
    {
      options.flake.nixosModules = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.anything;
        default = { };
        description = "Debug stub: defines flake.nixosModules so downstream modules can assign into it.";
      };
      options.flake.lib = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Debug stub: allows modules to write helpers under flake.lib.*";
      };
      config.flake.nixosModules = lib.mkDefault { };
      config.flake.lib = lib.mkDefault { };
    };

  roleModule =
    { lib, ... }:
    {
      config.flake.nixosModules.roles = {
        xserver = {
          imports = [
            (_: { })
          ];
        };
      };
    };

  evalWithoutStub = builtins.tryEval (
    lib.evalModules {
      modules = [ roleModule ];
      specialArgs = { inherit lib; };
    }
  );

  evalWithStub = builtins.tryEval (
    lib.evalModules {
      modules = [
        optionStub
        roleModule
      ];
      specialArgs = { inherit lib; };
    }
  );
in
{
  inherit
    optionStub
    roleModule
    evalWithoutStub
    evalWithStub
    ;
}
