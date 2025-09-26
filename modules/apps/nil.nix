{
  flake.nixosModules.apps.nil =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nil ];
    };
}
