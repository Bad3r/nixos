{
  flake.modules.nixos.apps.httpie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpie ];
    };
}
