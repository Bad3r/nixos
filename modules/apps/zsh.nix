{
  flake.nixosModules.apps."zsh" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.zsh ];
    };
}
