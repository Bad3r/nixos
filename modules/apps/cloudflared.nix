{
  flake.nixosModules.apps.cloudflared =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cloudflared ];
    };
}
