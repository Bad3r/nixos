{
  flake.nixosModules.apps.terraform =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.terraform ];
    };
}
