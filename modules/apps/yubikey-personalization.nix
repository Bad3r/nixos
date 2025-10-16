{
  flake.nixosModules.apps."yubikey-personalization" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."yubikey-personalization" ];
    };
}
