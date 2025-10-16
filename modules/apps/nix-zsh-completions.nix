{
  flake.nixosModules.apps."nix-zsh-completions" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-zsh-completions" ];
    };
}
