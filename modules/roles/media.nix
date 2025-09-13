{ config, lib, ... }:
{
  # Media role: aggregate media apps via robust lookup to avoid import ordering issues.
  flake.nixosModules.roles.media.imports =
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
      apps = map getApp (lib.filter hasApp names);
    in
    apps
    # Optionally include a top-level 'media' defaults module if present
    ++ lib.optional (lib.hasAttr "media" config.flake.nixosModules) config.flake.nixosModules.media;

  # Stable alias for host imports
  flake.nixosModules."role-media".imports = config.flake.nixosModules.roles.media.imports;
}
