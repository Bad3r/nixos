{ config, lib, ... }:
let
  flakeAttrs = config.flake or { };
  hmModules = flakeAttrs.homeManagerModules or { };
  hmGuiModule = lib.attrByPath [ "gui" ] null hmModules;
  hmAppModules = hmModules.apps or { };
  extraNames = lib.attrByPath [ "home-manager" "extraAppImports" ] [ ] config;
  getAppModule =
    name:
    let
      module = lib.attrByPath [ name ] null hmAppModules;
    in
    if module != null then
      module
    else
      throw "Unknown Home Manager app '${name}' referenced while wiring System76 GUI modules";
  extraAppModules = map getAppModule extraNames;
in
{
  configurations.nixos.system76.module = lib.mkIf (hmGuiModule != null) {
    home-manager.sharedModules = lib.mkAfter ([ hmGuiModule ] ++ extraAppModules);
  };
}
