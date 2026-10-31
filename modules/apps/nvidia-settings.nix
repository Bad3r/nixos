/*
  Package: nvidia-settings
  Description: NVIDIA X Server Settings, the driver's GUI and CLI for display, GPU, and PowerMizer settings.
  Homepage: https://github.com/NVIDIA/nvidia-settings
  Documentation: https://github.com/NVIDIA/nvidia-settings#readme
  Repository: https://github.com/NVIDIA/nvidia-settings

  Options:
    -q <attribute>: Query an attribute such as `GPUCoreTemp` or `GPUUtilization`.
    -a <attribute>=<value>: Assign an attribute.
    -t: Print query results without labels.
*/
_:
let
  NvidiaSettingsModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs."nvidia-settings".extended;
    in
    {
      options.programs.nvidia-settings.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nvidia-settings.";
        };
      };

      # Upstream defaults this to true, so the row sets it both ways.
      config.hardware.nvidia.nvidiaSettings = cfg.enable;
    };
in
{
  flake.nixosModules.apps."nvidia-settings" = NvidiaSettingsModule;
}
