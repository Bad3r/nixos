{
  flake.nixosModules.apps."steam-run" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."steam-run" ];
    };
}
