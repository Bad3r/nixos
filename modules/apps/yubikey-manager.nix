{
  flake.nixosModules.apps."yubikey-manager" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."yubikey-manager" ];
    };
}
