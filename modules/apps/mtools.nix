{
  flake.nixosModules.apps."mtools" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mtools ];
    };
}
