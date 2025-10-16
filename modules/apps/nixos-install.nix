{
  flake.nixosModules.apps."nixos-install" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-install" ];
    };
}
