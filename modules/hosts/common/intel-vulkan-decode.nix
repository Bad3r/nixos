/*
  Vulkan video decode on the Intel iGPU of a host whose display runs on
  another GPU. An app opts in twice: its wrapper takes
  gpu.intel.vulkanDecode.environment, and its Home Manager config lists its
  executables in gpu.intel.vulkanDecode.executables
  (modules/home-manager/_intel-vulkan-decode.nix), for which a per-user Vulkan
  loader settings file loads only the Intel driver. Gecko's wrapper also
  exports loaderSettingsDir, a global Intel-only store file that the readable
  per-user file shadows; only processes that cannot read $HOME (the sandboxed
  RDD) fall through to it.

  FFmpeg (mpv) takes Vulkan device 0 and Gecko prefers the device that matches
  its compositor (SelectVulkanDecoderPhysicalDevice in
  FFmpegVulkanVideoDecoder.cpp); both are the discrete card here, so the other
  drivers have to be hidden rather than reordered (MESA_VK_DEVICE_SELECT would
  move mpv but not Gecko). The per-user file matches the process's
  /proc/self/exe, so apps those executables launch, such as a browser's URL
  handlers, match no key and keep every driver while that file exists.
*/
_:
let
  body =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.gpu.intel.vulkanDecode;
    in
    {
      options.gpu.intel.vulkanDecode = {
        enable = lib.mkEnableOption "Vulkan video decode on the Intel iGPU for the apps that consume it";

        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          default = lib.optionalAttrs cfg.enable {
            # Drop once Mesa exposes anv video decode without the debug flag.
            ANV_DEBUG = "video-decode";
          };
          defaultText = lib.literalMD "anv's video-decode debug flag when `enable` is set, else `{ }`";
          description = ''
            Environment for the wrapper of an app that decodes video through
            Vulkan on the Intel iGPU. It reaches the processes the app
            launches, where it only adds video queues to the Intel device.
          '';
        };

        intelIcd = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "${pkgs.addDriverRunpath.driverLink}/share/vulkan/icd.d/intel_icd.x86_64.json";
          description = "The Intel Vulkan driver manifest the loader filters keep.";
        };

        loaderSettingsDir = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          readOnly = true;
          default =
            if cfg.enable then
              pkgs.writeTextDir "vulkan/loader_settings.d/vk_loader_settings.json" (
                builtins.toJSON {
                  file_format_version = "1.0.0";
                  settings_array = [
                    {
                      additional_drivers_use_exclusively = true;
                      additional_drivers = [ { path = cfg.intelIcd; } ];
                    }
                  ];
                }
              )
            else
              null;
          defaultText = lib.literalMD "a store directory with a global Intel-only loader settings file when `enable` is set, else `null`";
          description = ''
            XDG config directory holding a Vulkan loader settings file that
            applies to every process reading it, for a wrapper to put first
            in XDG_CONFIG_DIRS. vulkan-loader 1.4.363 finds only the first
            element of that list.
          '';
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
  flake.homeManagerModules.base.imports = [ ../../home-manager/_intel-vulkan-decode.nix ];
}
