{ lib, ... }:
{
  flake.nixosModules.lang.python = {
    programs = {
      python.extended.enable = lib.mkOverride 1050 true;
      uv.extended.enable = lib.mkOverride 1050 true;
      pyright.extended.enable = lib.mkOverride 1050 true;
      ruff.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
