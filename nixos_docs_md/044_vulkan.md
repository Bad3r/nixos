## Vulkan

[Vulkan](<https://en.wikipedia.org/wiki/Vulkan_(API)>) is a graphics and compute API for GPUs. It is used directly by games or indirectly though compatibility layers like [DXVK](https://github.com/doitsujin/dxvk/wiki).

By default, if [`hardware.graphics.enable`](options.html#opt-hardware.graphics.enable) is enabled, Mesa is installed and provides Vulkan for supported hardware.

Similar to OpenCL, Vulkan drivers are loaded through the _Installable Client Driver_ (ICD) mechanism. ICD files for Vulkan are JSON files that specify the path to the driver library and the supported Vulkan version. All successfully loaded drivers are exposed to the application as different GPUs. In NixOS, there are two ways to make ICD files visible to Vulkan applications: an environment variable and a module option.

The first option is through the `VK_ICD_FILENAMES` environment variable. This variable can contain multiple JSON files, separated by `:`. For example:

```programlisting
$ export \
  VK_ICD_FILENAMES=`nix-build '<nixpkgs>' --no-out-link -A amdvlk`/share/vulkan/icd.d/amd_icd64.json
```

The second mechanism is to add the Vulkan driver package to [`hardware.graphics.extraPackages`](options.html#opt-hardware.graphics.extraPackages). This links the ICD file under `/run/opengl-driver`, where it will be visible to the ICD loader.

The proper installation of Vulkan drivers can be verified through the `vulkaninfo` command of the vulkan-tools package. This command will report the hardware devices and drivers found, in this example output amdvlk and radv:

```programlisting
$ vulkaninfo | grep GPU
                GPU id  : 0 (Unknown AMD GPU)
                GPU id  : 1 (AMD RADV NAVI10 (LLVM 9.0.1))
     ...
GPU0:
        deviceType     = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
        deviceName     = Unknown AMD GPU
GPU1:
        deviceType     = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
```

A simple graphical application that uses Vulkan is `vkcube` from the vulkan-tools package.

### AMD

Modern AMD [Graphics Core Next](https://en.wikipedia.org/wiki/Graphics_Core_Next) (GCN) GPUs are supported through either radv, which is part of mesa, or the amdvlk package. Adding the amdvlk package to [`hardware.graphics.extraPackages`](options.html#opt-hardware.graphics.extraPackages) makes amdvlk the default driver and hides radv and lavapipe from the device list. A specific driver can be forced as follows:

```programlisting
{
  hardware.graphics.extraPackages = [ pkgs.amdvlk ];

  # To enable Vulkan support for 32-bit applications, also add:

  hardware.graphics.extraPackages32 = [ pkgs.driversi686Linux.amdvlk ];

  # Force radv

  environment.variables.AMD_VULKAN_ICD = "RADV";
  # Or

  environment.variables.VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
}
```
