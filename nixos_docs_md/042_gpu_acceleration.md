## GPU acceleration

**Table of Contents**

[OpenCL](#sec-gpu-accel-opencl)

[Vulkan](#sec-gpu-accel-vulkan)

[VA-API](#sec-gpu-accel-va-api)

[Common issues](#sec-gpu-accel-common-issues)

NixOS provides various APIs that benefit from GPU hardware acceleration, such as VA-API and VDPAU for video playback; OpenGL and Vulkan for 3D graphics; and OpenCL for general-purpose computing. This chapter describes how to set up GPU hardware acceleration (as far as this is not done automatically) and how to verify that hardware acceleration is indeed used.

Most of the aforementioned APIs are agnostic with regards to which display server is used. Consequently, these instructions should apply both to the X Window System and Wayland compositors.
