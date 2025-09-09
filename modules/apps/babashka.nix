{
  flake.modules.nixos.apps.babashka =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.babashka ];
    };
}
