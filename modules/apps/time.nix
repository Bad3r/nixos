{
  flake.nixosModules.apps."time" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.time ];
    };
}
