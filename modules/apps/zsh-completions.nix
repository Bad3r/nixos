{
  flake.nixosModules.apps."zsh-completions" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."zsh-completions" ];
    };
}
