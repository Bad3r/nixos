{
  flake.nixosModules.apps."nixos-icons" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-icons" ];
    };
}
