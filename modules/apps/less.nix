{
  flake.nixosModules.apps.less =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.less ];
    };
}
