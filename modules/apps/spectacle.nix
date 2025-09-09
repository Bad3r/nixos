{
  flake.modules.nixos.apps.spectacle =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.spectacle ];
    };
}
