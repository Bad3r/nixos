{
  flake.modules.nixos.apps.yq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };
}
