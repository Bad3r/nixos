# App rows as the i3 Home Manager modules read them from the host config. A
# module's finalPackage is defined only while its row is on, so an off row
# yields the row's package option instead.
{
  lib,
  osConfig,
  pkgs,
}:
let
  row = name: lib.attrByPath [ "programs" name "extended" ] { } osConfig;
in
{
  enabled = name: (row name).enable or false;

  package =
    name:
    let
      cfg = row name;
    in
    if (cfg.enable or false) && cfg ? finalPackage then
      cfg.finalPackage
    else
      cfg.package or pkgs.${name};
}
