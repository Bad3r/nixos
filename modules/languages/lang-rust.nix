{ lib, ... }:
{
  flake.nixosModules.lang.rust = {
    programs = {
      rustc.extended.enable = lib.mkOverride 1050 true;
      cargo.extended.enable = lib.mkOverride 1050 true;
      "rust-analyzer".extended.enable = lib.mkOverride 1050 true;
      "rust-clippy".extended.enable = lib.mkOverride 1050 true;
      rustfmt.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
