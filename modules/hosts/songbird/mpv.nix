{ lib, ... }:
{
  configurations.nixos.songbird.module =
    { config, pkgs, ... }:
    let
      vulkanDecode = config.gpu.intel.vulkanDecode.enable;
    in
    {
      programs.mpv.extended.package = pkgs.mpv.override {
        extraMakeWrapperArgs =
          lib.concatLists (
            lib.mapAttrsToList (name: value: [
              "--set"
              name
              value
            ]) config.gpu.intel.vulkanDecode.environment
          )
          ++ [
            # The session's LIBVA_DRIVER_NAME=nvidia would load
            # nvidia-vaapi-driver for the iGPU node.
            "--set"
            "LIBVA_DRIVER_NAME"
            "iHD"
          ];
      };

      home-manager.sharedModules = [
        (hm: {
          imports = [ ../../home-manager/_intel-vulkan-decode.nix ];

          gpu.intel.vulkanDecode.executables = [ "${hm.config.programs.mpv.finalPackage.unwrapped}/bin/mpv" ];

          programs.mpv.config = {
            # Under the proprietary NVIDIA driver, vo=gpu-next's default Vulkan
            # backend has deadlocked the GPU on render-context churn (rapid
            # playlist switching) and frozen the session; the GL backend avoids
            # it while keeping vo=gpu-next and profile=high-quality. Not yet
            # re-tested on the RTX 5080 with the open kernel modules: drop the
            # override once Vulkan proves stable here. mpv's Intel-only Vulkan
            # loader filter would then move output to the monitorless iGPU.
            gpu-api = lib.mkDefault "opengl";
            # Decode on the Xe-LPG iGPU; the RTX 5080 only renders. Zero-copy
            # modes would decode on the X screen's device, which is the 5080.
            # Vulkan reads frames back faster than VA-API, whose copy iHD
            # detiles on the CPU on this iGPU; VA-API covers AV1 and a Mesa
            # without the debug flag.
            hwdec = lib.mkForce (
              lib.concatStringsSep "," (lib.optional vulkanDecode "vulkan-copy" ++ [ "vaapi-copy" ])
            );
            vaapi-device = "/dev/dri/by-path/pci-0000:00:02.0-render";
          };
        })
      ];
    };
}
