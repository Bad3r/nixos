{ config, ... }:
{
  # Media role: aggregate PC-level media modules and defaults (mpv, vlc, toolchain)
  flake.modules.nixos.roles.media.imports = with config.flake.modules.nixos; [
    pc
  ];
}
