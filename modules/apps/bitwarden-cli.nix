{
  flake.nixosModules.apps."bitwarden-cli" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."bitwarden-cli" ];
    };
}
