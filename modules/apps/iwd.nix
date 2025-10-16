{
  flake.nixosModules.apps."iwd" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iwd ];
    };
}
