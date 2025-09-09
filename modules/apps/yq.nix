{
  flake.nixosModules.apps.yq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };
}
