{
  flake.modules.nixos.apps.ktailctl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ktailctl ];
    };
}
