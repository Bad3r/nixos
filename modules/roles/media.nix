{ config, lib, ... }:
{
  # Media role: aggregate media apps and optional defaults (if defined)
  flake.nixosModules.roles.media.imports =
    (with config.flake.nixosModules.apps; [
      mpv
      vlc
      okular
      gwenview
      spectacle
    ])
    # Optionally include a top-level 'media' defaults module if present
    ++ lib.optional (lib.hasAttr "media" config.flake.nixosModules) config.flake.nixosModules.media;
}
