{
  flake.modules.nixos.apps.mitmproxy =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mitmproxy ];
    };
}
