{ config, ... }:
{
  # Networking role: bring in base + PC networking per-app modules (vpn, tools)
  flake.modules.nixos.roles.net.imports = with config.flake.modules.nixos; [
    base
    pc
  ];
}
