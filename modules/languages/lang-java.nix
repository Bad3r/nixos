{ lib, ... }:
{
  flake.nixosModules.lang.java = {
    programs = {
      "temurin-bin-25".extended.enable = lib.mkOverride 1050 true;
    };
  };
}
