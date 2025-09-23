{
  flake.nixosModules.apps.dolphin =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.dolphin ];
    };
}
