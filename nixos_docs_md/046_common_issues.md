## Common issues

### User permissions

Except where noted explicitly, it should not be necessary to adjust user permissions to use these acceleration APIs. In the default configuration, GPU devices have world-read/write permissions (`/dev/dri/renderD*`) or are tagged as `uaccess` (`/dev/dri/card*`). The access control lists of devices with the `uaccess` tag will be updated automatically when a user logs in through `systemd-logind`. For example, if the user _alice_ is logged in, the access control list should look as follows:

```programlisting
$ getfacl /dev/dri/card0

# file: dev/dri/card0

# owner: root

# group: video

user::rw-
user:alice:rw-
group::rw-
mask::rw-
other::---
```

If you disabled (this functionality of) `systemd-logind`, you may need to add the user to the `video` group and log in again.

### Mixing different versions of nixpkgs

The _Installable Client Driver_ (ICD) mechanism used by OpenCL and Vulkan loads runtimes into its address space using `dlopen`. Mixing an ICD loader mechanism and runtimes from different version of nixpkgs may not work. For example, if the ICD loader uses an older version of glibc than the runtime, the runtime may not be loadable due to missing symbols. Unfortunately, the loader will generally be quiet about such issues.

If you suspect that you are running into library version mismatches between an ICL loader and a runtime, you could run an application with the `LD_DEBUG` variable set to get more diagnostic information. For example, OpenCL can be tested with `LD_DEBUG=files clinfo`, which should report missing symbols.
