{
  config,
  lib,
  inputs,
  ...
}:
let
  nm = config.flake.nixosModules;
in
{
  configurations.nixos.system76.module = {
    imports = [
      inputs.nixos-hardware.nixosModules.system76
      nm.workstation
      nm.system76-support
      nm."role-dev"
      nm."role-media"
      nm."role-net"
    ]
    ++ lib.optional (lib.hasAttr "ssh" nm) nm.ssh;
  };

  # Export the System76 configuration so the flake exposes it under nixosConfigurations
  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config) {
    nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ config.configurations.nixos.system76.module ];
    };
  };
}
