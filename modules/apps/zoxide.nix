{
  flake.nixosModules.apps.zoxide =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.zoxide ];
    };
}
