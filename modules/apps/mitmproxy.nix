{
  flake.nixosModules.apps.mitmproxy =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mitmproxy ];
    };
}
