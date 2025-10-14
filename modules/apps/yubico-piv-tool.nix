{
  flake.nixosModules.apps."yubico-piv-tool" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."yubico-piv-tool" ];
    };
}
