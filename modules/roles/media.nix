{ config, ... }:
{
  # Media role: aggregate media apps and defaults precisely
  flake.nixosModules.roles.media.imports =
    (with config.flake.nixosModules.apps; [
      mpv
      vlc
      okular
      gwenview
      spectacle
    ])
    ++ (with config.flake.nixosModules; [
      # Include media toolchain defaults
      media
    ]);
}
