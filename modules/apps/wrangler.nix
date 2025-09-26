{
  flake.nixosModules.apps.wrangler =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wrangler ];
    };
}
