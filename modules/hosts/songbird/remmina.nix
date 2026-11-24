_: {
  configurations.nixos.songbird.module = {
    # The iGPU drives no monitor, so RDP decoding there stays off the RTX 5080.
    programs.remmina.extended.intelDecodeDevice = "/dev/dri/by-path/pci-0000:00:02.0-render";
  };
}
