{
  flake.nixosModules.apps."gst-plugins-good" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gst_all_1."gst-plugins-good" ];
    };
}
