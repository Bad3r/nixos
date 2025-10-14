{
  flake.nixosModules.apps."wireshark-qt" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."wireshark-qt" ];
    };
}
