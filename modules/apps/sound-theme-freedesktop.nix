{
  flake.nixosModules.apps."sound-theme-freedesktop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."sound-theme-freedesktop" ];
    };
}
