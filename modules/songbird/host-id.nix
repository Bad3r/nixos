_: {
  configurations.nixos.songbird.module = {
    # head -c 8 /etc/machine-id on the installed host.
    networking.hostId = "c93b3b3c";
  };
}
