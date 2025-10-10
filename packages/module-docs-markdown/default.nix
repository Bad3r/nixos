{
  lib,
  pkgs,
  self,
  ...
}:
import ../../implementation/module-docs/derivation-markdown.nix {
  inherit
    lib
    pkgs
    self
    ;
  flakeRoot = ../../.;
}
