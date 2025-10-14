{
  flake.nixosModules.apps."tumbler" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xfce.tumbler ];
    };
}
