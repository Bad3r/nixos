{
  flake.nixosModules.apps.mitmproxy =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mitmproxy ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mitmproxy ];
    };
}
