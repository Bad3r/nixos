{
  flake.nixosModules.apps."gstreamer-vaapi" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gst_all_1."gst-vaapi" ];
    };
}
