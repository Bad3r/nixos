{
  flake.nixosModules.apps."bash-interactive" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bashInteractive ];
    };
}
