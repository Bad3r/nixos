{
  flake.nixosModules.apps.coreutils =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.coreutils ];
    };
}
