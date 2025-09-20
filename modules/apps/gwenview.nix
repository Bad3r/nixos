{
  flake.nixosModules.apps.gwenview =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.gwenview ];
    };
}
