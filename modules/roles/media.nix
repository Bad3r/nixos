{ config, lib, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
  names = [
    "mpv"
    "vlc"
    "okular"
    "gwenview"
    "spectacle"
  ];
  roleImports =
    getApps names
    ++ lib.optional (lib.hasAttr "media" config.flake.nixosModules) config.flake.nixosModules.media;
in
{
  # Media role: aggregate media apps via robust lookup to avoid import ordering issues.
  flake.nixosModules.roles.media.imports = roleImports;

  # Stable alias for host imports (avoid self-referencing nested aggregator)
  flake.nixosModules."role-media".imports = roleImports;
}
