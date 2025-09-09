{
  flake.modules.nixos.apps.nodejs_22 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nodejs_22 ];
    };
}
