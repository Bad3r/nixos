{
  flake.nixosModules.apps.ktailctl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ktailctl ];
    };
}
