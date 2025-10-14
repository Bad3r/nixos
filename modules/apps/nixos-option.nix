{
  flake.nixosModules.apps."nixos-option" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-option" ];
    };
}
