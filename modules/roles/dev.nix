{ config, ... }:
{
  # Development role: aggregate workstation-related per-app modules
  flake.modules.nixos.roles.dev.imports = with config.flake.modules.nixos; [
    workstation
  ];
}
