{ lib, ... }:
{
  flake.nixosModules.lang.go = {
    programs = {
      go.extended.enable = lib.mkOverride 1050 true;
      gopls.extended.enable = lib.mkOverride 1050 true;
      "golangci-lint".extended.enable = lib.mkOverride 1050 true;
      delve.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
