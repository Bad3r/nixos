{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 media tools.") config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

  mediaAppNames = [
    "mpv"
    "media-toolchain"
  ];

  mediaModule = lib.attrByPath [ "flake" "nixosModules" "media" ] null config;
  optionalImports = lib.optional (mediaModule != null) mediaModule;
in
{
  configurations.nixos.system76.module.imports = getApps mediaAppNames ++ optionalImports;
}
