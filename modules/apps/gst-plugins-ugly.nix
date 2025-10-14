{
  flake.nixosModules.apps."gst-plugins-ugly" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gst_all_1."gst-plugins-ugly" ];
    };
}
