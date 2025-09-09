{
  flake.modules.nixos.apps.httpx =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpx ];
    };
}
