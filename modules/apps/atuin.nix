{
  flake.nixosModules.apps.atuin =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.atuin ];
    };
}
