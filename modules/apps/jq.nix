{
  flake.nixosModules.apps.jq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jq ];
    };
}
