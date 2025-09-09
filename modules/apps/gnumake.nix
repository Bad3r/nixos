{
  flake.modules.nixos.apps.gnumake =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnumake ];
    };
}
