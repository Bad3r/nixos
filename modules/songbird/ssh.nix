_: {
  configurations.nixos.songbird.module = {
    services.openssh = {
      enable = true;
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINptd1paBJhCCHf8L2FolFAcCtzlBJQp6SIi4dLSiP53 root@songbird";
    };
  };
}
