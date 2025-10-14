{
  flake.nixosModules.apps."nixos-rebuild-ng" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-rebuild-ng" ];
    };
}
