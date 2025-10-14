{
  flake.nixosModules.apps."gst-plugins-bad" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gst_all_1."gst-plugins-bad" ];
    };
}
