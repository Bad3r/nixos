{
  lib,
  pkgs,
  self,
  inputs,
}:
import ../../implementation/module-docs/derivation-markdown.nix {
  inherit
    lib
    pkgs
    self
    inputs
    ;
  flakeRoot = ../../.;
}
