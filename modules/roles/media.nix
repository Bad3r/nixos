{ config, ... }:
{
  # Media role: aggregate media apps and defaults precisely
  flake.modules.nixos.roles.media.imports =
    (with config.flake.modules.nixos.apps; [
      mpv
      vlc
      okular
      gwenview
      spectacle
    ])
    ++ (with config.flake.modules.nixos; [
      # Include media toolchain defaults
      media
    ]);
}
