{
  flake.nixosModules.apps."cloudflare-warp" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."cloudflare-warp" ];
    };
}
