{
  flake ? builtins.getFlake (toString ./..),
  lib ? flake.inputs.nixpkgs.lib,
}:
let
  optionStub =
    { lib, ... }@args:
    let
      useStub = (args ? forceStubBootstrap) && args.forceStubBootstrap;
    in
    lib.mkIf useStub {
      options.flake.nixosModules = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.deferredModule;
        default = { };
        description = "Debug stub: defines flake.nixosModules so downstream modules can assign into it.";
      };
      config.flake.nixosModules = lib.mkDefault { };
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
