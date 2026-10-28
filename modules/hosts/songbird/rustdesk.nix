_: {
  configurations.nixos.songbird.module = {
    # The iGPU drives no monitor, so encoding there keeps NVENC off the RTX 5080
    # that runs llama.cpp.
    programs.rustdesk.extended.intelEncodeDevice = "/dev/dri/by-path/pci-0000:00:02.0-render";
  };
}
