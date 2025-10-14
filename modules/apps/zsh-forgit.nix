{
  flake.nixosModules.apps."zsh-forgit" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."zsh-forgit" ];
    };
}
