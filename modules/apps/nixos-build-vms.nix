{
  flake.nixosModules.apps."nixos-build-vms" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-build-vms" ];
    };
}
