# The `nixos` sbx base: a headless guest that sbx reaches over SSH on vsock
# and through qemu-ga. It carries no secrets; each sandbox's root key arrives
# as a systemd credential over fw_cfg.
{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

  boot = {
    # fw_cfg credentials reach systemd only when the initrd carries this module.
    initrd.kernelModules = [ "qemu_fw_cfg" ];
    kernelParams = [
      "console=tty0"
      "console=ttyS0"
    ];
    loader.timeout = 0;
  };

  networking.hostName = "sbx";

  services.qemuGuest.enable = true;
  # systemd-ssh-generator adds sshd-vsock.socket on AF_VSOCK.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users = {
    mutableUsers = false;
    # Root's key arrives at boot as the credential, which this check cannot see.
    allowNoPasswordLogin = true;
  };

  environment.systemPackages = with pkgs; [
    file
    git
    python3
    unzip
  ];

  documentation.enable = false;

  system.stateVersion = lib.trivial.release;
}
