{
  flake.nixosModules.apps."lightdm" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lightdm ];
    };
}
