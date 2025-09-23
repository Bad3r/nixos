{
  flake.nixosModules.apps.firefox =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.firefox ];
    };
}
