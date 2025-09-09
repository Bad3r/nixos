{
  flake.modules.nixos.apps.tokei =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tokei ];
    };
}
