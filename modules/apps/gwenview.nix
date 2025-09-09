{
  flake.modules.nixos.apps.gwenview =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.gwenview ];
    };
}
