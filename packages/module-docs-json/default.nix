{
  lib,
  pkgs,
  self,
  inputs,
}:
import ../../implementation/module-docs/derivation-json.nix {
  inherit
    lib
    pkgs
    self
    inputs
    ;
  flakeRoot = ../../.;
}
