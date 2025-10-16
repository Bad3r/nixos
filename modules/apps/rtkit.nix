{
  flake.nixosModules.apps."rtkit" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rtkit ];
    };
}
