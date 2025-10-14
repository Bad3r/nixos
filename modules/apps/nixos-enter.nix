{
  flake.nixosModules.apps."nixos-enter" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-enter" ];
    };
}
