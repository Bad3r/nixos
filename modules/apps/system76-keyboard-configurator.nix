{
  flake.nixosModules.apps."system76-keyboard-configurator" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."system76-keyboard-configurator" ];
    };
}
