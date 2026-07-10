_: {
  flake.lib.nixos.hosts.system76 = {
    # Primary fleet endpoint: registry consumers (ssh-hosts, tailscale)
    # point their default aliases at this machine. Hand off by moving
    # these two keys to the successor host's policy.nix.
    primary = true;
    tailnetIp = "100.64.1.5";
  };
}
