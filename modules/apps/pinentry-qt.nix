{
  flake.nixosModules.apps."pinentry-qt" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."pinentry-qt" ];
    };
}
