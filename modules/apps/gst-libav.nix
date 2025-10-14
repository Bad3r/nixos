{
  flake.nixosModules.apps."gst-libav" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gst_all_1."gst-libav" ];
    };
}
