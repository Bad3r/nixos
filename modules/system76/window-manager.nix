{ lib, ... }:
let
  exported = import ../apps/i3wm/nixos.nix;
  i3Module = lib.getAttrFromPath [
    "flake"
    "nixosModules"
    "window-manager"
    "i3"
  ] exported;
in
{
  configurations.nixos.system76.module.imports = lib.optional (i3Module != null) i3Module;
}
