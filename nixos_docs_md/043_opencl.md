## OpenCL

[OpenCL](https://en.wikipedia.org/wiki/OpenCL) is a general compute API. It is used by various applications such as Blender and Darktable to accelerate certain operations.

OpenCL applications load drivers through the _Installable Client Driver_ (ICD) mechanism. In this mechanism, an ICD file specifies the path to the OpenCL driver for a particular GPU family. In NixOS, there are two ways to make ICD files visible to the ICD loader. The first is through the `OCL_ICD_VENDORS` environment variable. This variable can contain a directory which is scanned by the ICL loader for ICD files. For example:

```programlisting
$ export \
  OCL_ICD_VENDORS=`nix-build '<nixpkgs>' --no-out-link -A rocmPackages.clr.icd`/etc/OpenCL/vendors/
```

The second mechanism is to add the OpenCL driver package to [`hardware.graphics.extraPackages`](options.html#opt-hardware.graphics.extraPackages). This links the ICD file under `/run/opengl-driver`, where it will be visible to the ICD loader.

The proper installation of OpenCL drivers can be verified through the `clinfo` command of the clinfo package. This command will report the number of hardware devices that is found and give detailed information for each device:

```programlisting
$ clinfo | head -n3
Number of platforms  1
Platform Name        AMD Accelerated Parallel Processing
Platform Vendor      Advanced Micro Devices, Inc.
```

### AMD

Modern AMD [Graphics Core Next](https://en.wikipedia.org/wiki/Graphics_Core_Next) (GCN) GPUs are supported through the rocmPackages.clr.icd package. Adding this package to [`hardware.graphics.extraPackages`](options.html#opt-hardware.graphics.extraPackages) enables OpenCL support:

```programlisting
{ hardware.graphics.extraPackages = [ rocmPackages.clr.icd ]; }
```

### Intel

[Intel Gen12 and later GPUs](https://en.wikipedia.org/wiki/List_of_Intel_graphics_processing_units#Gen12) are supported by the Intel NEO OpenCL runtime that is provided by the `intel-compute-runtime` package. The previous generations (8,9 and 11), have been moved to the `intel-compute-runtime-legacy1` package. The proprietary Intel OpenCL runtime, in the `intel-ocl` package, is an alternative for Gen7 GPUs.

Both `intel-compute-runtime` packages, as well as the `intel-ocl` package can be added to [`hardware.graphics.extraPackages`](options.html#opt-hardware.graphics.extraPackages) to enable OpenCL support. For example, for Gen12 and later GPUs, the following configuration can be used:

```programlisting
{ hardware.graphics.extraPackages = [ intel-compute-runtime ]; }
```
