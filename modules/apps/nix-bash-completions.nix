{
  flake.nixosModules.apps."nix-bash-completions" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-bash-completions" ];
    };
}
