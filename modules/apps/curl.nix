{
  flake.nixosModules.apps.curl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curl ];
    };
}
