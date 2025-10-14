{
  flake.nixosModules.apps."ghostscript-with-X" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ghostscript ];
    };
}
