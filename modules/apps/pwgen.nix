{
  flake.nixosModules.apps."pwgen" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pwgen ];
    };
}
