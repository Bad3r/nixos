{
  flake.nixosModules.apps.wget =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wget ];
    };
}
