/*
  Package: nvidia-settings
  Description: NVIDIA X Server Settings, the driver's GUI and CLI for display, GPU, and PowerMizer settings.
  Homepage: https://github.com/NVIDIA/nvidia-settings
  Documentation: https://github.com/NVIDIA/nvidia-settings#readme
  Repository: https://github.com/NVIDIA/nvidia-settings

  Summary:
    * Drives `hardware.nvidia.nvidiaSettings`, so the installed build is the one that matches `hardware.nvidia.package`.
    * Installs nothing on a host without the NVIDIA driver.

  Options:
    -q <attribute>: Query an attribute such as `GPUCoreTemp` or `GPUUtilization`.
    -a <attribute>=<value>: Assign an attribute.
    -t: Print query results without labels.

  Example Usage:
    * `nvidia-settings` -- Open the settings window.
    * `nvidia-settings -q GPUUtilization -t` -- Print the GPU utilization counters.
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
