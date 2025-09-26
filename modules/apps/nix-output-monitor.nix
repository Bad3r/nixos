{
  flake.nixosModules.apps."nix-output-monitor" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nix-output-monitor" ];
    };
}
