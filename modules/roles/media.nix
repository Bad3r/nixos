{ config, lib, ... }:
let
  names = [
    "mpv"
    "vlc"
    "okular"
    "gwenview"
    "spectacle"
  ];
  hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules;
  getApp = name: lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules;
  roleImports =
    (map getApp (lib.filter hasApp names))
    ++ lib.optional (lib.hasAttr "media" config.flake.nixosModules) config.flake.nixosModules.media;
in
{
  # Media role: aggregate media apps via robust lookup to avoid import ordering issues.
  flake.nixosModules.roles.media.imports = roleImports;

  # Stable alias for host imports (avoid self-referencing nested aggregator)
  flake.nixosModules."role-media".imports = roleImports;
}
