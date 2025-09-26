{
  flake.nixosModules.apps."bash-completion" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."bash-completion" ];
    };
}
