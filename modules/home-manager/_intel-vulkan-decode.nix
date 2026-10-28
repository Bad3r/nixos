# Home Manager side of gpu.intel.vulkanDecode (modules/hosts/common/intel-vulkan-decode.nix),
# imported by path from each consumer so a standalone configuration declares it too.
{
  config,
  lib,
  osConfig,
  ...
}:
let
  enabled = lib.attrByPath [ "gpu" "intel" "vulkanDecode" "enable" ] false osConfig;
  executables = config.gpu.intel.vulkanDecode.executables;
in
{
  options.gpu.intel.vulkanDecode.executables = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Executable paths, as /proc/self/exe resolves them, whose Vulkan loader
      sees only the Intel driver while the host's gpu.intel.vulkanDecode is
      enabled. They land in the loader's per-user vk_loader_settings.json,
      which Vulkan Configurator would otherwise own.
    '';
  };

  config = lib.mkIf (enabled && executables != [ ]) {
    xdg.configFile."vulkan/loader_settings.d/vk_loader_settings.json".text = builtins.toJSON {
      file_format_version = "1.0.0";
      settings_array = [
        {
          app_keys = executables;
          additional_drivers_use_exclusively = true;
          additional_drivers = [
            { path = osConfig.gpu.intel.vulkanDecode.intelIcd; }
          ];
        }
      ];
    };
  };
}
