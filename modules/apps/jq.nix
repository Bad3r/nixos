{
  flake.modules.nixos.apps.jq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.jq ];
    };
}
